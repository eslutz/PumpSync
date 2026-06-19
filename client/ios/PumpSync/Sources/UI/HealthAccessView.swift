import SwiftUI

struct HealthAccessView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection("Apple Health") {
        Text("PumpSync writes Tandem insulin delivery and carbohydrate samples to Apple Health. It does not read other Health data.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)

        GlassDivider()

        Button {
          Task {
            await services.healthKitService.manageWriteAccess()
          }
        } label: {
          Label(healthActionTitle, systemImage: "heart")
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .buttonStyle(GroupedInlineButtonStyle())
      }

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

      if let message = services.healthKitService.managementMessage {
        GlassSection("Review in Health") {
          Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .navigationTitle("Apple Health")
    .task {
      services.healthKitService.refreshAuthorizationStatus()
    }
  }

  private var healthActionTitle: String {
    if services.healthKitService.writePermissions.contains(where: { $0.status == .notDetermined }) {
      return "Allow Health Writes"
    }

    return "Review in Health"
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
