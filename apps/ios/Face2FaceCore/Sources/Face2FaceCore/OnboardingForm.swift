import Foundation

/// Editable input for one onboarding field. Only the slot matching the field's type is used.
public struct FieldDraft: Equatable, Sendable {
    public var text = ""
    public var date: Date?
    public var optionId: String?
    public var description = ""

    public init() {}
}

/// The fields a person still has to answer, their drafts, and the values to send to the server.
public struct OnboardingForm: Equatable, Sendable {
    public let fields: [OnboardingField]
    public var drafts: [String: FieldDraft]
    /// True when the server requires a field this app version cannot render.
    public let needsAppUpdate: Bool
    private let calendar: Calendar

    public init(state: OnboardingState, calendar: Calendar = .current) {
        let unanswered = state.fields.filter { $0.value == nil }
        fields = unanswered.filter { !Self.isUnsupported($0) }
        needsAppUpdate = unanswered.contains { Self.isUnsupported($0) && $0.required }
        drafts = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, FieldDraft()) })
        self.calendar = calendar
    }

    public func selectedOption(for field: OnboardingField) -> ChoiceOption? {
        guard let optionId = drafts[field.key]?.optionId else { return nil }
        return field.options.first { $0.id == optionId }
    }

    public func dateRange(for field: OnboardingField) -> ClosedRange<Date>? {
        guard let earliest = field.constraints?.earliestDate.flatMap(date(from:)),
            let latest = field.constraints?.latestDate.flatMap(date(from:)),
            earliest <= latest
        else { return nil }
        return earliest...latest
    }

    /// Values for every field with input. Empty fields are left out so the server reports them as missing.
    public func values() -> [String: FieldValue] {
        var values: [String: FieldValue] = [:]
        for field in fields {
            guard let draft = drafts[field.key], let value = value(of: draft, for: field) else { continue }
            values[field.key] = value
        }
        return values
    }

    private func value(of draft: FieldDraft, for field: OnboardingField) -> FieldValue? {
        switch field.type {
        case .text:
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .text(text)
        case .date:
            return draft.date.map { .date(isoDate(from: $0)) }
        case .singleChoice:
            guard let option = selectedOption(for: field) else { return nil }
            let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let keepsDescription = option.allowsDescription && !description.isEmpty
            return .choice(
                ChoiceValue(optionId: option.id, description: keepsDescription ? description : nil))
        case .image, .unsupported:
            return nil
        }
    }

    private func isoDate(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func date(from isoDate: String) -> Date? {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func isUnsupported(_ field: OnboardingField) -> Bool {
        if case .unsupported = field.type { return true }
        return false
    }
}
