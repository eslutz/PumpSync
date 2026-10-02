import SwiftUI

struct ImportPreviewView: View {
    let controller: ImportPreviewController
    let isSample: Bool
    let retry: () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(isSample ? "Sample data — nothing is saved to Apple Health" : "Preview only — nothing has been saved to Apple Health")
                    .font(.headline)
                    .accessibilityIdentifier("PreviewSafetyNotice")
                switch controller.state {
                case .idle:
                    Button("Download Preview") { Task { await retry() } }
                case .loading:
                    ProgressView("Downloading preview…")
                    Button("Cancel") { controller.cancel() }
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry Preview") { Task { await retry() } }
                case .ready(let plan):
                    Text("\(plan.downloadedRecordCount) downloaded records")
                    Text("Insulin concentration: \(plan.concentration.title)")
                    Text("\(plan.effectiveMinDate.formatted()) – \(plan.effectiveMaxDate.formatted())")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Time zone: \(TimeZone.current.identifier)").font(.footnote)
                    if plan.samples.isEmpty { Text("No records in this range") }
                    ForEach(plan.samples) { sample in
                        DisclosureGroup {
                            Text("Source: \(sample.original.source.deviceId)")
                            Text("Start: \(sample.original.startAt.formatted())")
                            Text("End: \(sample.original.endAt.formatted())")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sampleTitle(sample.original.type))
                                Text("\(sample.convertedValue.formatted()) \(sample.original.unit)")
                                if sample.original.type == "insulin.basal" {
                                    Text("\(sample.original.startAt.formatted(date: .abbreviated, time: .shortened)) – \(sample.original.endAt.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                                } else {
                                    Text(sample.original.startAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button("Refresh Preview") { Task { await retry() } }
                }
            }.padding().frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle("Import Preview")
        .onDisappear { controller.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.cancel() } }
    }

    private func sampleTitle(_ type: String) -> String {
        switch type {
        case "insulin.bolus": "Bolus insulin"
        case "insulin.basal": "Basal insulin"
        default: "Carbohydrates"
        }
    }
}

struct RealImportPreviewView: View {
    @State private var session: RealImportPreviewSession
    init(services: AppServices) {
        _session = State(initialValue: RealImportPreviewSession(apiClient: services.apiClient, authService: services.authService, credentialStore: services.credentialStore, metadataStore: services.syncMetadataStore, concentrationStore: services.insulinConcentrationStore, diagnostics: services.diagnosticsLogStore))
    }
    var body: some View {
        ImportPreviewView(controller: session.controller, isSample: false, retry: session.load).task { await session.load() }
    }
}
