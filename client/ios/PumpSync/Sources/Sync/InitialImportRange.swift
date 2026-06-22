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

  func minimumDate(relativeTo now: Date, calendar: Calendar = .current) -> Date {
    switch self {
    case .startFromNow:
      return now
    case .pastTwoDays:
      return startOfDay(daysBeforeNow: 2, relativeTo: now, calendar: calendar)
    case .pastWeek:
      return startOfDay(daysBeforeNow: 7, relativeTo: now, calendar: calendar)
    case .pastTwoWeeks:
      return startOfDay(daysBeforeNow: 14, relativeTo: now, calendar: calendar)
    }
  }

  private func startOfDay(daysBeforeNow days: Int, relativeTo now: Date, calendar: Calendar) -> Date {
    let startOfToday = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? startOfToday
  }
}
