import SwiftUI

struct AboutPumpSyncView: View {
    var body: some View {
        List {
            Section("Imports") {
                AboutGuideRow(
                    title: "Insulin and carbohydrates",
                    detail: "Imports available basal insulin, bolus insulin, and carbohydrate records with your Apple Health permissions.",
                    systemImage: "heart"
                )
            }
            .headerProminence(.increased)
            Section("How Sync Works") {
                AboutGuideRow(
                    title: "Manual sync",
                    detail: "Start an import from the Sync tab. For your first import, choose how much history to include.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                AboutGuideRow(
                    title: "Automatic updates",
                    detail: "When you open PumpSync, it checks for new records if the last successful sync was at least four hours ago. iOS decides when background updates run.",
                    systemImage: "clock"
                )
                AboutGuideRow(
                    title: "While syncing",
                    detail: "Keep PumpSync open until a foreground sync finishes. You can move between screens.",
                    systemImage: "iphone"
                )
                AboutGuideRow(
                    title: "Last successful sync",
                    detail: "Open Sync Details for counts and times. Previously imported records are skipped to prevent duplicates.",
                    systemImage: "checkmark.circle"
                )
            }
            .headerProminence(.increased)
        }
        .navigationTitle("About PumpSync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutGuideRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.tint)
        }
    }
}
