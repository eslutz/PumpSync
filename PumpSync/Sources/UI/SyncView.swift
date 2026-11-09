import SwiftUI
import UIKit

struct SyncView: View {
  @Environment(AppServices.self) private var services
  @State private var showsSubscription = false
  @Environment(\.openConnectionSettings) private var openConnectionSettings

  var body: some View {
    Form {
      Section {
        SyncInlineStatus(state: services.syncCoordinator.operationState)
      }
      Section {
        SyncActionButton(title: syncButtonTitle, isSyncing: services.syncCoordinator.isSyncing,
                         isEnabled: canSync, action: startSync)
        .listRowBackground(Color.clear)
      }
      if let lastSuccess = history.lastSuccess {
        SyncSummarySection(history: history, lastSuccess: lastSuccess)
      }

      if history.lastSuccess == nil {
        Section {
          Picker("History range", selection: Binding(
            get: { services.syncMetadataStore.metadata.initialImportRange },
            set: { services.syncMetadataStore.setInitialImportRange($0) }
          )) {
            ForEach(InitialImportRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("HistoryRangePicker")
          .accessibilityHint("Changes how much pump history to import during the first sync")
          if let reset = history.resetDescription {
            Text(reset).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
          }
          Text("Choose how much pump history to import the first time. Future syncs import new data only. Keep PumpSync open while a sync is running; you can move around within PumpSync.")
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
          Text("Initial Import").foregroundStyle(Color.primary)
        }
        .headerProminence(.increased)
      }

      if services.authService.isSignedIn, let message = Self.readinessMessage(
        isBackendConnected: true,
        isConnecting: services.authService.isConnecting,
        hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
        hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
      ) {
        Section {
          Text(message).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
          Button("Open Settings", systemImage: "gearshape", action: openConnectionSettings)
        }
      }

      Section {
        LabeledContent {
          if services.authService.isConnecting {
            ProgressView(connectionStatus)
          } else {
            Text(connectionStatus)
              .foregroundStyle(Color.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        } label: {
          Text(services.backendConfigurationStore.mode == .hosted ? "PumpSync service" : "Self-hosted service")
        }
        LabeledContent("Tandem account") {
          Text(tandemStatus).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        }
        if let lastAttempt = history.lastAttempt {
          LabeledContent("Last checked") {
            Text(lastAttempt.formatted(date: .abbreviated, time: .shortened))
              .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
          }
        }
        if !services.authService.isSignedIn && !services.authService.isConnecting && syncFailure == nil {
          Text(services.authService.errorMessage ?? "Connect before syncing pump data to Apple Health.")
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
          Button(services.authService.requiresSubscriptionAction ? "View Subscription" : "Retry Connection", action: retryConnection)
          Button("Connection Settings", systemImage: "gearshape", action: openConnectionSettings)
        }
      } header: {
        Text("Connection").foregroundStyle(Color.primary)
      }
      .headerProminence(.increased)
    }
    .font(.body)
    .navigationTitle("Sync")
    .sheet(isPresented: $showsSubscription) {
      NavigationStack {
        SubscriptionSettingsView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showsSubscription = false }
            }
          }
      }
    }
    .onAppear(perform: refreshReadiness)
  }

  private func startSync() {
    if canSync { services.syncCoordinator.startManualSync() }
  }

  private func retryConnection() {
    if services.authService.requiresSubscriptionAction { showsSubscription = true }
    else { services.foregroundRecovery.retryConnection() }
  }

  private func refreshReadiness() {
    services.healthKitService.refreshAuthorizationStatus()
  }

  private var syncFailure: SyncFailure? {
    if case .failed(let failure) = services.syncCoordinator.operationState { return failure }
    return nil
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
      isSyncing: false,
      isConnecting: services.authService.isConnecting,
      hasCompletedInitialSync: services.syncMetadataStore.metadata.lastSuccessfulSyncAt != nil,
      initialImportRange: services.syncMetadataStore.metadata.initialImportRange
    )
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


struct SyncSummarySection: View {
  let history: SyncHistoryPresentation
  let lastSuccess: Date

  var body: some View {
    Section {
      LabeledContent("Completed") {
        Text(lastSuccess.formatted(date: .abbreviated, time: .shortened))
          .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
      }
      LabeledContent("Records received") {
        Text(history.returned.map { $0.formatted() } ?? "Not recorded")
          .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
      }
        .accessibilityIdentifier("SyncRecordsReceived")
      LabeledContent("Samples saved") {
        Text(history.imported.map { $0.formatted() } ?? "Not recorded")
          .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
      }
        .accessibilityIdentifier("SyncSamplesSaved")
      if let skipped = history.permissionSkipped, skipped > 0 {
        Text("\(skipped) records awaiting Health write access.").foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if Date().timeIntervalSince(lastSuccess) >= AppConstants.staleSyncInterval {
        Label("Apple Health may be out of date.", systemImage: "clock.badge.exclamationmark")
          .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("StaleSyncNotice")
      }
      Text("Counts describe this completed sync. Previously saved records are not saved again; records without Health write access are skipped.")
        .foregroundStyle(Color.primary)
        .fixedSize(horizontal: false, vertical: true)
    } header: {
      Text("Last Successful Sync").foregroundStyle(Color.primary)
    }
    .headerProminence(.increased)
    .font(.body)
  }
}

#Preview("Completed sync") {
  let date = Date()
  let metadata = SyncMetadata(lastAttemptAt: date, lastSuccessfulSyncAt: date, lastSampleCount: 48,
                              lastImportedCount: 4, lastErrorMessage: nil)
  NavigationStack {
    Form { SyncSummarySection(history: SyncHistoryPresentation(metadata: metadata, attempts: []), lastSuccess: date) }
      .navigationTitle("Sync")
  }
}

private struct SyncActionButton: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: String
  let isSyncing: Bool
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Group {
        // At accessibility sizes, give the native text the whole button width.
        // Inline progress already communicates activity without a second icon.
        if dynamicTypeSize.isAccessibilitySize {
          stableTitle
        } else {
          Label {
            stableTitle
          } icon: {
            Group {
              if isSyncing { ProgressView().controlSize(.small).tint(.white) }
              else {
                Image(systemName: "arrow.triangle.2.circlepath")
                  .font(.system(size: 20))
                  .foregroundStyle(.white)
              }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
          }
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.glassProminent)
    .tint(Color("ProminentActionColor"))
    .font(.body)
    .controlSize(.large)
    .disabled(!isEnabled)
    .accessibilityLabel(isSyncing ? "Syncing" : title)
    .accessibilityIdentifier("SyncNowButton")
  }

  private var stableTitle: some View {
    // Reserve both states, including wrapping, so starting or finishing a sync
    // never changes the button's height at the current system text size.
    ZStack {
      Text(title).hidden().accessibilityHidden(true)
      Text("Syncing").hidden().accessibilityHidden(true)
      Text(isSyncing ? "Syncing" : title)
    }
    .font(.body)
    .lineLimit(nil)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
  }
}

#Preview("Sync in progress") {
  NavigationStack {
    Form {
      SyncActionButton(title: "Syncing", isSyncing: true, isEnabled: false, action: {})
      Text("Saving new pump samples to Apple Health.").foregroundStyle(.secondary)
    }.navigationTitle("Sync")
  }
}
