import SwiftUI
import UIKit

struct SyncView: View {
  @Environment(AppServices.self) private var services

  private enum SetupDestination: Hashable { case account, health }

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
          Text("Choose how much pump history to import the first time. Future syncs import new data only. Keep PumpSync open while a sync is running. You can move between screens.")
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
          Text("Initial Import").foregroundStyle(Color.primary)
        }
        .headerProminence(.increased)
      }

      if let message = Self.readinessMessage(
        needsReconnect: services.credentialStore.needsDirectReconnect,
        hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
        hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
      ) {
        Section {
          Text(message).fixedSize(horizontal: false, vertical: true)
          if services.credentialStore.hasValidatedCredentials {
            NavigationLink("Apple Health", value: SetupDestination.health)
          } else {
            NavigationLink(services.credentialStore.needsDirectReconnect ? "Reconnect to Tandem" : "Tandem Account", value: SetupDestination.account)
          }
        }
      }

      Section {
        LabeledContent("Tandem account") {
          Text(tandemStatus).fixedSize(horizontal: false, vertical: true)
        }
        if let lastAttempt = history.lastAttempt {
          LabeledContent("Last checked") {
            Text(lastAttempt.formatted(date: .abbreviated, time: .shortened))
              .foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
          }
        }
      } header: {
        Text("Connection").foregroundStyle(Color.primary)
      }
      .headerProminence(.increased)
    }
    .font(.body)
    .navigationDestination(for: SetupDestination.self) { destination in
      switch destination {
      case .account: TandemCredentialForm()
      case .health: HealthAccessView()
      }
    }
    .navigationTitle("Sync")
    .onAppear(perform: refreshReadiness)
  }

  private func startSync() {
    if canSync { services.syncCoordinator.startManualSync() }
  }

  private func refreshReadiness() {
    services.healthKitService.refreshAuthorizationStatus()
  }

  private var history: SyncHistoryPresentation {
    SyncHistoryPresentation(metadata: services.syncMetadataStore.metadata,
      attempts: (services.syncCoordinator.attemptStore.active.map { [$0] } ?? []) + services.syncCoordinator.attemptStore.history)
  }

  private var canSync: Bool {
    services.credentialStore.hasValidatedCredentials && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
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
      hasCompletedInitialSync: services.syncMetadataStore.metadata.lastSuccessfulSyncAt != nil,
      initialImportRange: services.syncMetadataStore.metadata.initialImportRange
    )
  }

  static func syncButtonTitle(
    isSyncing: Bool,
    hasCompletedInitialSync: Bool,
    initialImportRange: InitialImportRange
  ) -> String {
    if isSyncing {
      return "Syncing"
    }

    return hasCompletedInitialSync ? "Sync Now" : initialImportRange.initialSyncButtonTitle
  }

  static func readinessMessage(
    needsReconnect: Bool,
    hasValidatedCredentials: Bool,
    hasAnyHealthWritePermission: Bool
  ) -> String? {
    if needsReconnect {
      return "Reconnect your saved account to sync directly with Tandem."
    }

    if !hasValidatedCredentials {
      return "Sign in to your Tandem account to sync your pump history."
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
