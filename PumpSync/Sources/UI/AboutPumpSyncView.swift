import SwiftUI

struct AboutPumpSyncView: View {
    var body: some View {
        List {
            Text("Your pump history, in Apple Health.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

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
                detail: "Opening the app also attempts a sync if the last success was at least four hours ago.",
                systemImage: "arrow.triangle.2.circlepath"
            )
              AboutGuideRow(
                title: "Updates in the background",
                detail: "PumpSync requests background updates. iOS decides when they run, so timing isn’t guaranteed.",
                systemImage: "clock"
            )
              AboutGuideRow(
                title: "While syncing",
                detail: "Keep PumpSync open until a foreground sync finishes. You can move between screens.",
                systemImage: "iphone"
            )
              AboutGuideRow(
                title: "Last successful sync",
                detail: "Shows the last completed sync, even when there were no new records.",
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
