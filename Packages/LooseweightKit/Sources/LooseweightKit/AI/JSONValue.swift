import Foundation

/// JSON with ordered object keys and a `raw` case for splicing pre-serialised fragments byte-for-byte.
public indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([Field])
    case raw(Data)

    public struct Field: Hashable, Sendable {
        public var key: String
        public var value: JSONValue

        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    public static func obj(_ pairs: KeyValuePairs<String, JSONValue>) -> JSONValue {
        .object(pairs.map { Field($0.key, $0.value) })
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(fields) = self else { return nil }
        return fields.first { $0.key == key }?.value
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        doubleValue.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(values) = self { return values }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Serialising

    public func serialized() -> Data {
        var output = Data()
        write(into: &output)
        return output
    }

    public var jsonString: String { String(decoding: serialized(), as: UTF8.self) }

    private func write(into output: inout Data) {
        switch self {
        case .null:
            output.append(contentsOf: Array("null".utf8))
        case let .bool(value):
            output.append(contentsOf: Array((value ? "true" : "false").utf8))
        case let .number(value):
            output.append(contentsOf: Array(Self.format(value).utf8))
        case let .string(value):
            Self.writeString(value, into: &output)
        case let .array(values):
            output.append(UInt8(ascii: "["))
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                value.write(into: &output)
            }
            output.append(UInt8(ascii: "]"))
        case let .object(fields):
            output.append(UInt8(ascii: "{"))
            for (index, field) in fields.enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                Self.writeString(field.key, into: &output)
                output.append(UInt8(ascii: ":"))
                field.value.write(into: &output)
            }
            output.append(UInt8(ascii: "}"))
        case let .raw(data):
            output.append(data)
        }
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    private static func writeString(_ string: String, into output: inout Data) {
        output.append(UInt8(ascii: "\""))
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output.append(contentsOf: [0x5C, 0x22])
            case "\\": output.append(contentsOf: [0x5C, 0x5C])
            case "\n": output.append(contentsOf: [0x5C, UInt8(ascii: "n")])
            case "\r": output.append(contentsOf: [0x5C, UInt8(ascii: "r")])
            case "\t": output.append(contentsOf: [0x5C, UInt8(ascii: "t")])
            default:
                if scalar.value < 0x20 {
                    output.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
                } else {
                    output.append(contentsOf: Array(String(scalar).utf8))
                }
            }
        }
        output.append(UInt8(ascii: "\""))
    }

    // MARK: Parsing

    public enum ParseError: Error, Equatable {
        case unexpectedEnd
        case unexpectedByte(Int)
        case invalidNumber(Int)
        case invalidEscape(Int)
        case trailingData(Int)
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: [UInt8](data))
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.position == parser.bytes.count else { throw ParseError.trailingData(parser.position) }
        return value
    }

    /// Exact bytes of each value in a top-level JSON object, keyed by field name.
    public static func topLevelRawFields(_ data: Data) throws -> [String: Data] {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        guard parser.peek() == UInt8(ascii: "{") else { throw ParseError.unexpectedByte(parser.position) }
        parser.position += 1
        var result: [String: Data] = [:]
        parser.skipWhitespace()
        if parser.peek() == UInt8(ascii: "}") { return result }
        while true {
            parser.skipWhitespace()
            let key = try parser.parseString()
            parser.skipWhitespace()
            try parser.expect(UInt8(ascii: ":"))
            parser.skipWhitespace()
            let start = parser.position
            _ = try parser.parseValue()
            result[key] = Data(parser.bytes[start..<parser.position])
            parser.skipWhitespace()
            if parser.peek() == UInt8(ascii: ",") { parser.position += 1; continue }
            try parser.expect(UInt8(ascii: "}"))
            return result
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var position = 0

        func peek() -> UInt8? { position < bytes.count ? bytes[position] : nil }

        mutating func skipWhitespace() {
            while let byte = peek(), byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { position += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            guard let current = peek() else { throw ParseError.unexpectedEnd }
            guard current == byte else { throw ParseError.unexpectedByte(position) }
            position += 1
        }

        mutating func parseValue() throws -> JSONValue {
            skipWhitespace()
            guard let byte = peek() else { throw ParseError.unexpectedEnd }
            switch byte {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try parseNumber())
            }
        }

        mutating func literal(_ word: String) throws {
            for expected in word.utf8 { try expect(expected) }
        }

        mutating func parseObject() throws -> JSONValue {
            try expect(UInt8(ascii: "{"))
            var fields: [Field] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { position += 1; return .object(fields) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                try expect(UInt8(ascii: ":"))
                fields.append(Field(key, try parseValue()))
                skipWhitespace()
                if peek() == UInt8(ascii: ",") { position += 1; continue }
                try expect(UInt8(ascii: "}"))
                return .object(fields)
            }
        }

        mutating func parseArray() throws -> JSONValue {
            try expect(UInt8(ascii: "["))
            var values: [JSONValue] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "]") { position += 1; return .array(values) }
            while true {
                values.append(try parseValue())
                skipWhitespace()
                if peek() == UInt8(ascii: ",") { position += 1; continue }
                try expect(UInt8(ascii: "]"))
                return .array(values)
            }
        }

        mutating func parseString() throws -> String {
            try expect(UInt8(ascii: "\""))
            var scalars = String.UnicodeScalarView()
            var buffer: [UInt8] = []
            func flush() {
                if !buffer.isEmpty {
                    scalars.append(contentsOf: String(decoding: buffer, as: UTF8.self).unicodeScalars)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            while true {
                guard let byte = peek() else { throw ParseError.unexpectedEnd }
                position += 1
                switch byte {
                case UInt8(ascii: "\""):
                    flush()
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    flush()
                    guard let escape = peek() else { throw ParseError.unexpectedEnd }
                    position += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code), peek() == UInt8(ascii: "\\") {
                            let saved = position
                            position += 1
                            if peek() == UInt8(ascii: "u") {
                                position += 1
                                let low = try hex4()
                                if (0xDC00...0xDFFF).contains(low) {
                                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                } else {
                                    position = saved
                                }
                            } else {
                                position = saved
                            }
                        }
                        scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                    default:
                        throw ParseError.invalidEscape(position - 1)
                    }
                default:
                    buffer.append(byte)
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard position + 4 <= bytes.count else { throw ParseError.unexpectedEnd }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[position]
                position += 1
                value <<= 4
                switch byte {
                case 0x30...0x39: value |= UInt32(byte - 0x30)
                case 0x41...0x46: value |= UInt32(byte - 0x41 + 10)
                case 0x61...0x66: value |= UInt32(byte - 0x61 + 10)
                default: throw ParseError.invalidEscape(position - 1)
                }
            }
            return value
        }

        mutating func parseNumber() throws -> Double {
            let start = position
            while let byte = peek(), byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
                || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") || (0x30...0x39).contains(byte) {
                position += 1
            }
            guard position > start, let value = Double(String(decoding: bytes[start..<position], as: UTF8.self)) else {
                throw ParseError.invalidNumber(start)
            }
            return value
        }
    }
}
