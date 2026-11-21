import Foundation
import SwiftUI

struct DataHandlingView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.openURL) private var openURL
  @State private var emailUnavailable = false

  var body: some View {
    Form {
      Section("Credentials") {
        DataHandlingRow(
          title: "Stored on this device",
          detail: "Your Tandem sign-in stays in device-only Keychain storage until you remove it. It is not synced through iCloud.",
          systemImage: "key"
        )

        DataHandlingRow(
          title: "Sent for validation, sync and preview",
          detail: "PumpSync sends your sign-in directly to Tandem when you connect your account, sync, or inspect records.",
          systemImage: "lock.shield"
        )
      }
      .headerProminence(.increased)

      Section("Pump Data") {
        DataHandlingRow(
          title: "Temporary processing",
          detail: "Sync payloads are processed in memory and released when the attempt ends, including failure or cancellation. Source inspection keeps records in memory while its screen is open. Apple Health keeps confirmed imports.",
          systemImage: "externaldrive.badge.checkmark"
        )

        DataHandlingRow(
          title: "Duplicate prevention",
          detail: "Hashed sample identifiers and import times remain on this device to prevent repeat imports. This local record is separate from Apple Health and is not shared with another device.",
          systemImage: "checkmark.seal"
        )
      }
      .headerProminence(.increased)

      Section("Other Devices") {
        DataHandlingRow(
          title: "Configure each device",
          detail: "Your pump account sign-in is not synced through iCloud. Set it up separately on each device.",
          systemImage: "iphone"
        )
      }
      .headerProminence(.increased)

      Section {
        Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
      }

      if let installationID = services.legacyInstallationID {
        Section("Earlier PumpSync Versions") {
          Text("If you used the hosted service, include this installation ID when requesting deletion of its operational records. For a server you operated, contact its administrator.")
          Button("Email Deletion Request", systemImage: "envelope") {
            openURL(deletionRequestURL(installationID: installationID)) { accepted in emailUnavailable = !accepted }
          }
          if emailUnavailable {
            Text("Email support@ericslutz.dev and include your installation ID.")
          }
          Button("Copy Installation ID") { DiagnosticsClipboard.copy(installationID) }
          Link("Privacy and Deletion Details", destination: AppConstants.dataDeletionURL)
        }
        .headerProminence(.increased)
      }
    }
    .navigationTitle("Data Handling")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func deletionRequestURL(installationID: String) -> URL {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = "support@ericslutz.dev"
    components.queryItems = [
      URLQueryItem(name: "subject", value: "DELETION REQUEST - PumpSync Support"),
      URLQueryItem(name: "body", value: "Please delete legacy hosted metadata for PumpSync installation \(installationID).")
    ]

    return components.url ?? URL(string: "mailto:support@ericslutz.dev")!
  }
}

private struct DataHandlingRow: View {
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.body)
          .foregroundStyle(.primary)
      }
      .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(.tint)
    }
    .padding(.vertical, 6)
  }
}
