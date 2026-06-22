import Foundation

struct CapabilitiesResponse: Decodable, Equatable {
  let apiVersion: String
  let serviceMode: String
  let billingMode: String
  let tandemCredentialStorage: String
  let tandemDataRetention: String
}

struct SubscriptionSessionRequest: Encodable {
  let signedTransactionInfo: String
  let installationId: String
}

struct SelfHostedSessionRequest: Encodable {
  let installationId: String
}

struct BackendSessionResponse: Codable, Equatable {
  let accessToken: String
  let expiresAt: Date
  let entitlementActive: Bool
  let serviceMode: String
}

struct StatusResponse: Decodable, Equatable {
  let entitlementActive: Bool
  let serviceMode: String
  let tandemCredentialStorage: String
  let tandemDataRetention: String
}

struct TandemSyncRequest: Encodable {
  let tandem: TandemCredentials
  let deviceId: String?
  let minDate: Date?
  let maxDate: Date?
}

struct TandemCredentialValidationRequest: Encodable {
  let tandem: TandemCredentials
}

struct TandemCredentialValidationResponse: Decodable, Equatable {
  let validated: Bool
}

struct TandemSyncResponse: Decodable {
  let cursor: String?
  let samples: [SampleDTO]

  enum CodingKeys: String, CodingKey {
    case cursor
    case samples
  }

  init(cursor: String?, samples: [SampleDTO]) {
    self.cursor = cursor
    self.samples = samples
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cursor = try container.decodeIfPresent(FlexibleString.self, forKey: .cursor)?.value
    samples = try container.decode([SampleDTO].self, forKey: .samples)
  }
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
