import Foundation

enum InitialImportRange: String, CaseIterable, Codable, Identifiable {
  case startFromNow
  case pastTwoDays
  case pastWeek
  case pastTwoWeeks

  static let `default`: InitialImportRange = .pastWeek

  var id: String { rawValue }

  var title: String {
    switch self {
    case .startFromNow:
      return "Start from now"
    case .pastTwoDays:
      return "Past 2 days"
    case .pastWeek:
      return "Past 7 days"
    case .pastTwoWeeks:
      return "Past 14 days"
    }
  }

  func minimumDate(relativeTo now: Date) -> Date {
    switch self {
    case .startFromNow:
      return now
    case .pastTwoDays:
      return now.addingTimeInterval(-2 * 24 * 60 * 60)
    case .pastWeek:
      return now.addingTimeInterval(-7 * 24 * 60 * 60)
    case .pastTwoWeeks:
      return now.addingTimeInterval(-(14 * 24 * 60 * 60 - 10 * 60))
    }
  }
}
