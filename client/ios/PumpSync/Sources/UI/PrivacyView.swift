import SwiftUI

struct DataHandlingView: View {
  var body: some View {
    PumpSyncScreen(spacing: 16) {
      GlassSection("Credentials") {
        DataHandlingRow(
          title: "Stored on this device",
          detail: "Pump account credentials are kept in this device's Keychain with device-only accessibility.",
          systemImage: "key"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Sent only for sync",
          detail: "Credentials are sent over HTTPS only during an active sync request.",
          systemImage: "lock.shield"
        )
      }

      GlassSection("Pump Data") {
        DataHandlingRow(
          title: "Not retained after write",
          detail: "Raw records and normalized samples are discarded after Apple Health confirms the write.",
          systemImage: "externaldrive.badge.checkmark"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Duplicate prevention",
          detail: "PumpSync keeps a rolling HMAC ledger of imported external IDs. The ledger cannot recover source event IDs without the device-only key.",
          systemImage: "checkmark.seal"
        )
      }

      GlassSection("Other Devices") {
        DataHandlingRow(
          title: "Configure each device",
          detail: "Pump account credentials are not synced through iCloud. Each device must be configured separately.",
          systemImage: "iphone"
        )
      }
    }
    .navigationTitle("Data Handling")
  }
}

private struct DataHandlingRow: View {
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(.tint)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
  }
}
