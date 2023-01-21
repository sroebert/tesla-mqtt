import Vapor

enum JSON: Content, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Decimal)
    case string(String)
    case array([JSON])
    case dictionary([String: JSON])
    
    // MARK: - Public
    
    static func integer(_ value: Int) -> Self {
        return .integer(Int64(value))
    }
    
    static func integer(_ value: Int32) -> Self {
        return .integer(Int64(value))
    }
    
    static func unsignedInteger(_ value: UInt) -> Self {
        return .unsignedInteger(UInt64(value))
    }
    
    static func unsignedInteger(_ value: UInt32) -> Self {
        return .unsignedInteger(UInt64(value))
    }
    
    static func double(_ value: Double) -> Self {
        return .double(Decimal(value))
    }
    
    // MARK: - Lifecycle
    
    init<T: Encodable>(encodable: T) throws {
        let data = try JSONEncoder().encode(encodable)
        self = try JSONDecoder().decode(JSON.self, from: data)
    }
    
    // MARK: - Codable
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard !container.decodeNil() else {
            self = .null
            return
        }
        
        if let bool = container.decodeIfMatched(Bool.self) {
            self = .bool(bool)
        } else if let integer = container.decodeIfMatched(Int32.self) {
            self = .integer(Int64(integer))
        } else if let integer = container.decodeIfMatched(Int64.self) {
            self = .integer(integer)
        } else if let integer = container.decodeIfMatched(UInt32.self) {
            self = .unsignedInteger(UInt64(integer))
        } else if let integer = container.decodeIfMatched(UInt64.self) {
            self = .unsignedInteger(integer)
        } else if let double = container.decodeIfMatched(Decimal.self) {
            self = .double(double)
        } else if let double = container.decodeIfMatched(Double.self) {
            self = .double(double)
        } else if let string = container.decodeIfMatched(String.self) {
            self = .string(string)
        } else if let array = container.decodeIfMatched([JSON].self) {
            self = .array(array)
        } else if let dictionary = container.decodeIfMatched([String : JSON].self) {
            self = .dictionary(dictionary)
        } else {
            throw DecodingError.typeMismatch(JSON.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode JSON as any of the possible types."))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
            case .null: try container.encodeNil()
            case .bool(let bool): try container.encode(bool)
            case .integer(let integer): try container.encode(integer)
            case .unsignedInteger(let integer): try container.encode(integer)
            case .double(let double): try container.encode(double)
            case .string(let string): try container.encode(string)
            case .array(let array): try container.encode(array)
            case .dictionary(let dictionary): try container.encode(dictionary)
        }
    }
}

extension JSON: ExpressibleByNilLiteral {
    init(nilLiteral: ()) {
        self = .null
    }
}

extension JSON: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .integer(Int64(value))
    }
}

extension JSON: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .double(Decimal(value))
    }
}

extension JSON: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSON...) {
        self = .array(elements)
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSON)...) {
        self = .dictionary(.init(uniqueKeysWithValues: elements))
    }
}

fileprivate extension SingleValueDecodingContainer {
    func decodeIfMatched<T : Decodable>(_ type: T.Type) -> T? {
        do {
            return try self.decode(T.self)
        } catch {
            return nil
        }
    }
}
