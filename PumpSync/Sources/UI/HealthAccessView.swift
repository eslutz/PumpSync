import SwiftUI

struct HealthAccessView: View {
  @Environment(AppServices.self) private var services
  @State private var isRequestingAccess = false

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

      if !services.healthKitService.hasAnyWritePermission {
        Button {
          Task {
            isRequestingAccess = true
            await services.healthKitService.manageWriteAccess()
            isRequestingAccess = false
          }
        } label: {
          HStack {
            Spacer()
            if isRequestingAccess {
              ProgressView()
            } else {
              Text("Allow Access to Health")
            }
            Spacer()
          }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(isRequestingAccess)
      }

      if let message = services.healthKitService.errorMessage {
        GlassSection {
          Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      GlassSection("Change Access") {
        if services.healthKitService.managementMessage == nil {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(HealthAccessCopy.healthAppInstructionSteps.enumerated()), id: \.offset) { index, step in
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(index + 1)")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.tint)
                  .frame(width: 20)
                Text(step)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(services.healthKitService.managementMessage ?? "")
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
