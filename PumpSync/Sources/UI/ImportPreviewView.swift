import SwiftUI

struct ImportPreviewView: View {
    let controller: ImportPreviewController
    let retry: () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var expandedRecords: Set<String> = []

    var body: some View {
        List {
            Section {
                Text("Viewing or refreshing these records doesn’t change Apple Health.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("PreviewSafetyNotice")
            }
            switch controller.state {
                case .idle:
                  Section {
                    Text("Load records from your connected Tandem account to inspect them here.")
                    Button("Load Records") { Task { await retry() } }
                        .frame(minHeight: 44)
                  }
                case .loading:
                  Section {
                    ProgressView("Loading records from Tandem…")
                    Button("Cancel") { controller.cancel() }
                        .frame(minHeight: 44)
                  }
                case .failed(let message):
                  Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await retry() } }
                        .frame(minHeight: 44)
                  }
                case .ready(let plan):
                  Section {
                    summary(plan)
                  }
                  Section("Records") {
                    if plan.samples.isEmpty {
                        Text("No records in this time range")
                    }
                    ForEach(controller.recordsNewestFirst) { sample in
                        ImportPreviewRecordRow(
                            sample: sample,
                            concentration: plan.concentration,
                            isExpanded: Binding(
                                get: { expandedRecords.contains(sample.id) },
                                set: { expanded in
                                    if expanded { expandedRecords.insert(sample.id) }
                                    else { expandedRecords.remove(sample.id) }
                                }
                            )
                        )
                    }
                  }
                }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Inspect Source Data")
        .onDisappear { controller.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.suspend() }
            if phase == .active { controller.validateSnapshot() }
        }
    }

    private func summary(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(plan.samples.count) records · Newest first")
                .font(.headline)
            if let loadedAt = controller.loadedAt {
                Text("Loaded \(loadedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Insulin equivalents: \(plan.concentration.title)")
                .font(.subheadline).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Time range").font(.subheadline.weight(.semibold))
                Text("Newest: \(plan.effectiveMaxDate.formatted(date: .abbreviated, time: .shortened))")
                Text("Oldest: \(plan.effectiveMinDate.formatted(date: .abbreviated, time: .shortened))")
                Text("Time zone: \(TimeZone.current.identifier)").foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if controller.isRefreshing {
                ProgressView("Refreshing records…")
                Button { controller.suspend() } label: {
                    Text("Cancel Refresh")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            } else {
                if let error = controller.refreshError {
                    Text("\(error) Showing the records loaded earlier.")
                        .foregroundStyle(.secondary)
                }
                Button { Task { await retry() } } label: {
                    Text("Refresh Records")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

private struct ImportPreviewRecordRow: View {
    let sample: PlannedImportSample
    let concentration: InsulinConcentration
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if isInsulin {
                    Text("Apple Health equivalent: \(sample.convertedValue.formatted()) IU")
                    Text("Calculated using \(concentration.title) (\(concentration.healthMultiplierFactor)× pump-reported amount).")
                    Text("This calculation doesn’t confirm an Apple Health import.")
                }
                Text("Source: \(sample.original.source.deviceId)")
                Text("Start: \(sample.original.startAt.formatted())")
                Text("End: \(sample.original.endAt.formatted())")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if isInsulin {
                    Text("Pump-reported: \(sample.original.value.formatted()) units")
                } else {
                    Text("\(sample.original.value.formatted()) \(sample.original.unit)")
                }
                Text(timeRange).font(.subheadline).foregroundStyle(Color.secondary)
            }
            .foregroundStyle(Color.primary)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("InspectionRecord-\(sample.id)")
    }

    private var isInsulin: Bool { sample.original.type.hasPrefix("insulin.") }

    private var title: String {
        switch sample.original.type {
        case "insulin.bolus": "Bolus insulin"
        case "insulin.basal": "Basal insulin"
        default: "Carbohydrates"
        }
    }

    private var timeRange: String {
        let start = sample.original.startAt.formatted(date: .abbreviated, time: .shortened)
        guard sample.original.type == "insulin.basal" else { return start }
        let sameDay = Calendar.current.isDate(sample.original.startAt, inSameDayAs: sample.original.endAt)
        let end = sample.original.endAt.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
}

struct RealImportPreviewView: View {
    @State private var session: RealImportPreviewSession
    @Environment(\.scenePhase) private var scenePhase

    init(services: AppServices) {
        _session = State(initialValue: RealImportPreviewSession(apiClient: services.apiClient, authService: services.authService, credentialStore: services.credentialStore, metadataStore: services.syncMetadataStore, concentrationStore: services.insulinConcentrationStore, diagnostics: services.diagnosticsLogStore))
    }

    var body: some View {
        ImportPreviewView(controller: session.controller, retry: session.load)
            .task { await session.loadIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await session.loadIfNeeded() } }
            }
            .onChange(of: session.currentContext) { _, _ in session.controller.validateSnapshot() }
    }
}
