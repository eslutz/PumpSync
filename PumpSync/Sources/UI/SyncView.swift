import SwiftUI

enum SyncDestination: Hashable { case account, health, details }

struct SyncView: View {
  @Environment(AppServices.self) private var services
  let navigate: (SyncDestination) -> Void

  private var coordinator: SyncCoordinator { services.syncCoordinator }
  private var setupMessage: String? {
    Self.readinessMessage(needsReconnect: services.credentialStore.needsDirectReconnect,
                          hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
                          hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission)
  }

  var body: some View {
    let state = coordinator.dashboardState
    let history = coordinator.dashboardHistory
    // Only the keep-open hint, freshness threshold, and retry deadline require time-based updates.
    let dates = transitionDates(for: state, lastSuccess: history?.lastSuccess)
    TimelineView(.explicit(dates)) { _ in
      let now = Date.now
      let action = primaryAction(for: state)
      Form {
        if let status = status(for: state, now: now) {
          Section {
            SyncInlineStatus(status: status)
            if let lastSuccess = history?.lastSuccess {
              if case .failed = state {
                Text(SyncStatusPresentation.lastSynced(lastSuccess)).foregroundStyle(.secondary)
              }
              if now.timeIntervalSince(lastSuccess) >= AppConstants.staleSyncInterval {
                Label("Apple Health may be out of date.", systemImage: "clock.badge.exclamationmark")
                  .accessibilityIdentifier("StaleSyncNotice")
              }
            }
          }
        }

        if history?.lastSuccess == nil && (setupMessage == nil || coordinator.isSyncing) {
          rangeSection(history: history)
        }

        Section {
          Button { perform(action) } label: {
            Text(actionTitle(action))
              .foregroundStyle(.white)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.glassProminent)
          .tint(Color("ProminentActionColor"))
          .controlSize(.large)
          .frame(minHeight: 44)
          .disabled(isActionDisabled(state: state, now: now))
          .accessibilityIdentifier("SyncNowButton")
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
        }

        if history?.lastSuccess != nil || history?.lastAttempt != nil {
          Section {
            NavigationLink("Sync Details", value: SyncDestination.details)
              .accessibilityIdentifier("SyncDetailsLink")
          }
        }
      }
    }
    .navigationTitle("Sync")
    .navigationDestination(for: SyncDestination.self) { destination in
      switch destination {
      case .account: TandemCredentialForm()
      case .health: HealthAccessView()
      case .details: SyncDetailsView()
      }
    }
    .onAppear { services.healthKitService.refreshAuthorizationStatus() }
  }

  private func transitionDates(for state: SyncOperationState, lastSuccess: Date?) -> [Date] {
    var dates = [Date.distantPast]
    if case .running(let progress) = state, progress.trigger != .background {
      dates.append(progress.startedAt.addingTimeInterval(3))
    }
    if case .failed(let failure) = state, let deadline = failure.retryAfter { dates.append(deadline) }
    if let lastSuccess { dates.append(lastSuccess.addingTimeInterval(AppConstants.staleSyncInterval)) }
    return dates.sorted()
  }

  private func status(for state: SyncOperationState, now: Date) -> SyncStatusPresentation? {
    switch state {
    case .idle, .succeeded:
      if let setupMessage {
        return SyncStatusPresentation(title: services.credentialStore.hasValidatedCredentials
          ? String(localized: "Apple Health access required") : String(localized: "Connect your account"),
          detail: setupMessage, systemImage: "exclamationmark.circle")
      }
    case .running, .failed:
      break
    }
    return SyncStatusPresentation.make(for: state, now: now)
  }

  @ViewBuilder
  private func rangeSection(history: SyncHistoryPresentation?) -> some View {
    Section("Initial Import") {
      if coordinator.isSyncing || coordinator.hasActiveSyncExecution {
        LabeledContent("History range", value: (coordinator.activeInitialImportRange
          ?? services.syncMetadataStore.metadata.initialImportRange).title)
          .accessibilityIdentifier("ActiveHistoryRange")
      } else {
        Picker("History range", selection: Binding(
          get: { services.syncMetadataStore.metadata.initialImportRange },
          set: { services.syncMetadataStore.setInitialImportRange($0) }
        )) {
          ForEach(InitialImportRange.allCases) { range in Text(range.title).tag(range) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("HistoryRangePicker")
      }
      if let reset = history?.resetDescription { Text(reset) }
    }
  }

  private enum Action {
    case sync, busy, retry, connect, reconnect, healthSetup, reviewHealth

  }

  private func primaryAction(for state: SyncOperationState) -> Action {
    if case .running = state { return .busy }
    if case .failed(let failure) = state {
      if failure.recovery == .account { return .reconnect }
      if failure.recovery == .health { return .reviewHealth }
    }
    if !services.credentialStore.hasValidatedCredentials {
      return services.credentialStore.hasStoredCredentials ? .reconnect : .connect
    }
    if !services.healthKitService.hasAnyWritePermission { return .healthSetup }
    if case .failed = state { return .retry }
    if case .succeeded(let result) = state, result.permissionSkipped > 0,
       !services.healthKitService.isAuthorized { return .reviewHealth }
    return .sync
  }

  private func isActionDisabled(state: SyncOperationState, now: Date) -> Bool {
    if coordinator.isSyncing || coordinator.hasActiveSyncExecution { return true }
    if case .failed(let failure) = state, let until = failure.retryAfter { return until > now }
    return false
  }

  private func actionTitle(_ action: Action) -> LocalizedStringKey {
    switch action {
    case .busy: "Syncing"
    case .retry: "Try Again"
    case .connect: "Connect to Tandem"
    case .reconnect: "Reconnect to Tandem"
    case .healthSetup: "Set Up Apple Health"
    case .reviewHealth: "Review Health Access"
    case .sync:
      if coordinator.dashboardHistory?.lastSuccess != nil { "Sync Now" }
      else { LocalizedStringKey(services.syncMetadataStore.metadata.initialImportRange.initialSyncButtonTitle) }
    }
  }

  private func perform(_ action: Action) {
    switch action {
    case .connect, .reconnect: navigate(.account)
    case .healthSetup, .reviewHealth: navigate(.health)
    case .sync, .retry: coordinator.startManualSync()
    case .busy: break
    }
  }

  static func readinessMessage(needsReconnect: Bool, hasValidatedCredentials: Bool,
                               hasAnyHealthWritePermission: Bool) -> String? {
    if needsReconnect { return String(localized: "Reconnect your saved account to sync directly with Tandem.") }
    if !hasValidatedCredentials { return String(localized: "Sign in to your Tandem account to sync your pump history.") }
    if !hasAnyHealthWritePermission { return String(localized: "Enable at least one Apple Health write permission before syncing.") }
    return nil
  }
}

private struct SyncDetailsView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    let coordinator = services.syncCoordinator
    let history = coordinator.dashboardHistory
    Form {
      if let history, let lastSuccess = history.lastSuccess {
        Section("Last Successful Sync") {
          LabeledContent("Completed", value: lastSuccess.formatted(date: .abbreviated, time: .standard))
          LabeledContent("Records received", value: history.returned?.formatted() ?? String(localized: "Not recorded"))
            .accessibilityIdentifier("SyncRecordsReceived")
          LabeledContent("Samples saved", value: history.imported?.formatted() ?? String(localized: "Not recorded"))
            .accessibilityIdentifier("SyncSamplesSaved")
          if let skipped = history.permissionSkipped, skipped > 0 {
            LabeledContent("Awaiting Health write access", value: skipped.formatted())
          }
        }
      }
      if let lastAttempt = history?.lastAttempt {
        LabeledContent("Last attempt started", value: lastAttempt.formatted(date: .abbreviated, time: .standard))
      }
      if case .succeeded(let result) = coordinator.dashboardState,
         result.permissionSkipped > 0, services.healthKitService.hasAnyWritePermission, !services.healthKitService.isAuthorized {
        // People who intentionally grant only one Health permission can continue manual imports.
        Button("Sync Allowed Types") { coordinator.startManualSync() }
          .disabled(coordinator.hasActiveSyncExecution)
      }
    }
    .navigationTitle("Sync Details")
    .navigationBarTitleDisplayMode(.inline)
  }
}
