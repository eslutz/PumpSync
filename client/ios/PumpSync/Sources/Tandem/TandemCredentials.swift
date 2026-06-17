import Foundation

struct TandemCredentials: Codable, Equatable {
  var username: String
  var password: String
  var region: String

  var redactedUsername: String {
    guard let atIndex = username.firstIndex(of: "@") else {
      return username.isEmpty ? "" : "\(username.prefix(2))..."
    }

    return "\(username[..<atIndex])@..."
  }
}

enum TandemRegion: String, CaseIterable, Identifiable {
  case us = "us"
  case eu = "eu"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .us:
      return "United States"
    case .eu:
      return "Europe"
    }
  }
}
