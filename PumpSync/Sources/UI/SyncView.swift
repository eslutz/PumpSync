import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: "Connection",
          value: connectionStatus,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Pump data",
          value: tandemStatus,
          systemImage: services.credentialStore.hasValidatedCredentials ? "key.fill" : "key.slash"
        )
      }

      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          initialImportMenu

          GlassDivider(leadingPadding: 0)

          Text("Choose how much pump history to import the first time. Future syncs import new data only.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
      }

      // Sync triggers stay visible after the first sync: this is the only
      // in-app disclosure that syncing also happens automatically.
      GlassSection("How Syncing Runs") {
        Text("You can start a sync yourself anytime. PumpSync also checks for new pump data when the app opens and during background updates when iOS grants time. Background updates usually target data that is less than four hours old, but iOS may delay them.")
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }

      Button {
        Task {
          if canSync {
            await services.syncCoordinator.sync(reason: .manual)
          }
        }
      } label: {
        SyncButtonLabel(title: syncButtonTitle, isSyncing: services.syncCoordinator.isSyncing)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canSync)

      if let message = Self.readinessMessage(
        isBackendConnected: services.authService.isSignedIn,
        hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
        hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
      ) {
        GlassSection {
          Text(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
        }
      }

      if let lastSuccessfulSyncAt = services.syncMetadataStore.metadata.lastSuccessfulSyncAt {
        GlassSection("Last Sync") {
          GlassStatusRow(
            title: "Completed",
            value: formattedDate(lastSuccessfulSyncAt),
            systemImage: "checkmark.circle.fill",
            tint: .green
          )
        }
        if Date().timeIntervalSince(lastSuccessfulSyncAt) >= AppConstants.staleSyncInterval {
          GlassSection {
            Label("Pump data may be out of date. Start a sync to refresh Apple Health.", systemImage: "exclamationmark.triangle")
              .frame(maxWidth: .infinity, alignment: .leading)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Sync")
    .onAppear {
      services.healthKitService.refreshAuthorizationStatus()
    }
  }

  private var initialImportMenu: some View {
    Menu {
      ForEach(InitialImportRange.allCases) { range in
        Button {
          services.syncMetadataStore.setInitialImportRange(range)
        } label: {
          if range == services.syncMetadataStore.metadata.initialImportRange {
            Label(range.title, systemImage: "checkmark")
          } else {
            Text(range.title)
          }
        }
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "calendar.badge.clock")
          .font(.title3)
          .frame(width: 28)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text("History range")
            .foregroundStyle(.primary)

          Text(services.syncMetadataStore.metadata.initialImportRange.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Text("Change")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("History range")
    .accessibilityValue(services.syncMetadataStore.metadata.initialImportRange.title)
    .accessibilityHint("Changes how much pump history to import during the first sync")
  }

  private var canSync: Bool {
    services.authService.isSignedIn
      && services.credentialStore.hasValidatedCredentials
      && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
  }

  private var connectionStatus: String {
    services.authService.isSignedIn ? "Connected" : "Not connected"
  }

  private var tandemStatus: String {
    if services.credentialStore.hasValidatedCredentials {
      return "Ready"
    }

    if services.credentialStore.hasStoredCredentials {
      return "Needs validation"
    }

    return "Not configured"
  }

  private var syncButtonTitle: String {
    if services.syncCoordinator.isSyncing {
      return "Syncing"
    }

    return services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil
      ? services.syncMetadataStore.metadata.initialImportRange.initialSyncButtonTitle
      : "Sync Now"
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func readinessMessage(
    isBackendConnected: Bool,
    hasValidatedCredentials: Bool,
    hasAnyHealthWritePermission: Bool
  ) -> String? {
    if !isBackendConnected {
      return nil
    }

    if !hasValidatedCredentials {
      return "Save your pump account credentials in Settings before syncing."
    }

    if !hasAnyHealthWritePermission {
      return "Enable at least one Apple Health write permission before syncing."
    }

    return nil
  }
}

enum SyncButtonIconRotation {
  static func angle(
    isSyncing: Bool,
    startDate: Date?,
    currentDate: Date,
    revolutionDuration: TimeInterval = 0.8
  ) -> Double {
    guard isSyncing, let startDate, revolutionDuration > 0 else {
      return 0
    }

    let elapsed = max(0, currentDate.timeIntervalSince(startDate))
    let progress = elapsed.truncatingRemainder(dividingBy: revolutionDuration) / revolutionDuration
    return progress * 360
  }
}

private struct SyncButtonLabel: View {
  @State private var animationStartDate: Date?

  let title: String
  let isSyncing: Bool

  var body: some View {
    TimelineView(.animation(paused: !isSyncing)) { context in
      HStack(spacing: 14) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.title3)
          .frame(width: 28)
          .foregroundStyle(.tint)
          .rotationEffect(.degrees(
            SyncButtonIconRotation.angle(
              isSyncing: isSyncing,
              startDate: animationStartDate,
              currentDate: context.date
            )
          ))
          .accessibilityHidden(true)

        Text(title)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(title)
    }
    .onAppear {
      updateAnimationStartDate(isSyncing: isSyncing)
    }
    .onChange(of: isSyncing) { _, newValue in
      updateAnimationStartDate(isSyncing: newValue)
    }
  }

  private func updateAnimationStartDate(isSyncing: Bool) {
    animationStartDate = isSyncing ? Date() : nil
  }
}
