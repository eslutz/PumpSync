import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitService {
  private let healthStore = HKHealthStore()
  private let diagnostics: DiagnosticsLogStore?
  private var usesScreenshotFixture = false

  private(set) var isAuthorized = false
  private(set) var writePermissions = HealthWritePermission.defaultWritePermissions()
  var errorMessage: String?
  var managementMessage: String?

  var hasAnyWritePermission: Bool {
    writePermissions.contains { $0.status == .sharingAuthorized }
  }

  init(diagnostics: DiagnosticsLogStore? = nil) {
    self.diagnostics = diagnostics
  }

  func refreshAuthorizationStatus() {
    if usesScreenshotFixture {
      return
    }

    guard HKHealthStore.isHealthDataAvailable() else {
      writePermissions = HealthWritePermission.defaultWritePermissions(
        statuses: Dictionary(
          uniqueKeysWithValues: HealthWriteSampleKind.allCases.map { ($0, .unavailable) }
        )
      )
      isAuthorized = false
      return
    }

    var statuses: [HealthWriteSampleKind: HealthWriteAccessStatus] = [:]
    for (kind, type) in writableTypePairs() {
      statuses[kind] = HealthWriteAccessStatus(healthKitStatus: healthStore.authorizationStatus(for: type))
    }

    writePermissions = HealthWritePermission.defaultWritePermissions(statuses: statuses)
    isAuthorized = writePermissions.allSatisfy { $0.status == .sharingAuthorized }
  }

  func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw HealthKitError.notAvailable
    }

    let types = try writableTypes()
    try await requestAuthorization(toShare: types)

    refreshAuthorizationStatus()
    errorMessage = nil
  }

  func manageWriteAccess() async {
    do {
      guard HKHealthStore.isHealthDataAvailable() else {
        throw HealthKitError.notAvailable
      }

      let types = try writableTypes()
      let requestStatus = try await healthStore.statusForAuthorizationRequest(toShare: types, read: [])

      switch requestStatus {
      case .shouldRequest, .unknown:
        do {
          try await requestAuthorization(toShare: types)
          refreshAuthorizationStatus()
          if isAuthorized {
            managementMessage = nil
            errorMessage = nil
            diagnostics?.record(source: .health, title: "Health write access authorized")
          } else {
            managementMessage = HealthAccessCopy.healthAppInstructions
            errorMessage = nil
            diagnostics?.record(
              source: .health,
              severity: .warning,
              title: "Health authorization incomplete",
              message: "The authorization sheet completed but not all requested write permissions are authorized."
            )
          }
        } catch {
          refreshAuthorizationStatus()
          managementMessage = HealthAccessCopy.healthAppInstructions
          errorMessage = nil
          diagnostics?.record(error: error, source: .health, title: "Health authorization request failed")
        }
      case .unnecessary:
        refreshAuthorizationStatus()
        managementMessage = HealthAccessCopy.healthAppInstructions
        errorMessage = nil
        diagnostics?.record(source: .health, title: "Health permissions already decided")
      @unknown default:
        refreshAuthorizationStatus()
        managementMessage = HealthAccessCopy.healthAppInstructions
        errorMessage = nil
        diagnostics?.record(source: .health, severity: .warning, title: "Unknown Health authorization request status")
      }
    } catch {
      errorMessage = "Apple Health access could not be updated."
      managementMessage = nil
      diagnostics?.record(error: error, source: .health, title: "Health access management failed")
    }
  }

  private func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      healthStore.requestAuthorization(toShare: types, read: []) { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: HealthKitError.authorizationDenied)
        }
      }
    }
  }

  func save(samples: [SampleDTO]) async throws -> Int {
    guard !samples.isEmpty else {
      return 0
    }

    if !hasAnyWritePermission {
      try await requestAuthorization()
    }

    guard hasAnyWritePermission else {
      throw HealthKitError.authorizationDenied
    }

    let objects = samples.compactMap(makeHealthKitSample)
    guard !objects.isEmpty else {
      return 0
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      healthStore.save(objects) { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: HealthKitError.writeFailed)
        }
      }
    }

    return objects.count
  }

  private func writableTypes() throws -> Set<HKSampleType> {
    let types = writableTypePairs().map(\.type)
    guard types.count == HealthWriteSampleKind.allCases.count else {
      throw HealthKitError.unsupportedSampleType
    }

    return Set(types)
  }

  private func writableTypePairs() -> [(kind: HealthWriteSampleKind, type: HKSampleType)] {
    var pairs: [(kind: HealthWriteSampleKind, type: HKSampleType)] = []

    if let insulin = HKObjectType.quantityType(forIdentifier: .insulinDelivery) {
      pairs.append((.insulinDelivery, insulin))
    }

    if let carbohydrates = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
      pairs.append((.dietaryCarbohydrates, carbohydrates))
    }

    return pairs
  }

  private func makeHealthKitSample(from sample: SampleDTO) -> HKQuantitySample? {
    switch sample.type {
    case "insulin.bolus":
      guard canWrite(.insulinDelivery) else {
        return nil
      }
      return insulinSample(sample, reason: .bolus)
    case "insulin.basal":
      guard canWrite(.insulinDelivery) else {
        return nil
      }
      return insulinSample(sample, reason: .basal)
    case "nutrition.carbohydrates":
      guard canWrite(.dietaryCarbohydrates) else {
        return nil
      }
      return carbohydrateSample(sample)
    default:
      return nil
    }
  }

  private func canWrite(_ kind: HealthWriteSampleKind) -> Bool {
    writePermissions.first { $0.kind == kind }?.status == .sharingAuthorized
  }

  private func insulinSample(_ sample: SampleDTO, reason: HKInsulinDeliveryReason) -> HKQuantitySample? {
    guard let type = HKObjectType.quantityType(forIdentifier: .insulinDelivery) else {
      return nil
    }

    let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: decimalToDouble(sample.value))
    var metadata = healthKitMetadata(for: sample)
    metadata[HKMetadataKeyInsulinDeliveryReason] = reason.rawValue

    return HKQuantitySample(
      type: type,
      quantity: quantity,
      start: sample.startAt,
      end: sample.endAt,
      metadata: metadata
    )
  }

  private func carbohydrateSample(_ sample: SampleDTO) -> HKQuantitySample? {
    guard let type = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) else {
      return nil
    }

    let quantity = HKQuantity(unit: .gram(), doubleValue: decimalToDouble(sample.value))

    return HKQuantitySample(
      type: type,
      quantity: quantity,
      start: sample.startAt,
      end: sample.endAt,
      metadata: healthKitMetadata(for: sample)
    )
  }

  private func healthKitMetadata(for sample: SampleDTO) -> [String: Any] {
    var metadata: [String: Any] = [
      HKMetadataKeyExternalUUID: sample.externalId,
      "PumpSyncSourceDeviceId": sample.source.deviceId,
      "PumpSyncSourceEventIds": sample.source.eventIds.joined(separator: ",")
    ]

    for (key, value) in sample.metadata {
      metadata["PumpSync_\(key)"] = value
    }

    return metadata
  }

  private func decimalToDouble(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
  }
}

private extension HealthWriteAccessStatus {
  init(healthKitStatus: HKAuthorizationStatus) {
    switch healthKitStatus {
    case .notDetermined:
      self = .notDetermined
    case .sharingDenied:
      self = .sharingDenied
    case .sharingAuthorized:
      self = .sharingAuthorized
    @unknown default:
      self = .notDetermined
    }
  }
}

enum HealthKitError: LocalizedError {
  case notAvailable
  case authorizationDenied
  case unsupportedSampleType
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .notAvailable:
      return "Health data is not available on this device."
    case .authorizationDenied:
      return "Apple Health authorization was not granted."
    case .unsupportedSampleType:
      return "The required Apple Health sample types are unavailable."
    case .writeFailed:
      return "Apple Health did not confirm the write."
    }
  }
}

#if DEBUG
extension HealthKitService {
  func applyScreenshotAuthorization() {
    usesScreenshotFixture = true
    writePermissions = HealthWritePermission.defaultWritePermissions(
      statuses: Dictionary(
        uniqueKeysWithValues: HealthWriteSampleKind.allCases.map { ($0, .sharingAuthorized) }
      )
    )
    isAuthorized = true
    errorMessage = nil
    managementMessage = HealthAccessCopy.healthAppInstructions
  }
}
#endif
