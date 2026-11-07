import Foundation
import SwiftUI

struct DataHandlingView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var emailUnavailable = false

  var body: some View {
    PumpSyncScreen(spacing: 16) {
      GlassSection("Credentials") {
        DataHandlingRow(
          title: "Stored on this device",
          detail: "Your Tandem sign-in stays in device-only Keychain storage until you remove it. It is not synced through iCloud.",
          systemImage: "key"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Sent for validation, sync and preview",
          detail: "Your sign-in is sent securely when validating your pump account, syncing or previewing real pump data.",
          systemImage: "lock.shield"
        )
      }

      GlassSection("Pump Data") {
        DataHandlingRow(
          title: "Temporary processing",
          detail: "Sync payloads are processed in memory and released when the attempt ends, including failure or cancellation. Source inspection clears its in-memory records when closed or backgrounded. Apple Health keeps confirmed imports.",
          systemImage: "externaldrive.badge.checkmark"
        )

        GlassDivider()

        DataHandlingRow(
          title: "Duplicate prevention",
          detail: "Hashed sample identifiers and import times remain on this device to prevent repeat imports. This local record is separate from Apple Health and is not shared with another device.",
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
          title: "Request server metadata deletion",
          detail: services.backendConfigurationStore.mode == .hosted
            ? "Prepare an email to request deletion of hosted metadata linked to this installation. A draft is not a sent request or completed deletion."
            : "Contact your self-hosted server operator to delete server metadata. Hosted support cannot delete records on your own server.",
          systemImage: "envelope"
        )

        GlassDivider()

        Button {
          if services.backendConfigurationStore.mode == .hosted {
            openURL(dataDeletionRequestURL) { accepted in emailUnavailable = !accepted }
          } else { openURL(AppConstants.dataDeletionURL) }
        } label: {
          HStack(spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
              Image(systemName: "envelope")
                .font(.title3)
                .fixedSize()
                .accessibilityHidden(true)
            }

            Text(services.backendConfigurationStore.mode == .hosted ? "Prepare Deletion Request Email" : "Self-hosted Deletion Instructions")
              .layoutPriority(1)

            Spacer(minLength: 0)
          }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered).tint(.primary)
        .foregroundStyle(.primary)
        .accessibilityHint("Opens request instructions; does not delete data")
        Text("Removing credentials, clearing logs, or requesting server deletion does not remove Apple Health samples or cancel a subscription. Manage those separately in Health and Apple subscription settings.")
          .font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
        if emailUnavailable {
          Text("Email could not open. Contact support@ericslutz.dev with your installation ID from Developer settings. No request has been sent.")
          Button("Copy Installation ID") { DiagnosticsClipboard.copy(services.backendConfigurationStore.installationId) }
            .tint(.primary).frame(minHeight: 44)
        }
        Link(destination: AppConstants.dataDeletionURL) { Text("Full Privacy and Deletion Details").underline() }.foregroundStyle(.primary).frame(minHeight: 44)
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      if !dynamicTypeSize.isAccessibilitySize {
        Image(systemName: systemImage)
          .rowIconColumn()
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Color.pumpSyncSecondaryText)
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
