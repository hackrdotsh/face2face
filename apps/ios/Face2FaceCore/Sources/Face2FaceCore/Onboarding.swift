import Foundation

public struct OnboardingState: Decodable, Sendable, Equatable {
    public let complete: Bool
    public let fields: [OnboardingField]
}

public enum FieldType: Equatable, Sendable {
    case text
    case date
    case singleChoice
    /// A field type this build of the app does not know how to render.
    case unsupported(String)

    init(rawValue: String) {
        switch rawValue {
        case "text": self = .text
        case "date": self = .date
        case "singleChoice": self = .singleChoice
        default: self = .unsupported(rawValue)
        }
    }
}

public struct ChoiceOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let allowsDescription: Bool
}

public struct ChoiceValue: Codable, Sendable, Equatable {
    public var optionId: String
    public var description: String?

    public init(optionId: String, description: String? = nil) {
        self.optionId = optionId
        self.description = description
    }
}

public enum FieldValue: Encodable, Sendable, Equatable {
    case text(String)
    /// A calendar date as `YYYY-MM-DD`.
    case date(String)
    case choice(ChoiceValue)

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .date(let date): try container.encode(date)
        case .choice(let choice): try container.encode(choice)
        }
    }
}

public struct FieldConstraints: Decodable, Sendable, Equatable {
    public let maxLength: Int?
    public let earliestDate: String?
    public let latestDate: String?
}

public struct OnboardingField: Decodable, Sendable, Equatable, Identifiable {
    public let key: String
    public let type: FieldType
    public let label: String
    public let required: Bool
    public let value: FieldValue?
    public let constraints: FieldConstraints?
    public let options: [ChoiceOption]

    public var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, type, label, required, value, constraints, options
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        type = FieldType(rawValue: try container.decode(String.self, forKey: .type))
        label = try container.decode(String.self, forKey: .label)
        required = try container.decode(Bool.self, forKey: .required)
        constraints = try container.decodeIfPresent(FieldConstraints.self, forKey: .constraints)
        options = try container.decodeIfPresent([ChoiceOption].self, forKey: .options) ?? []
        value = try Self.decodeValue(of: type, from: container)
    }

    private static func decodeValue(of type: FieldType, from container: KeyedDecodingContainer<CodingKeys>)
        throws -> FieldValue?
    {
        switch type {
        case .text: try container.decodeIfPresent(String.self, forKey: .value).map(FieldValue.text)
        case .date: try container.decodeIfPresent(String.self, forKey: .value).map(FieldValue.date)
        case .singleChoice:
            try container.decodeIfPresent(ChoiceValue.self, forKey: .value).map(FieldValue.choice)
        case .unsupported: nil
        }
    }
}
