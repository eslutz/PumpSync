import SwiftUI

struct PrivacyView: View {
  var body: some View {
    PumpSyncScreen {
      GlassSection("Tandem Credentials") {
        Text("Stored only in this device's Keychain with device-only accessibility. They are sent to PumpSync only during an active sync request over HTTPS.")
          .foregroundStyle(.secondary)
      }

      GlassSection("Tandem Data") {
        Text("Raw Tandem records and normalized samples are not saved by the app after Apple Health confirms the write.")
          .foregroundStyle(.secondary)
      }

      GlassSection("Duplicate Prevention") {
        Text("PumpSync keeps a rolling HMAC ledger of imported external IDs. The ledger cannot be used to recover Tandem event IDs without the device-only key.")
          .foregroundStyle(.secondary)
      }

      GlassSection("Other Devices") {
        Text("Tandem credentials are not synced through iCloud in this version. Each device must be configured separately.")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Privacy")
  }
}
