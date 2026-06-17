import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitService {
  private let healthStore = HKHealthStore()

  private(set) var isAuthorized = false
  var errorMessage: String?

  func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw HealthKitError.notAvailable
    }

    let types = try writableTypes()

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

    isAuthorized = true
    errorMessage = nil
  }

  func save(samples: [SampleDTO]) async throws -> Int {
    if !isAuthorized {
      try await requestAuthorization()
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
    guard
      let insulin = HKObjectType.quantityType(forIdentifier: .insulinDelivery),
      let carbohydrates = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
    else {
      throw HealthKitError.unsupportedSampleType
    }

    return [insulin, carbohydrates]
  }

  private func makeHealthKitSample(from sample: SampleDTO) -> HKQuantitySample? {
    switch sample.type {
    case "insulin.bolus":
      return insulinSample(sample, reason: .bolus)
    case "insulin.basal":
      return insulinSample(sample, reason: .basal)
    case "nutrition.carbohydrates":
      return carbohydrateSample(sample)
    default:
      return nil
    }
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
