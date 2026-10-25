import Face2FaceCore
import Foundation

#if DEBUG
    actor PreviewForumRepository: ForumRepository {
        private var names = [
            "coffee", "music", "art", "books", "hiking", "film", "running", "cooking", "gaming", "gardening",
            "photography",
        ]
        private var selected: Set<String> = ["coffee", "music"]
        private var opened: Set<String> = []
        private var created = 0
        private var rows: [[String: Any]] = []
        private var attending: [String: Set<String>] = [:]
        private let state: String?
        init(state: String? = nil) {
            let arguments = ProcessInfo.processInfo.arguments
            let index = arguments.firstIndex(of: "-forums-preview-state")
            self.state =
                state ?? index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            opened = Set(names)
            if self.state == "empty" { selected = [] }
            if self.state == "waiting" {
                names.append("kite flying")
                selected = ["kite flying"]
            }
        }
        private func check() throws { if state == "error" { throw APIError.server(503) } }
        private func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
            try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
        }
        private func person(_ id: String) -> [String: Any] {
            [
                "userId": id, "name": id == "preview" ? "Preview Walker" : id.capitalized,
                "avatar": ["seed": id == "ava" ? "AAAAAAAAAAAAAAAAAAAAAA" : "AQIDBAUGBwgJCgsMDQ4PEA"],
            ]
        }
        private func seed() {
            guard rows.isEmpty else { return }
            let now = Date()
            let formatter = ISO8601DateFormatter()
            for (id, forum, title, author, hours) in [
                ("preview-coffee", "coffee", "Coffee & a little conversation", "ava", 2.0),
                ("preview-event", "music", "Bring a song to the square", "preview", 25.0),
                ("preview-art", "art", "Sketching by the water", "cleo", 48.0),
                ("preview-past", "coffee", "Last weekend's coffee stroll", "noor", -48.0),
                ("preview-cancelled", "coffee", "A rainy-day picnic", "ava", 48.0),
            ] {
                rows.append([
                    "id": id, "forumId": forum, "title": title,
                    "description":
                        "A relaxed get-together with people who love the same little things. Come as you are.",
                    "location": "The café by the town square",
                    "startsAt": formatter.string(from: now.addingTimeInterval(hours * 3600)),
                    "endsAt": formatter.string(from: now.addingTimeInterval((hours + 2) * 3600)),
                    "createdAt": formatter.string(from: now.addingTimeInterval(-3600 * hours.magnitude)),
                    "updatedAt": formatter.string(from: now.addingTimeInterval(-3600 * hours.magnitude)),
                    "author": person(author), "edited": false, "cancelled": id == "preview-cancelled",
                ])
                attending[id] =
                    id == "preview-coffee"
                    ? ["cleo", "noor"]
                    : ["preview-past", "preview-cancelled"].contains(id) ? ["noor", "preview"] : ["noor"]
            }
        }
        private func view(_ row: [String: Any]) -> [String: Any] {
            var value = row
            let id = row["id"] as? String ?? ""
            let attendees = (attending[id] ?? []).sorted()
            value["attendeeCount"] = attendees.count
            value["attendeePreview"] = attendees.prefix(5).map(person)
            value["attending"] = attendees.contains("preview")
            value["isAuthor"] = (row["author"] as? [String: Any])?["userId"] as? String == "preview"
            let end = (row["endsAt"] as? String) ?? (row["startsAt"] as? String) ?? ""
            value["past"] = (ISO8601DateFormatter().date(from: end) ?? .distantPast) <= Date()
            return value
        }
        func townForums() throws -> [TownForum] {
            try check()
            seed()
            let forums = names.filter { selected.contains($0) && opened.contains($0) }.map { name in
                [
                    "id": name, "interestId": name, "interestName": name,
                    "upcomingPostCount": rows.filter {
                        ($0["forumId"] as? String) == name && (view($0)["past"] as? Bool) == false
                            && ($0["cancelled"] as? Bool) == false
                    }.count,
                ] as [String: Any]
            }
            return try decode(forums, as: [TownForum].self)
        }
        func interests() throws -> InterestCatalog {
            try check()
            return InterestCatalog(
                maxSelected: 10,
                interests: names.map {
                    InterestChoice(
                        id: $0, name: $0,
                        memberCount: opened.contains($0) ? 42 : selected.contains($0) ? 1 : 0,
                        selected: selected.contains($0))
                })
        }
        func replaceInterests(_ ids: [String]) throws -> InterestCatalog {
            try check()
            guard ids.count <= 10, Set(ids).count == ids.count, ids.allSatisfy(names.contains) else {
                throw APIError.server(400)
            }
            selected = Set(ids)
            return try interests()
        }
        func addInterest(named raw: String) throws -> InterestCatalog {
            try check()
            let name = InterestName.normalize(raw)
            guard InterestName.isValid(name) else {
                throw APIError.invalidFields(["name": "Use 2–32 letters, numbers, spaces, &, ', or -."])
            }
            guard selected.count < 10 || selected.contains(name) else { throw APIError.interestLimitReached }
            if !names.contains(name) {
                guard created < 5 else { throw APIError.rateLimited }
                created += 1
                names.append(name)
            }
            selected.insert(name)
            return try interests()
        }
        func forumPosts(forumID: String?, cursor: String?) throws -> ForumPostPage {
            try check()
            seed()
            if let forumID, !selected.contains(forumID) || !opened.contains(forumID) {
                throw APIError.server(404)
            }
            let posts = rows.filter { row in
                guard let id = row["forumId"] as? String, selected.contains(id),
                    row["cancelled"] as? Bool == false
                else { return false }
                return forumID.map { $0 == id } ?? (view(row)["past"] as? Bool == false)
            }.sorted {
                if forumID == nil {
                    return ($0["startsAt"] as? String ?? "") < ($1["startsAt"] as? String ?? "")
                }
                return ($0["createdAt"] as? String ?? "") > ($1["createdAt"] as? String ?? "")
            }
            let start =
                cursor.flatMap { id in posts.firstIndex { $0["id"] as? String == id }.map { $0 + 1 } } ?? 0
            let page = Array(posts.dropFirst(start).prefix(2)).map(view)
            return try decode(
                ["posts": page, "hasMore": posts.count > start + page.count], as: ForumPostPage.self)
        }
        func forumPost(_ id: String) throws -> ForumPost {
            try check()
            seed()
            guard let row = rows.first(where: { $0["id"] as? String == id }),
                let forum = row["forumId"] as? String, selected.contains(forum)
            else { throw APIError.server(404) }
            return try decode(view(row), as: ForumPost.self)
        }
        func createForumPost(forumID: String, input: ForumPostInput) throws -> ForumPost {
            try check()
            seed()
            guard selected.contains(forumID), opened.contains(forumID) else { throw APIError.server(404) }
            guard input.validationErrors.isEmpty else { throw APIError.invalidFields(input.validationErrors) }
            var row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
            let id = UUID().uuidString
            row.merge([
                "id": id, "forumId": forumID, "author": person("preview"), "cancelled": false,
                "edited": false,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "updatedAt": ISO8601DateFormatter().string(from: Date()),
            ]) { _, new in new }
            rows.insert(row, at: 0)
            attending[id] = []
            return try forumPost(id)
        }
        func updateForumPost(_ id: String, input: ForumPostInput) throws -> ForumPost {
            let old = try forumPost(id)
            guard old.isAuthor else { throw APIError.forumNotAuthor }
            guard !old.cancelled else { throw APIError.forumCancelled }
            guard input.validationErrors.isEmpty else { throw APIError.invalidFields(input.validationErrors) }
            let index = rows.firstIndex { $0["id"] as? String == id }!
            let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
            rows[index].merge(fields) { _, new in new }
            rows[index]["edited"] = true
            rows[index]["updatedAt"] = ISO8601DateFormatter().string(from: Date())
            return try forumPost(id)
        }
        func cancelForumPost(_ id: String) throws -> ForumPost {
            let old = try forumPost(id)
            guard old.isAuthor else { throw APIError.forumNotAuthor }
            guard !old.cancelled else { throw APIError.forumCancelled }
            let index = rows.firstIndex { $0["id"] as? String == id }!
            rows[index]["cancelled"] = true
            return try forumPost(id)
        }
        func attendForumPost(_ id: String, attending join: Bool) throws -> ForumPost {
            let old = try forumPost(id)
            if join && old.cancelled { throw APIError.forumCancelled }
            if join && old.past { throw APIError.forumEventOver }
            if join {
                attending[id, default: []].insert("preview")
            } else {
                attending[id, default: []].remove("preview")
            }
            return try forumPost(id)
        }
        func forumAttendees(_ id: String) throws -> [ForumPerson] {
            _ = try forumPost(id)
            return try decode((attending[id] ?? []).sorted().map(person), as: [ForumPerson].self)
        }
    }
#endif
