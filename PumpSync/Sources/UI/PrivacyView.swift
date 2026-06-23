import Foundation
import SwiftUI

struct DataHandlingView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.openURL) private var openURL

  var body: some View {
    PumpSyncScreen(spacing: 16) {
      GlassSection("Credentials") {
        DataHandlingRow(
          title: "Stored on this device",
          detail: "Pump account credentials are kept on this device in Keychain with device-only accessibility.",
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
          detail: "On this device, PumpSync keeps a rolling HMAC ledger of imported source IDs so repeat syncs do not write duplicates. The server does not store this ledger, and the ledger cannot reveal source event IDs without the device-only key.",
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

      GlassSection("Data Deletion") {
        DataHandlingRow(
          title: "Request hosted metadata deletion",
          detail: "PumpSync can prepare a support email with the installation ID needed to locate hosted metadata associated with this app install.",
          systemImage: "envelope"
        )

        GlassDivider()

        Button {
          openURL(dataDeletionRequestURL)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "trash")
              .font(.title3)
              .frame(width: 28)
              .accessibilityHidden(true)

            Text("Delete Data Request")
              .layoutPriority(1)

            Spacer(minLength: 0)
          }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .accessibilityHint("Opens a prefilled email to PumpSync support with this installation ID")
      }
    }
    .navigationTitle("Data Handling")
  }

  private var dataDeletionRequestURL: URL {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = "support@ericslutz.dev"
    components.queryItems = [
      URLQueryItem(name: "subject", value: "DELETION REQUEST - PumpSync Support"),
      URLQueryItem(name: "body", value: dataDeletionRequestBody)
    ]

    return components.url ?? URL(string: "mailto:support@ericslutz.dev")!
  }

  private var dataDeletionRequestBody: String {
    """
    Please delete PumpSync hosted backend metadata associated with this installation.

    PumpSync installation ID:
    \(services.backendConfigurationStore.installationId)

    Do not include Tandem passwords, Tandem tokens, screenshots containing health data, or other sensitive medical details in this request.
    """
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
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
  }
}
