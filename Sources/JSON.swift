import Foundation

/// JS-like JSON object.
public struct JSON {}

// MARK: - JSON.parse<T>()

extension JSON {
  private static func createDecoder () -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    return decoder
  }

  private static let defaultDecoder = createDecoder()

  public static func parse<T: Decodable>(_ data: Data) throws -> T {
    return try defaultDecoder.decode(T.self, from: data)
  }

  public static func parse<T: Decodable>(_ string: String) throws -> T {
    return try parse(Data(string.utf8))
  }
}

extension JSONDecoder.DateDecodingStrategy {
  fileprivate static let iso8601WithFractionalSeconds = custom { decoder in
    let dateString = try decoder.singleValueContainer().decode(String.self)
    if let date = JSON.DateFormatter.parse(dateString) {
      return date
    }

    throw DecodingError.dataCorrupted(DecodingError.Context(
      codingPath: decoder.codingPath,
      debugDescription: "Invalid date: \(dateString.debugDescription)"
    ))
  }
}

// MARK: - JSON.stringify()

extension JSON {
  static private func createEncoder (pretty: Bool) -> JSONEncoder {
    let encoder = JSONEncoder()

    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if (pretty) { encoder.outputFormatting.insert(.prettyPrinted) }

    encoder.dataEncodingStrategy = .base64
    encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
    encoder.keyEncodingStrategy = .useDefaultKeys
    encoder.nonConformingFloatEncodingStrategy = .throw

    return encoder
  }

  static private let defaultEncoder = createEncoder(pretty: false)
  static private let defaultPrettyEncoder = createEncoder(pretty: true)

  public static func stringify (_ value: any Encodable, pretty: Bool = false) -> Data {
    let encoder = pretty ? defaultPrettyEncoder : defaultEncoder
    return try! encoder.encode(value)
  }

  public static func stringify (_ value: any Encodable, pretty: Bool = false) -> String {
    return String(
      data: stringify(value, pretty: pretty),
      encoding: .utf8
    )!
  }
}


extension JSONEncoder.DateEncodingStrategy {
  fileprivate static let iso8601WithFractionalSeconds = custom { value, encoder  in
    var container = encoder.singleValueContainer()
    try container.encode(JSON.DateFormatter.stringify(value))
  }
}

// MARK: - Formatting dates
// TODO: https://stackoverflow.com/a/28016692

extension JSON {
  public struct DateFormatter {
    private static func createFormatter (fractionalSeconds fractionalSecondsEnabled: Bool) -> ISO8601DateFormatter {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = fractionalSecondsEnabled
      ? [.withInternetDateTime, .withFractionalSeconds]
      : [.withInternetDateTime]

      return formatter
    }

    private static let Default = createFormatter(fractionalSeconds: true)
    private static let Fractionless = createFormatter(fractionalSeconds: false)

    public static func parse (_ string: String) -> Date? {
      return DateFormatter.Default.date(from: string)
      ?? DateFormatter.Fractionless.date(from: string)
    }

    public static func stringify (_ date: Date) -> String {
      return Default.string(from: date)
    }
  }
}
