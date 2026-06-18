import SwiftUI

struct HealthAccessView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection("Write Access") {
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

      GlassEffectContainer(spacing: 16) {
        Button {
          Task {
            await services.healthKitService.manageWriteAccess()
          }
        } label: {
          GlassPrimaryLabel(title: "Manage Apple Health Access", systemImage: "heart")
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
      }

      if let message = services.healthKitService.errorMessage {
        GlassSection {
          Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if let message = services.healthKitService.managementMessage {
        GlassSection("Manage Access") {
          Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        GlassSection("Manage Access") {
          Text("PumpSync writes Tandem insulin delivery and carbohydrate samples to Apple Health. You can review or change these permissions at any time in the Health app.")
          .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .navigationTitle("Apple Health Access")
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
