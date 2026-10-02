import Foundation

enum DataSourceMode: String, Codable, Equatable {
    case tandemSource
    case syntheticDemo
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try? container.decode(String.self)
        self = value.flatMap(Self.init(rawValue:)) ?? .unknown
    }
}

struct ImportConfigurationSnapshot: Equatable {
    let backendIdentity: String?
    let revision: Int
}

struct ImportSessionSnapshot: Equatable {
    let backendIdentity: String
    let configurationRevision: Int
    let credentialRevision: Int
    let sessionFamilyId: String
    let dataSourceMode: DataSourceMode

    static func canonicalBackendIdentity(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? url.absoluteString
    }
}

@MainActor
protocol ImportContextProvider {
    func currentSnapshot() -> ImportSessionSnapshot?
}

struct PlannedImportSample: Equatable, Identifiable {
    let original: SampleDTO
    let convertedValue: Decimal
    var id: String { "\(original.source.deviceId)|\(original.type)|\(original.externalId)" }
}

struct ImportPlan: Equatable {
    let context: ImportSessionSnapshot
    let concentration: InsulinConcentration
    let effectiveMinDate: Date
    let effectiveMaxDate: Date
    let samples: [PlannedImportSample]
    let downloadedRecordCount: Int

    fileprivate init(context: ImportSessionSnapshot, concentration: InsulinConcentration, effectiveMinDate: Date, effectiveMaxDate: Date, samples: [PlannedImportSample], downloadedRecordCount: Int) {
        self.context = context
        self.concentration = concentration
        self.effectiveMinDate = effectiveMinDate
        self.effectiveMaxDate = effectiveMaxDate
        self.samples = samples
        self.downloadedRecordCount = downloadedRecordCount
    }

    func selectingSamples(_ originals: [SampleDTO]) -> ImportPlan {
        let selected = samples.filter { originals.contains($0.original) }
        return ImportPlan(context: context, concentration: concentration, effectiveMinDate: effectiveMinDate, effectiveMaxDate: effectiveMaxDate, samples: selected, downloadedRecordCount: downloadedRecordCount)
    }
}

enum ImportPlanner {
    static func makePlan(response: TandemSyncResponse, context: ImportSessionSnapshot, concentration: InsulinConcentration) throws -> ImportPlan {
        guard response.dataSourceMode != .unknown, context.dataSourceMode != .unknown else { throw HealthImportError.unverifiedSource }
        guard response.dataSourceMode == context.dataSourceMode else { throw HealthImportError.sourceMismatch }
        guard response.effectiveMinDate.timeIntervalSince1970.isFinite, response.effectiveMaxDate.timeIntervalSince1970.isFinite, response.effectiveMinDate <= response.effectiveMaxDate else { throw HealthImportError.invalidWindow }
        var samples: [PlannedImportSample] = []
        var identities: [String: SampleDTO] = [:]
        for sample in response.samples {
            let insulin = sample.type == "insulin.bolus" || sample.type == "insulin.basal"
            guard insulin || sample.type == "nutrition.carbohydrates" else { throw HealthImportError.invalidSample }
            guard sample.unit == (insulin ? "IU" : "g"), !sample.externalId.isEmpty,
                  !sample.value.isNaN, sample.value >= 0,
                  sample.startAt.timeIntervalSince1970.isFinite, sample.endAt.timeIntervalSince1970.isFinite,
                  sample.startAt <= sample.endAt else { throw HealthImportError.invalidSample }
            let converted = insulin ? concentration.appleHealthValue(forPumpReportedValue: sample.value) : sample.value
            guard !converted.isNaN, NSDecimalNumber(decimal: converted).doubleValue.isFinite else { throw HealthImportError.invalidSample }
            let planned = PlannedImportSample(original: sample, convertedValue: converted)
            if let previous = identities[planned.id] {
                guard previous == sample else { throw HealthImportError.conflictingDuplicate }
                continue
            }
            identities[planned.id] = sample
            samples.append(planned)
        }
        samples.sort {
            if $0.original.startAt != $1.original.startAt { return $0.original.startAt < $1.original.startAt }
            return $0.id < $1.id
        }
        return ImportPlan(context: context, concentration: concentration, effectiveMinDate: response.effectiveMinDate, effectiveMaxDate: response.effectiveMaxDate, samples: samples, downloadedRecordCount: response.samples.count)
    }
}
