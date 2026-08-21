import Foundation

struct SubscriptionSessionRequest: Encodable {
  let signedTransactionInfo: String
  let installationId: String
  let deviceEnrollment: HostedDeviceEnrollment
}

struct SelfHostedSessionRequest: Encodable {
  let installationId: String
  let deviceEnrollment: SelfHostedDeviceEnrollment
}

struct SessionChallengeRequest: Encodable {
  let installationId: String
  let purpose: String
  let requestHash: String?
}

struct SessionChallengeResponse: Decodable, Equatable {
  let protocolVersion: Int
  let proofKind: String
  let challengeToken: String
  let expiresAt: Date
}

enum HostedDeviceProofPreparation: String, Equatable {
  case generated
  case reconciliation
  case reused
}

struct HostedDeviceEnrollment: Codable, Equatable {
  let requestId: String
  let issuedAt: Date
  let challengeToken: String
  let keyId: String
  let proofKind: String
  let proof: String
  var preparation: HostedDeviceProofPreparation = .generated

  private enum CodingKeys: String, CodingKey {
    case requestId
    case issuedAt
    case challengeToken
    case keyId
    case proofKind
    case proof
  }
}

struct SelfHostedDeviceEnrollment: Encodable, Equatable {
  let requestId: String
  let issuedAt: Date
  let challengeToken: String
  let publicKey: String
  let signature: String
}

struct SessionRefreshRequest: Encodable, Equatable {
  let installationId: String
  let refreshToken: String
  let requestId: String
  let issuedAt: Date
  let proof: String
}

struct BackendSessionResponse: Codable, Equatable {
  let accessToken: String
  let expiresAt: Date
  let serviceMode: String
  let dataSourceMode: String
  let protocolVersion: Int
  let sessionFamilyId: String
  let refreshToken: String
  let refreshTokenExpiresAt: Date
  let refreshTokenAbsoluteExpiresAt: Date

  var isSyntheticDemo: Bool {
    dataSourceMode == "syntheticDemo"
  }

  var hasRenewableCredential: Bool {
    protocolVersion == 3 &&
      !refreshToken.isEmpty &&
      refreshTokenExpiresAt > Date() &&
      refreshTokenAbsoluteExpiresAt > Date()
  }
}

#if DEBUG
extension BackendSessionResponse {
  init(accessToken: String, expiresAt: Date, serviceMode: String, dataSourceMode: String) {
    self.init(
      accessToken: accessToken,
      expiresAt: expiresAt,
      serviceMode: serviceMode,
      dataSourceMode: dataSourceMode,
      protocolVersion: 3,
      sessionFamilyId: "debug-session-family",
      refreshToken: "debug-refresh-token",
      refreshTokenExpiresAt: .distantFuture,
      refreshTokenAbsoluteExpiresAt: .distantFuture
    )
  }
}
#endif

struct TandemSyncRequest: Encodable {
  let tandem: TandemCredentials
  let minDate: Date?
  let maxDate: Date?
  /// IANA identifier of the device's time zone. Tandem reports pump-local
  /// wall-clock timestamps; without this the backend assumes UTC and every
  /// sample lands hours off in Apple Health.
  let timeZoneIdentifier: String?
}

struct TandemCredentialValidationRequest: Encodable {
  let tandem: TandemCredentials
  let timeZoneIdentifier: String?
}

struct TandemCredentialValidationResponse: Decodable, Equatable {
  let validated: Bool
}

struct TandemSyncResponse: Decodable {
  let samples: [SampleDTO]
  let effectiveMinDate: Date
  let effectiveMaxDate: Date
}

struct SampleDTO: Codable, Equatable {
  let externalId: String
  let type: String
  let value: Decimal
  let unit: String
  let startAt: Date
  let endAt: Date
  let metadata: [String: String]
  let source: SourceDTO

  enum CodingKeys: String, CodingKey {
    case externalId
    case type
    case value
    case unit
    case startAt
    case endAt
    case metadata
    case source
  }

  init(
    externalId: String,
    type: String,
    value: Decimal,
    unit: String,
    startAt: Date,
    endAt: Date,
    metadata: [String: String],
    source: SourceDTO
  ) {
    self.externalId = externalId
    self.type = type
    self.value = value
    self.unit = unit
    self.startAt = startAt
    self.endAt = endAt
    self.metadata = metadata
    self.source = source
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    externalId = try container.decode(FlexibleString.self, forKey: .externalId).value
    type = try container.decode(FlexibleString.self, forKey: .type).value
    value = try container.decode(Decimal.self, forKey: .value)
    unit = try container.decode(FlexibleString.self, forKey: .unit).value
    startAt = try container.decode(Date.self, forKey: .startAt)
    endAt = try container.decode(Date.self, forKey: .endAt)
    source = try container.decode(SourceDTO.self, forKey: .source)

    let decodedMetadata = try container.decodeIfPresent([String: FlexibleString].self, forKey: .metadata) ?? [:]
    metadata = decodedMetadata.mapValues(\.value)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(externalId, forKey: .externalId)
    try container.encode(type, forKey: .type)
    try container.encode(value, forKey: .value)
    try container.encode(unit, forKey: .unit)
    try container.encode(startAt, forKey: .startAt)
    try container.encode(endAt, forKey: .endAt)
    try container.encode(metadata, forKey: .metadata)
    try container.encode(source, forKey: .source)
  }
}

struct SourceDTO: Codable, Equatable {
  let deviceId: String
  let eventIds: [String]

  enum CodingKeys: String, CodingKey {
    case deviceId
    case eventIds
  }

  init(deviceId: String, eventIds: [String]) {
    self.deviceId = deviceId
    self.eventIds = eventIds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    deviceId = try container.decode(FlexibleString.self, forKey: .deviceId).value
    eventIds = try container.decode([FlexibleString].self, forKey: .eventIds).map(\.value)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(deviceId, forKey: .deviceId)
    try container.encode(eventIds, forKey: .eventIds)
  }
}

private struct FlexibleString: Decodable {
  let value: String

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let value = try? container.decode(String.self) {
      self.value = value
    } else if let value = try? container.decode(Int.self) {
      self.value = String(value)
    } else if let value = try? container.decode(Double.self) {
      self.value = String(value)
    } else if let value = try? container.decode(Bool.self) {
      self.value = String(value)
    } else {
      throw DecodingError.typeMismatch(
        String.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected a string-compatible JSON value."
        )
      )
    }
  }
}
