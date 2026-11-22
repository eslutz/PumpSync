import SwiftUI

struct HealthAccessView: View {
  @Environment(AppServices.self) private var services
  @State private var isRequestingAccess = false

  var body: some View {
    HealthAccessContent(
      permissions: services.healthKitService.writePermissions,
      hasAnyWritePermission: services.healthKitService.hasAnyWritePermission,
      isAuthorized: services.healthKitService.isAuthorized,
      isRequestingAccess: isRequestingAccess,
      errorMessage: services.healthKitService.errorMessage,
      managementMessage: services.healthKitService.managementMessage,
      requestAccess: {
        Task {
          isRequestingAccess = true
          await services.healthKitService.manageWriteAccess()
          isRequestingAccess = false
        }
      }
    )
    .task { services.healthKitService.refreshAuthorizationStatus() }
  }
}

private struct HealthAccessContent: View {
  let permissions: [HealthWritePermission]
  let hasAnyWritePermission: Bool
  let isAuthorized: Bool
  let isRequestingAccess: Bool
  let errorMessage: String?
  let managementMessage: String?
  let requestAccess: () -> Void

  var body: some View {
    Form {
      Section {
        ForEach(permissions) { permission in
          LabeledContent {
            Text(permission.statusDescription)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          } label: {
            Label {
              Text(permission.title)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
              Image(systemName: permission.kind == .insulinDelivery ? "syringe" : "fork.knife")
                .foregroundStyle(.tint)
            }
          }
        }
      } header: {
        Text("Write Permissions")
          .foregroundStyle(Color.primary)
      } footer: {
        Text("PumpSync requests write access only.")
          .foregroundStyle(Color(uiColor: .label))
          .fixedSize(horizontal: false, vertical: true)
      }
      .headerProminence(.increased)

      if hasAnyWritePermission && !isAuthorized {
        Section {
          Text("Enable the missing permission to import both types while their records are available from Tandem.")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("PartialHealthAccessNotice")
        }
      }

      if permissions.contains(where: { $0.status == .notDetermined }) {
        Section {
          Button(action: requestAccess) {
            if isRequestingAccess {
              HStack { ProgressView(); Text("Requesting Access") }
            } else {
              Text("Allow Access to Health")
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .disabled(isRequestingAccess)
        }
      }

      if let message = errorMessage {
        Section { Text(message) }
      }

      if isAuthorized {
        Section {
          DisclosureGroup("How to Change Access") { instructions }
        }
      } else if permissions.contains(where: { $0.status == .sharingDenied }) || managementMessage != nil {
        Section("Change Access") { instructions }
      } else if permissions.allSatisfy({ $0.status == .unavailable }) {
        Section { Text("Apple Health is unavailable on this device.") }
      }
    }
    .navigationTitle("Apple Health")
    .navigationBarTitleDisplayMode(.inline)
  }
  private var instructions: some View {
    ForEach(Array(HealthAccessCopy.healthAppInstructionSteps.enumerated()), id: \.offset) { index, step in
      Text("\(index + 1). \(step)")
    }
  }

}

#if DEBUG
#Preview("Partial Health access") {
  NavigationStack {
    HealthAccessContent(
      permissions: HealthWritePermission.defaultWritePermissions(statuses: [
        .insulinDelivery: .sharingAuthorized, .dietaryCarbohydrates: .sharingDenied
      ]),
      hasAnyWritePermission: true, isAuthorized: false, isRequestingAccess: false,
      errorMessage: nil, managementMessage: nil, requestAccess: {}
    )
  }
}
#endif
