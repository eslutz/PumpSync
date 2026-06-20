import SwiftUI

struct HealthAccessView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      Text("PumpSync writes insulin delivery and carbohydrate samples to Apple Health. It does not read other Health data.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)

      GlassSection("Write Permissions") {
        ForEach(Array(services.healthKitService.writePermissions.enumerated()), id: \.element.id) { index, permission in
          GlassStatusRow(
            title: permission.title,
            value: permission.statusDescription,
            systemImage: permission.kind.systemImage,
            tint: permission.status == .sharingAuthorized ? .green : .accentColor
          )

          if index < services.healthKitService.writePermissions.count - 1 {
            GlassDivider()
          }
        }
      }

      if let message = services.healthKitService.errorMessage {
        GlassSection {
          Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      GlassSection("Change Access") {
        Text(HealthAccessCopy.healthAppInstructions)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .navigationTitle("Apple Health")
    .task {
      services.healthKitService.refreshAuthorizationStatus()
    }
  }

}

private extension HealthWriteSampleKind {
  var systemImage: String {
    switch self {
    case .insulinDelivery:
      return "syringe"
    case .dietaryCarbohydrates:
      return "fork.knife"
    }
  }
}
