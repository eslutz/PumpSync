import Foundation

/// Fresh codecs keep configuration local to one operation. Native value-format
/// styles can be shared safely; no mutable date formatter crosses an executor.
enum JSONCodec {
  static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      guard let date = parseDate(value) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
      }
      return date
    }
    return decoder
  }

  private static let fractionalDate = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let wholeDate = Date.ISO8601FormatStyle()

  static func parseDate(_ value: String) -> Date? {
    // The existing wire decoder truncates fractions beyond milliseconds.
    // Preserve sample boundaries while replacing its unsafe shared formatter.
    let milliseconds = value.replacingOccurrences(
      of: #"(\.[0-9]{3})[0-9]+"#, with: "$1", options: .regularExpression
    )
    guard let date = (try? fractionalDate.parse(milliseconds)) ?? (try? wholeDate.parse(milliseconds)) else { return nil }
    return Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
  }
}
