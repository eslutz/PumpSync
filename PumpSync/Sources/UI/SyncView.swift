import SwiftUI
import UIKit

struct SyncView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppServices.self) private var services
  @ScaledMetric(relativeTo: .title3) private var iconColumnWidth = 28
  @State private var showsSubscription = false
  @Environment(\.openConnectionSettings) private var openConnectionSettings

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: services.backendConfigurationStore.mode == .hosted ? "PumpSync service" : "Self-hosted service",
          value: connectionStatus,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled",
          showsProgress: services.authService.isConnecting
        )

        if !services.authService.isSignedIn && !services.authService.isConnecting && syncFailure == nil {
          Text(services.authService.errorMessage ?? "Connect before syncing pump data to Apple Health.")
            .font(.subheadline)
            .foregroundStyle(Color.pumpSyncSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            .padding(.leading, iconColumnWidth + 14)

          GlassDivider()
          Button {
            if services.authService.requiresSubscriptionAction { showsSubscription = true }
            else { services.foregroundRecovery.retryConnection() }
          } label: {
            GlassPrimaryLabel(
              title: services.authService.requiresSubscriptionAction ? "View Subscription" : "Retry Connection",
              systemImage: services.authService.requiresSubscriptionAction ? "creditcard" : "arrow.clockwise"
            )
          }
          .buttonStyle(GroupedRowActionButtonStyle())

          GlassDivider()
          Button(action: openConnectionSettings) {
            GlassNavigationRow("Connection Settings", systemImage: "gearshape")
          }
          .buttonStyle(.plain)
        }

        GlassDivider()

        GlassStatusRow(
          title: "Tandem account",
          value: tandemStatus,
          systemImage: services.credentialStore.hasValidatedCredentials ? "key.fill" : "key.slash"
        )
      }

      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          if let reset = history.resetDescription {
            Text(reset).font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText)
          }
          initialImportMenu

          GlassDivider(leadingPadding: 0)

          Text("Choose how much pump history to import the first time. Future syncs import new data only. Keep PumpSync open while a sync is running; you can move around within PumpSync.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.pumpSyncSecondaryText)
            .padding(.vertical, 8)
        }
      }

      if syncFailure == nil {
        Button {
          if canSync { services.syncCoordinator.startManualSync() }
        } label: {
          SyncButtonLabel(title: syncButtonTitle, isSyncing: services.syncCoordinator.isSyncing)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).font(.title3.weight(.semibold))
        .disabled(!canSync)
      }

      if services.syncCoordinator.isSyncing {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          if let presentation = SyncStatusPresentation.make(
            for: services.syncCoordinator.operationState, now: context.date
          ) {
            Text(presentation.detail)
              .font(.subheadline)
              .foregroundStyle(Color.pumpSyncSecondaryText)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityIdentifier("SyncProgressDetail")
          }
        }
      }

      if syncFailure == nil, services.authService.isSignedIn,
         let message = Self.readinessMessage(
           isBackendConnected: true,
           isConnecting: services.authService.isConnecting,
           hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
           hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
         ) {
        GlassSection {
          Text(message).foregroundStyle(Color.pumpSyncSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if let lastSuccessfulSyncAt = history.lastSuccess {
        VStack(alignment: .leading, spacing: 8) {
          GlassSection("Last Successful Sync") {
            GlassStatusRow(
              title: "Completed",
              value: formattedDate(lastSuccessfulSyncAt),
              systemImage: "checkmark.circle.fill",
              tint: .green
            )
          }
          if let summary = history.countsSummary {
            Text(summary)
              .font(.subheadline)
              .foregroundStyle(Color.pumpSyncSecondaryText)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 16)
              .accessibilityIdentifier("SyncCompletionSummary")
          }
          if case .succeeded(let completion) = services.syncCoordinator.operationState, let notice = completion.notice {
            Text(notice).font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText)
              .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 16)
              .accessibilityIdentifier("SyncCompletionDetail")
          }
          if Date().timeIntervalSince(lastSuccessfulSyncAt) >= AppConstants.staleSyncInterval {
            Label("Apple Health may be out of date.", systemImage: "clock.badge.exclamationmark")
              .font(.footnote)
              .foregroundStyle(Color.pumpSyncSecondaryText)
              .padding(.horizontal, 16)
              .accessibilityIdentifier("StaleSyncNotice")
          }
        }
      }
    }
    .navigationTitle("Sync")
    .sheet(isPresented: $showsSubscription, onDismiss: {
      if syncFailure?.recovery == .openSubscription,
         !services.authService.requiresSubscriptionAction, canSync {
        services.syncCoordinator.dismissResult()
      }
    }) {
      PumpSyncSubscriptionStoreView(isPresented: $showsSubscription)
    }
    .onAppear {
      services.healthKitService.refreshAuthorizationStatus()
      if canSync, syncFailure?.recovery == .openSettings {
        services.syncCoordinator.dismissResult()
      }
    }
  }

  private var syncFailure: SyncFailure? {
    if case .failed(let failure) = services.syncCoordinator.operationState { return failure }
    return nil
  }

  private var recoveryTitle: String {
    SyncStatusPresentation.make(for: services.syncCoordinator.operationState, now: Date())?.actionTitle ?? "Try Again"
  }

  private var recoveryIcon: String {
    switch syncFailure?.recovery {
    case .openSubscription: return "creditcard"
    case .openSettings: return "gearshape"
    default: return "arrow.clockwise"
    }
  }

  private func recoverSync() {
    switch syncFailure?.recovery {
    case .openSubscription: showsSubscription = true
    case .openSettings: openConnectionSettings()
    default: services.syncCoordinator.startManualSync()
    }
  }

  private var initialImportMenu: some View {
    LabeledMenuPickerRow(title: "History range", systemImage: "calendar.badge.clock") {
        NativeMenuPicker("History range", selection: Binding(
          get: { services.syncMetadataStore.metadata.initialImportRange },
          set: { services.syncMetadataStore.setInitialImportRange($0) }
        )) {
          ForEach(InitialImportRange.allCases) { range in
            Text(dynamicTypeSize.isAccessibilitySize ? range.compactTitle : range.title).tag(range)
          }
        }
        .accessibilityIdentifier("HistoryRangePicker")
        .accessibilityHint("Changes how much pump history to import during the first sync")
    }
  }

  private var history: SyncHistoryPresentation {
    SyncHistoryPresentation(metadata: services.syncMetadataStore.metadata,
      attempts: (services.syncCoordinator.attemptStore.active.map { [$0] } ?? []) + services.syncCoordinator.attemptStore.history)
  }

  private var canSync: Bool {
    services.authService.isSignedIn
      && services.credentialStore.hasValidatedCredentials
      && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
      && !services.authService.isReplacingConnection
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
          .rowIconColumn()
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
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)

      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
      .contentShape(Rectangle())
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
