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
          detail: "Your pump account sign-in is stored securely on this device.",
          systemImage: "key"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Sent only for sync",
          detail: "Your sign-in is sent securely only while PumpSync is syncing.",
          systemImage: "lock.shield"
        )
      }

      GlassSection("Pump Data") {
        DataHandlingRow(
          title: "Not retained after write",
          detail: "PumpSync removes the downloaded pump data after Apple Health confirms it was saved.",
          systemImage: "externaldrive.badge.checkmark"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Duplicate prevention",
          detail: "PumpSync keeps a secure record on this device so the same pump data is not added to Apple Health twice.",
          systemImage: "checkmark.seal"
        )
      }

      GlassSection("Other Devices") {
        DataHandlingRow(
          title: "Configure each device",
          detail: "Your pump account sign-in is not synced through iCloud. Set it up separately on each device.",
          systemImage: "iphone"
        )
      }

      GlassSection("Data Deletion") {
        DataHandlingRow(
          title: "Delete PumpSync data",
          detail: "PumpSync can prepare an email asking support to delete information linked to this app installation.",
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

            Text("Request Data Deletion")
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
    Please delete metadata stored by the PumpSync-hosted backend for this installation.

    PumpSync installation ID:
    \(services.backendConfigurationStore.installationId)

    Do not include pump account passwords or tokens, screenshots containing health data, or other sensitive medical details in this request.
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
