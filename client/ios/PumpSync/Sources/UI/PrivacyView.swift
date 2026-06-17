import SwiftUI

struct PrivacyView: View {
  var body: some View {
    List {
      Section("Tandem Credentials") {
        Text("Stored only in this device's Keychain with device-only accessibility. They are sent to PumpSync only during an active sync request over HTTPS.")
      }

      Section("Tandem Data") {
        Text("Raw Tandem records and normalized samples are not saved by the app after Apple Health confirms the write.")
      }

      Section("Duplicate Prevention") {
        Text("PumpSync keeps a rolling HMAC ledger of imported external IDs. The ledger cannot be used to recover Tandem event IDs without the device-only key.")
      }

      Section("Other Devices") {
        Text("Tandem credentials are not synced through iCloud in this version. Each device must be configured separately.")
      }
    }
    .navigationTitle("Privacy")
  }
}
