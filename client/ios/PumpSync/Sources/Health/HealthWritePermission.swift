import Foundation

enum HealthWriteSampleKind: String, CaseIterable, Identifiable {
  case insulinDelivery
  case dietaryCarbohydrates

  var id: String { rawValue }

  var title: String {
    switch self {
    case .insulinDelivery:
      return "Insulin delivery"
    case .dietaryCarbohydrates:
      return "Carbohydrates"
    }
  }
}

enum HealthWriteAccessStatus: Equatable {
  case notDetermined
  case sharingDenied
  case sharingAuthorized
  case unavailable

  var description: String {
    switch self {
    case .notDetermined:
      return "Not set"
    case .sharingDenied:
      return "Not allowed"
    case .sharingAuthorized:
      return "Allowed"
    case .unavailable:
      return "Unavailable"
    }
  }
}

struct HealthWritePermission: Identifiable, Equatable {
  let kind: HealthWriteSampleKind
  let status: HealthWriteAccessStatus

  var id: HealthWriteSampleKind { kind }
  var title: String { kind.title }
  var statusDescription: String { status.description }

  static func defaultWritePermissions(
    statuses: [HealthWriteSampleKind: HealthWriteAccessStatus] = [:]
  ) -> [HealthWritePermission] {
    HealthWriteSampleKind.allCases.map { kind in
      HealthWritePermission(kind: kind, status: statuses[kind] ?? .notDetermined)
    }
  }
}

enum HealthAccessCopy {
  static let healthAppInstructions = "To change access, open iPhone Settings, tap Privacy & Security, tap Health, choose PumpSync, then update the Insulin Delivery and Carbohydrates permissions."
}
