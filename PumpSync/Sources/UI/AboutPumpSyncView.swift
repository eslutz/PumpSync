import SwiftUI

struct AboutPumpSyncView: View {
    var body: some View {
        PumpSyncScreen(spacing: 28) {
            Text("Your Tandem pump history, in Apple Health.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            AboutGuideRow(
                title: "Insulin and carbohydrates",
                detail: "Imports available basal insulin, bolus insulin, and carbohydrate records with your Apple Health permissions.",
                systemImage: "heart"
            )
            AboutGuideRow(
                title: "Sync when you need to",
                detail: "Tap Sync Now. Opening the app also attempts a sync if none has succeeded yet or the last success was at least four hours ago.",
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

            Text("Last Successful Sync shows the last completed sync, even if there were no new records.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("About PumpSync")
    }
}

private struct AboutGuideRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .rowIconColumn()
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
