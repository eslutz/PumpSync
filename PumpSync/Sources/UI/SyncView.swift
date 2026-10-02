import SwiftUI

struct SyncView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppServices.self) private var services
  @State private var showsSubscription = false

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: "Connection",
          value: connectionStatus,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled",
          showsProgress: services.authService.isConnecting
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

          Text("Choose how much pump history to import the first time. Future syncs import new data only. Keep PumpSync open while a sync is running; you can move around within PumpSync.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
      }

      Button {
        if canSync {
          services.syncCoordinator.startManualSync()
        }
      } label: {
        SyncButtonLabel(title: syncButtonTitle, isSyncing: services.syncCoordinator.isSyncing)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canSync)

      NavigationLink("Preview Import") { RealImportPreviewView(services: services) }
        .buttonStyle(GroupedActionButtonStyle())
        .disabled(!services.authService.isSignedIn || !services.credentialStore.hasValidatedCredentials || services.demoPreviewActive)

      if let message = Self.readinessMessage(
        isBackendConnected: services.authService.isSignedIn,
        isConnecting: services.authService.isConnecting,
        hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
        hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
      ) {
        GlassSection {
          Text(!services.authService.isSignedIn && !services.authService.isConnecting
               ? services.authService.errorMessage ?? message : message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
          if !services.authService.isSignedIn && !services.authService.isConnecting {
            if services.authService.requiresSubscriptionAction {
              Button("View Subscription") { showsSubscription = true }
            } else {
              Button("Retry Connection") { services.foregroundRecovery.retryConnection() }
            }
            NavigationLink("Connection Settings") { SettingsView() }
          }
        }
      }

      if let lastSuccessfulSyncAt = services.syncMetadataStore.metadata.lastSuccessfulSyncAt {
        VStack(alignment: .leading, spacing: 8) {
          GlassSection("Last Successful Sync") {
            GlassStatusRow(
              title: "Completed",
              value: formattedDate(lastSuccessfulSyncAt),
              systemImage: "checkmark.circle.fill",
              tint: .green
            )
          }
          if Date().timeIntervalSince(lastSuccessfulSyncAt) >= AppConstants.staleSyncInterval {
            Label("Apple Health may be out of date.", systemImage: "clock.badge.exclamationmark")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 16)
              .accessibilityIdentifier("StaleSyncNotice")
          }
        }
      }
    }
    .navigationTitle("Sync")
    .sheet(isPresented: $showsSubscription) {
      PumpSyncSubscriptionStoreView(isPresented: $showsSubscription)
    }
    .onAppear {
      services.healthKitService.refreshAuthorizationStatus()
    }
  }

  private var adaptiveMenuLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(spacing: 14))
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
      adaptiveMenuLayout {
        Image(systemName: "calendar.badge.clock")
          .font(.title3)
          .fixedSize()
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text("History range")
            .foregroundStyle(.primary)

          Text(services.syncMetadataStore.metadata.initialImportRange.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }

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
      && !services.demoPreviewActive
  }

  private var connectionStatus: String {
    Self.connectionStatus(
      isSignedIn: services.authService.isSignedIn,
      isConnecting: services.authService.isConnecting
    )
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
    Self.syncButtonTitle(
      isSyncing: services.syncCoordinator.isSyncing,
      isConnecting: services.authService.isConnecting,
      hasCompletedInitialSync: services.syncMetadataStore.metadata.lastSuccessfulSyncAt != nil,
      initialImportRange: services.syncMetadataStore.metadata.initialImportRange
    )
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func connectionStatus(isSignedIn: Bool, isConnecting: Bool) -> String {
    if isSignedIn {
      return "Connected"
    }

    return isConnecting ? "Connecting to PumpSync…" : "Not connected"
  }

  static func syncButtonTitle(
    isSyncing: Bool,
    isConnecting: Bool,
    hasCompletedInitialSync: Bool,
    initialImportRange: InitialImportRange
  ) -> String {
    if isSyncing {
      return "Syncing"
    }

    return hasCompletedInitialSync ? "Sync Now" : initialImportRange.initialSyncButtonTitle
  }

  static func readinessMessage(
    isBackendConnected: Bool,
    isConnecting: Bool = false,
    hasValidatedCredentials: Bool,
    hasAnyHealthWritePermission: Bool
  ) -> String? {
    if !isBackendConnected {
      return isConnecting
        ? "Restoring your secure connection. Sync will start automatically when ready."
        : "PumpSync is not connected. Retry the secure connection, or review your connection settings."
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
    revolutionDuration: TimeInterval = 0.8,
    reduceMotion: Bool = false
  ) -> Double {
    guard isSyncing, !reduceMotion, let startDate, revolutionDuration > 0 else {
      return 0
    }

    let elapsed = max(0, currentDate.timeIntervalSince(startDate))
    let progress = elapsed.truncatingRemainder(dividingBy: revolutionDuration) / revolutionDuration
    return progress * 360
  }
}

private struct SyncButtonLabel: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animationStartDate: Date?

  let title: String
  let isSyncing: Bool

  var body: some View {
    TimelineView(.animation(paused: !isSyncing || reduceMotion)) { context in
      HStack(spacing: 14) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.title3)
          .fixedSize()
          .foregroundStyle(.tint)
          .rotationEffect(.degrees(
            SyncButtonIconRotation.angle(
              isSyncing: isSyncing,
              startDate: animationStartDate,
              currentDate: context.date,
              reduceMotion: reduceMotion
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
