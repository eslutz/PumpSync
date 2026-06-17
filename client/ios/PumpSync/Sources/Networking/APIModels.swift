import Foundation

struct AppleSessionRequest: Encodable {
  let identityToken: String
  let authorizationCode: String?
  let email: String?
  let fullName: String?
}

struct AppleSessionResponse: Decodable, Equatable {
  let accessToken: String
  let expiresAt: Date
  let user: UserSummary
}

struct UserSummary: Decodable, Equatable {
  let userId: String
  let email: String?
}

struct StatusResponse: Decodable, Equatable {
  let entitlementActive: Bool
  let tandemCredentialStorage: String
  let tandemDataRetention: String
}

struct TandemSyncRequest: Encodable {
  let tandem: TandemCredentials
  let deviceId: String?
  let minDate: Date?
  let maxDate: Date?
}

struct TandemSyncResponse: Decodable {
  let cursor: String?
  let samples: [SampleDTO]
}

struct SampleDTO: Codable, Identifiable, Equatable {
  let externalId: String
  let type: String
  let value: Decimal
  let unit: String
  let startAt: Date
  let endAt: Date
  let metadata: [String: String]
  let source: SourceDTO

  var id: String { externalId }
}

struct SourceDTO: Codable, Equatable {
  let deviceId: String
  let eventIds: [String]
}
