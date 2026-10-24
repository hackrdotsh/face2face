#if DEBUG
    import CoreBluetooth
    import Face2FaceCore
    import Foundation
    import Observation

    struct DiscoveryLogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }

    /// Explicitly started experiments. Only the timed anonymous Pocket mode opts into restoration.
    @MainActor
    @Observable
    final class BluetoothDiscoveryService: NSObject {
        private static weak var activeOwner: BluetoothDiscoveryService?
        private static let serviceID = CBUUID(string: "C5D1A704-9D2E-4B29-A541-2C3138E64001")
        private static let tokenID = CBUUID(string: "C5D1A704-9D2E-4B29-A541-2C3138E64002")
        private static let exchangeTimeout: TimeInterval = 8
        private static let retryLimit = 3
        private static let candidateLimit = 32

        #if targetEnvironment(simulator)
            static let isSimulator = true
        #else
            static let isSimulator = false
        #endif

        private(set) var isPocketMode = false
        private(set) var isApplicationActive = true
        private(set) var isRestorationPending = false
        private(set) var restorationCallbacks = 0
        private(set) var isRequested = false
        private(set) var isScanning = false
        private(set) var isAdvertising = false
        private(set) var bluetoothStatus = "Not requested"
        private(set) var status = "Stopped"
        private(set) var exchangeStatus = "Idle"
        private(set) var lastIssue: String?
        private(set) var session: DiscoverySession?
        private(set) var events: [DiscoveryLogEntry] = []

        @ObservationIgnored var onEncounter: ((DiscoveryEncounter) -> Void)?
        @ObservationIgnored var onStopped: (() -> Void)?
        @ObservationIgnored var onRestored: (() -> Void)?
        @ObservationIgnored private var pocketWindow: PocketTestWindow?
        @ObservationIgnored private var pocketExpiry: Task<Void, Never>?
        @ObservationIgnored private var centralStateReported = false
        @ObservationIgnored private var advertiserStateReported = false
        @ObservationIgnored private var restoredConnections: [CBPeripheral] = []
        @ObservationIgnored private var resetRestoredPeripheral = false
        @ObservationIgnored private var generation = UUID()
        @ObservationIgnored private var central: CBCentralManager?
        @ObservationIgnored private var advertiser: CBPeripheralManager?
        @ObservationIgnored private var publishedService: CBMutableService?
        @ObservationIgnored private var serviceReady = false
        @ObservationIgnored private var advertisingPending = false
        @ObservationIgnored private var candidates: [UUID: Candidate] = [:]
        @ObservationIgnored private var outbound: Exchange?
        @ObservationIgnored private var inboundReads: [UUID: Date] = [:]
        @ObservationIgnored private var heartbeat: Task<Void, Never>?

        @MainActor
        private final class Candidate {
            let peripheral: CBPeripheral
            var lastSeen = Date()
            var nextAttempt = Date()
            var attempts = 0

            init(_ peripheral: CBPeripheral) {
                self.peripheral = peripheral
            }
        }

        @MainActor
        private final class Exchange {
            enum Phase {
                case connecting, services, characteristic, reading, writing, disconnecting
            }

            let peripheral: CBPeripheral
            let localToken: DiscoveryToken
            let generation: UUID
            var peerToken: DiscoveryToken?
            var phase = Phase.connecting
            var deadline = Date().addingTimeInterval(BluetoothDiscoveryService.exchangeTimeout)

            init(peripheral: CBPeripheral, localToken: DiscoveryToken, generation: UUID) {
                self.peripheral = peripheral
                self.localToken = localToken
                self.generation = generation
            }
        }

        deinit {
            heartbeat?.cancel()
            pocketExpiry?.cancel()
        }

        func start(token: DiscoveryToken = DiscoveryToken(), pocketWindow: PocketTestWindow? = nil) {
            guard !isRequested, !isRestorationPending, !Self.isSimulator else { return }
            if let pocketWindow, pocketWindow.remaining(uptime: ProcessInfo.processInfo.systemUptime) <= 0 {
                return
            }
            if let owner = Self.activeOwner, owner !== self {
                owner.stop(reason: "Another discovery test was started")
            }
            Self.activeOwner = self
            self.pocketWindow = pocketWindow
            isPocketMode = pocketWindow != nil
            restorationCallbacks = 0
            generation = UUID()
            session = DiscoverySession(token: token, startedAt: pocketWindow?.startedAt ?? Date())
            events = []
            lastIssue = nil
            isRequested = true
            status = "Starting discovery"
            bluetoothStatus = "Checking Bluetooth"
            log("Started a fresh anonymous test session.")
            makeManagers(restorable: isPocketMode)
            startHeartbeat()
            schedulePocketExpiry()
        }

        private func makeManagers(restorable: Bool) {
            centralStateReported = false
            advertiserStateReported = false
            var centralOptions: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: false]
            var peripheralOptions: [String: Any] = [CBPeripheralManagerOptionShowPowerAlertKey: false]
            if restorable {
                centralOptions[CBCentralManagerOptionRestoreIdentifierKey] =
                    "sh.hackr.face2face.pocket.central.v1"
                peripheralOptions[CBPeripheralManagerOptionRestoreIdentifierKey] =
                    "sh.hackr.face2face.pocket.peripheral.v1"
            }
            central = CBCentralManager(delegate: self, queue: .main, options: centralOptions)
            advertiser = CBPeripheralManager(delegate: self, queue: .main, options: peripheralOptions)
        }

        private func startHeartbeat() {
            heartbeat?.cancel()
            heartbeat = nil
            guard isApplicationActive else { return }
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(0.5)) } catch { return }
                    guard let self else { return }
                    self.tick()
                }
            }
        }

        private var consentIsCurrent: Bool {
            guard let pocketWindow else { return true }
            return pocketWindow.remaining(uptime: ProcessInfo.processInfo.systemUptime) > 0
        }

        private func allowRadioOperations() -> Bool {
            guard isRequested else { return false }
            guard consentIsCurrent else {
                stop(reason: "Five-minute Pocket test expired")
                return false
            }
            return true
        }

        private func schedulePocketExpiry() {
            pocketExpiry?.cancel()
            guard let pocketWindow else { return }
            let remaining = pocketWindow.remaining(uptime: ProcessInfo.processInfo.systemUptime)
            pocketExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard let self, self.pocketWindow?.id == pocketWindow.id else { return }
                self.stop(reason: "Five-minute Pocket test expired")
            }
        }

        func setApplicationActive(_ active: Bool) {
            isApplicationActive = active
            guard isPocketMode, allowRadioOperations() else { return }
            if active {
                startHeartbeat()
                tick()
                log("App foregrounded; foreground retry timer enabled.")
            } else {
                heartbeat?.cancel()
                heartbeat = nil
                log("App backgrounded; radio work now depends on Bluetooth callbacks.")
            }
            guard isRequested, central?.state == .poweredOn else { return }
            central?.stopScan()
            isScanning = false
            startRadiosIfReady()
        }

        /// Prepare managers at launch, but never start a scan merely because a checkpoint exists.
        func prepareForRestoration(window: PocketTestWindow, applicationActive: Bool) {
            guard !Self.isSimulator, !isRequested, central == nil else { return }
            guard window.remaining(uptime: ProcessInfo.processInfo.systemUptime) > 0 else {
                status = "Saved Pocket consent expired"
                onStopped?()
                return
            }
            pocketWindow = window
            isPocketMode = true
            isApplicationActive = applicationActive
            isRestorationPending = true
            restorationCallbacks = 0
            generation = UUID()
            // No token is persisted. An OS restoration receives a fresh anonymous test code.
            session = DiscoverySession(startedAt: window.startedAt)
            status = "Checking iOS radio restoration state"
            log("Prepared restoration managers; no scan has been requested.")
            schedulePocketExpiry()
            makeManagers(restorable: true)
        }

        private func acceptRestoration(_ description: String) -> Bool {
            guard isPocketMode, pocketWindow != nil, consentIsCurrent else {
                stop(reason: "Restoration refused because consent expired")
                return false
            }
            guard Self.activeOwner == nil || Self.activeOwner === self else {
                stop(reason: "Another radio test already owns discovery")
                return false
            }
            Self.activeOwner = self
            isRequested = true
            isRestorationPending = false
            restorationCallbacks += 1
            log("iOS delivered " + description + " restoration state.")
            onRestored?()
            startHeartbeat()
            return true
        }

        private func finishRestorationWithoutState() {
            guard isRestorationPending, centralStateReported, advertiserStateReported,
                central?.state != .unknown, central?.state != .resetting,
                advertiser?.state != .unknown, advertiser?.state != .resetting
            else { return }
            stop(reason: "iOS did not restore the saved test. Tap Start for a new test")
        }

        func rotateToken(to token: DiscoveryToken) {
            guard isRequested, var current = session else { return }
            current.rotate(to: token)
            session = current
            log("Rotated the anonymous discovery token.")
        }

        func stop(reason: String = "Stopped") {
            guard isRequested || central != nil || advertiser != nil else { return }
            isRequested = false
            heartbeat?.cancel()
            heartbeat = nil
            pocketExpiry?.cancel()
            pocketExpiry = nil
            isRestorationPending = false
            pocketWindow = nil
            restoredConnections.removeAll()
            resetRestoredPeripheral = false
            if Self.activeOwner === self { Self.activeOwner = nil }
            if let central, central.state == .poweredOn {
                central.stopScan()
                if let outbound { central.cancelPeripheralConnection(outbound.peripheral) }
            }
            if let advertiser, advertiser.state == .poweredOn {
                advertiser.stopAdvertising()
                advertiser.removeAllServices()
            }
            for candidate in candidates.values { candidate.peripheral.delegate = nil }
            // Old callbacks cannot affect the next session, even if Start follows Stop immediately.
            central?.delegate = nil
            advertiser?.delegate = nil
            central = nil
            advertiser = nil
            publishedService = nil
            serviceReady = false
            advertisingPending = false
            candidates.removeAll()
            inboundReads.removeAll()
            outbound = nil
            isScanning = false
            isAdvertising = false
            exchangeStatus = "Idle"
            bluetoothStatus = "Not in use"
            status = reason
            log(reason + ". Radios stopped; results retained until the next Start.")
            onStopped?()
        }

        private func log(_ message: String) {
            events.insert(DiscoveryLogEntry(message: message), at: 0)
            if events.count > 60 { events.removeLast(events.count - 60) }
        }

        private func updateAvailability() {
            guard allowRadioOperations() else { return }
            let states = [central?.state ?? .unknown, advertiser?.state ?? .unknown]
            if states.allSatisfy({ $0 == .poweredOn }) {
                bluetoothStatus = "Ready"
                startRadiosIfReady()
                return
            }

            if states.contains(.unauthorized) {
                bluetoothStatus = "Permission denied"
                status = "Allow Face2Face Bluetooth access in Settings, then return here."
            } else if states.contains(.unsupported) {
                bluetoothStatus = "Unsupported"
                status = "This device does not support the Bluetooth test."
            } else if states.contains(.poweredOff) {
                bluetoothStatus = "Bluetooth is off"
                status = "Turn Bluetooth on to continue this session."
            } else {
                bluetoothStatus = "Starting or resetting"
                status = "Waiting for Bluetooth"
            }
            if let central, central.state == .poweredOn {
                central.stopScan()
                if let outbound { central.cancelPeripheralConnection(outbound.peripheral) }
            }
            if let advertiser, advertiser.state == .poweredOn {
                advertiser.stopAdvertising()
                advertiser.removeAllServices()
            }
            outbound?.peripheral.delegate = nil
            outbound = nil
            candidates.removeAll()
            inboundReads.removeAll()
            publishedService = nil
            serviceReady = false
            advertisingPending = false
            isScanning = false
            isAdvertising = false
            exchangeStatus = "Idle"
        }

        private func startRadiosIfReady() {
            guard allowRadioOperations(), central?.state == .poweredOn, advertiser?.state == .poweredOn else {
                return
            }
            guard let advertiser, let central else { return }
            if !restoredConnections.isEmpty {
                central.stopScan()
                isScanning = false
                for peer in restoredConnections {
                    peer.delegate = nil
                    central.cancelPeripheralConnection(peer)
                }
                restoredConnections.removeAll()
            }
            if resetRestoredPeripheral {
                advertiser.stopAdvertising()
                advertiser.removeAllServices()
                publishedService = nil
                serviceReady = false
                advertisingPending = false
                isAdvertising = false
                resetRestoredPeripheral = false
            }
            if publishedService == nil {
                advertiser.removeAllServices()
                let characteristic = CBMutableCharacteristic(
                    type: Self.tokenID, properties: [.read, .write], value: nil,
                    permissions: [.readable, .writeable])
                let service = CBMutableService(type: Self.serviceID, primary: true)
                service.characteristics = [characteristic]
                publishedService = service
                advertiser.add(service)
                status = "Publishing the test service"
            }
            guard serviceReady else { return }
            if !isAdvertising && !advertisingPending {
                advertisingPending = true
                advertiser.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID]])
            }
            if !isScanning {
                central.scanForPeripherals(
                    withServices: [Self.serviceID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: isApplicationActive])
                isScanning = central.isScanning
                log("Scanning for the Face2Face test service.")
            }
            status = isAdvertising && isScanning ? "Discovering nearby test devices" : "Starting the radios"
        }

        private func pruneInboundReads() {
            let now = Date()
            inboundReads = inboundReads.filter {
                let age = now.timeIntervalSince($0.value)
                return age >= 0 && age < Self.exchangeTimeout
            }
        }

        private func tick() {
            guard allowRadioOperations() else { return }
            let now = Date()
            pruneInboundReads()
            candidates = candidates.filter {
                now.timeIntervalSince($0.value.lastSeen) < 20 || $0.key == outbound?.peripheral.identifier
            }
            if let outbound, now >= outbound.deadline {
                if outbound.phase == .disconnecting {
                    outbound.peripheral.delegate = nil
                    self.outbound = nil
                    exchangeStatus = "Idle"
                } else {
                    failExchange("The peer timed out.")
                }
            }
            connectNextPeer()
        }

        private func connectNextPeer() {
            guard allowRadioOperations(), serviceReady, isScanning, outbound == nil,
                let token = session?.token,
                let central, central.state == .poweredOn
            else { return }
            let now = Date()
            let candidate = candidates.values
                .filter {
                    $0.attempts < Self.retryLimit && $0.nextAttempt <= now
                        && ($0.peripheral.state == .disconnected || $0.peripheral.state == .connected)
                }
                .min { $0.nextAttempt < $1.nextAttempt }
            guard let candidate else { return }
            candidate.attempts += 1
            let peer = candidate.peripheral
            outbound = Exchange(peripheral: peer, localToken: token, generation: generation)
            peer.delegate = self
            exchangeStatus = "Connecting (attempt \(candidate.attempts) of \(Self.retryLimit))"
            log(exchangeStatus)
            if peer.state == .connected {
                discoverService(on: peer)
            } else {
                central.connect(peer, options: nil)
            }
        }

        private func currentExchange(_ peer: CBPeripheral) -> Exchange? {
            guard allowRadioOperations(), let outbound, outbound.peripheral === peer,
                outbound.generation == generation
            else { return nil }
            if outbound.phase != .disconnecting, Date() >= outbound.deadline {
                failExchange("The peer's exchange deadline passed.")
                return nil
            }
            return outbound
        }

        private func discoverService(on peer: CBPeripheral) {
            guard let exchange = currentExchange(peer) else { return }
            exchange.phase = .services
            exchangeStatus = "Discovering the token service"
            peer.discoverServices([Self.serviceID])
        }

        private func failExchange(_ message: String) {
            guard let outbound, outbound.phase != .disconnecting else { return }
            let candidate = candidates[outbound.peripheral.identifier]
            let exhausted = (candidate?.attempts ?? Self.retryLimit) >= Self.retryLimit
            candidate?.nextAttempt = Date().addingTimeInterval(
                pow(2, Double(candidate?.attempts ?? 1)) + Double.random(in: 0.1...0.8))
            lastIssue =
                message
                + (exhausted ? " Tap Stop, then Start to retry this peer." : " Retrying automatically.")
            log(lastIssue ?? message)
            disconnect(outbound)
        }

        private func disconnect(_ exchange: Exchange) {
            exchange.phase = .disconnecting
            exchange.deadline = Date().addingTimeInterval(2)
            exchangeStatus = "Disconnecting"
            central?.cancelPeripheralConnection(exchange.peripheral)
        }

        private func record(_ token: DiscoveryToken, direction: String) {
            guard allowRadioOperations(), var session else { return }
            if let encounter = session.record(token) {
                self.session = session
                onEncounter?(encounter)
                log(
                    "\(direction) exchange: \(token.shortCode), \(String(format: "%.1f", encounter.elapsed)) seconds since Start."
                )
                if session.encounters.count == DiscoverySession.encounterLimit {
                    log("Session storage limit reached. Start a fresh session to record more tokens.")
                }
            }
            lastIssue = nil
        }

        var report: String {
            let encounters = session?.encounters ?? []
            let rows = encounters.map {
                "\($0.id.shortCode): \(String(format: "%.1f", $0.elapsed))s since Start"
            }
            let logs = events.reversed().map {
                "\($0.timestamp.formatted(date: .omitted, time: .standard)) \($0.message)"
            }
            return
                ([
                    isPocketMode
                        ? "Face2Face Stage 3 — anonymous Pocket experiment"
                        : "Face2Face Stage 1 — foreground Bluetooth experiment",
                    "Application active: \(isApplicationActive)",
                    "Actual iOS restoration callbacks: \(restorationCallbacks)",
                    "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                    "Simulator: \(Self.isSimulator)",
                    "Status: \(status)",
                    "Bluetooth: \(bluetoothStatus)",
                    "Scanning: \(isScanning); advertising: \(isAdvertising)",
                    "Session code (truncated): \(session?.token.shortCode ?? "none")",
                    "Unique peer tokens: \(encounters.count)",
                    "Anonymous, unverified observations. No account or proximity proof.",
                    "",
                ] + rows + ["", "Events (up to 60):"] + logs).joined(separator: "\n")
        }
    }

    extension BluetoothDiscoveryService: @preconcurrency CBCentralManagerDelegate {

        func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
            guard central === self.central, acceptRestoration("central manager") else { return }
            restoredConnections = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
            // Pending old-token handshakes are canceled after the manager becomes powered on.
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            guard central === self.central else { return }
            centralStateReported = true
            if isRestorationPending {
                finishRestorationWithoutState()
                return
            }
            updateAvailability()
            log("Bluetooth: \(bluetoothStatus).")
        }

        func centralManager(
            _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any], rssi: NSNumber
        ) {
            guard central === self.central, allowRadioOperations(), serviceReady else { return }
            tick()
            guard isRequested else { return }
            // Device names, RSSI, addresses and account data are deliberately not recorded.
            if let candidate = candidates[peripheral.identifier] {
                candidate.lastSeen = Date()
            } else if candidates.count < Self.candidateLimit {
                candidates[peripheral.identifier] = Candidate(peripheral)
            }
            connectNextPeer()
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            guard central === self.central, currentExchange(peripheral)?.phase == .connecting else { return }
            discoverService(on: peripheral)
        }

        func centralManager(
            _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
        ) {
            guard central === self.central, currentExchange(peripheral)?.phase == .connecting else { return }
            failExchange("Could not connect to a test peer.")
        }

        func centralManager(
            _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
        ) {
            guard central === self.central, let exchange = currentExchange(peripheral) else { return }
            if exchange.phase != .disconnecting { failExchange("The peer disconnected during the exchange.") }
            peripheral.delegate = nil
            outbound = nil
            exchangeStatus = "Idle"
            connectNextPeer()
        }
    }

    extension BluetoothDiscoveryService: @preconcurrency CBPeripheralDelegate {
        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard let exchange = currentExchange(peripheral), exchange.phase == .services else { return }
            guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID })
            else {
                failExchange("The peer's token service was unavailable.")
                return
            }
            exchange.phase = .characteristic
            exchangeStatus = "Discovering the token characteristic"
            peripheral.discoverCharacteristics([Self.tokenID], for: service)
        }

        func peripheral(
            _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
        ) {
            guard let exchange = currentExchange(peripheral), exchange.phase == .characteristic,
                service.uuid == Self.serviceID
            else { return }
            guard error == nil,
                let characteristic = service.characteristics?.first(where: { $0.uuid == Self.tokenID }),
                characteristic.properties.contains(.read), characteristic.properties.contains(.write)
            else {
                failExchange("The peer does not support the token exchange.")
                return
            }
            exchange.phase = .reading
            exchangeStatus = "Reading an anonymous token"
            peripheral.readValue(for: characteristic)
        }

        func peripheral(
            _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
        ) {
            guard let exchange = currentExchange(peripheral), exchange.phase == .reading,
                characteristic.uuid == Self.tokenID
            else { return }
            guard error == nil, let data = characteristic.value, let peer = try? DiscoveryToken(packet: data),
                peer != exchange.localToken
            else {
                failExchange("The peer sent an invalid or reflected test token.")
                return
            }
            let packet = exchange.localToken.packet
            guard peripheral.maximumWriteValueLength(for: .withResponse) >= packet.count else {
                failExchange("The peer cannot accept the token packet.")
                return
            }
            exchange.peerToken = peer
            exchange.phase = .writing
            exchangeStatus = "Sending our anonymous token"
            peripheral.writeValue(packet, for: characteristic, type: .withResponse)
        }

        func peripheral(
            _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
        ) {
            guard let exchange = currentExchange(peripheral), exchange.phase == .writing,
                characteristic.uuid == Self.tokenID
            else { return }
            guard error == nil, let peer = exchange.peerToken else {
                failExchange("The peer did not acknowledge our token.")
                return
            }
            record(peer, direction: "Outgoing")
            // Recheck later so a peer can start a new session without restarting this phone.
            let candidate = candidates[peripheral.identifier]
            candidate?.attempts = 0
            candidate?.nextAttempt = Date().addingTimeInterval(15)
            disconnect(exchange)
        }

        func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
            guard currentExchange(peripheral) != nil,
                invalidatedServices.contains(where: { $0.uuid == Self.serviceID })
            else { return }
            failExchange("The peer restarted its test service.")
        }
    }

    extension BluetoothDiscoveryService: @preconcurrency CBPeripheralManagerDelegate {

        func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
            guard peripheral === advertiser, acceptRestoration("peripheral manager") else { return }
            resetRestoredPeripheral = true
            // Rebuild the service with a new in-memory token; do not reuse restored token state.
        }

        func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            guard peripheral === advertiser else { return }
            advertiserStateReported = true
            if isRestorationPending {
                finishRestorationWithoutState()
                return
            }
            updateAvailability()
            log("Bluetooth: \(bluetoothStatus).")
        }

        func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            guard peripheral === advertiser, allowRadioOperations(), service === publishedService else {
                return
            }
            guard error == nil else {
                stop(reason: "Could not publish the Bluetooth service")
                lastIssue = "Tap Start discovery to try publishing the service again."
                return
            }
            serviceReady = true
            log("Published the anonymous token service.")
            startRadiosIfReady()
        }

        func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
            guard peripheral === advertiser, allowRadioOperations(), serviceReady else { return }
            advertisingPending = false
            guard error == nil else {
                stop(reason: "Could not advertise the Bluetooth service")
                lastIssue = "Tap Start discovery to try advertising again."
                return
            }
            isAdvertising = peripheral.isAdvertising
            log("Advertising the Face2Face test service.")
            startRadiosIfReady()
        }

        func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            guard peripheral === advertiser else { return }
            pruneInboundReads()
            guard isRequested, consentIsCurrent, serviceReady, let token = session?.token else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization)
                if !consentIsCurrent { stop(reason: "Five-minute Pocket test expired") }
                return
            }
            guard request.characteristic.uuid == Self.tokenID else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                return
            }
            let packet = token.packet
            guard request.offset >= 0, request.offset <= packet.count else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            // Bound read-before-write tracking even when untrusted centrals connect.
            if request.offset == 0 {
                guard
                    inboundReads[request.central.identifier] != nil
                        || inboundReads.count < Self.candidateLimit
                else {
                    peripheral.respond(to: request, withResult: .insufficientResources)
                    return
                }
                inboundReads[request.central.identifier] = Date()
            }
            request.value = packet.subdata(in: request.offset..<packet.count)
            peripheral.respond(to: request, withResult: .success)
        }

        func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            guard peripheral === advertiser, let request = requests.first else { return }
            pruneInboundReads()
            // One response for the whole batch, and no partial application of malformed writes.
            guard isRequested, consentIsCurrent, serviceReady, let token = session?.token else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization)
                if !consentIsCurrent { stop(reason: "Five-minute Pocket test expired") }
                return
            }
            guard requests.count == 1, request.characteristic.uuid == Self.tokenID else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                return
            }
            guard request.offset == 0 else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            guard let readAt = inboundReads[request.central.identifier],
                Date().timeIntervalSince(readAt) < Self.exchangeTimeout
            else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization)
                return
            }
            guard let data = request.value, let peer = try? DiscoveryToken(packet: data), peer != token else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                return
            }
            inboundReads.removeValue(forKey: request.central.identifier)
            peripheral.respond(to: request, withResult: .success)
            record(peer, direction: "Incoming")
        }
    }
#endif
