import SwiftUI

enum SyncDestination: Hashable { case account, health, details(RecentSync.ID) }

struct SyncView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let navigate: (SyncDestination) -> Void
  let maximumContentWidth: CGFloat

  private var coordinator: SyncCoordinator { services.syncCoordinator }
  private var setupMessage: String? {
    Self.readinessMessage(needsReconnect: services.credentialStore.needsDirectReconnect,
                          hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
                          hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission)
  }

  var body: some View {
    let state = coordinator.dashboardState
    let history = coordinator.dashboardHistory
    let recent = coordinator.recentSyncs
    TimelineView(.explicit(transitionDates(for: state, lastSuccess: history?.lastSuccess))) { context in
      let now = max(context.date, .now)
      let action = primaryAction(for: state)
      let status = status(for: state, now: now)
      let showsStale = history?.lastSuccess.map { now.timeIntervalSince($0) >= AppConstants.staleSyncInterval } ?? false

      Form {
        if status != nil || showsStale {
          Section {
            if let status { SyncInlineStatus(status: status) }
            if showsStale {
              Label("Apple Health may be out of date.", systemImage: "clock.badge.exclamationmark")
                .accessibilityIdentifier("StaleSyncNotice")
            }
          }
        }

        if history?.lastSuccess == nil && (setupMessage == nil || coordinator.isSyncing) {
          rangeSection(history: history)
        }

        recentSyncSections(recent, now: now)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
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
        .padding(.horizontal, 16)
        .frame(maxWidth: maximumContentWidth)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Sync")
    .navigationDestination(for: SyncDestination.self) { destination in
      switch destination {
      case .account: TandemCredentialForm()
      case .health: HealthAccessView()
      case .details(let id): SyncDetailsView(id: id)
      }
    }
    .onAppear { services.healthKitService.refreshAuthorizationStatus() }
  }

  private var localCalendar: Calendar {
    var calendar = calendar
    calendar.timeZone = timeZone
    return calendar
  }

  private func recentSyncSections(_ runs: [RecentSync], now: Date) -> some View {
    let calendar = localCalendar
    let days = RecentSyncDay.groups(for: runs, calendar: calendar)
    return ForEach(days) { day in
      Section {
        ForEach(day.runs) { run in
          NavigationLink(value: SyncDestination.details(run.id)) {
            RecentSyncRow(run: run, isNewest: run.id == runs.first?.id,
                          connectsAbove: run.id != day.runs.first?.id, connectsBelow: run.id != day.runs.last?.id)
          }
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
          .accessibilityIdentifier("RecentSyncRow\(runs.firstIndex(of: run) ?? 0)")
        }
      } header: {
        VStack(alignment: .leading, spacing: 8) {
          if day.id == days.first?.id {
            Text("Recent syncs")
              .font(.title2.weight(.semibold))
              .foregroundStyle(Color(uiColor: .label))
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("RecentSyncsHeading")
          }
          Text(day.title(now: now, calendar: calendar))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: .label))
            .accessibilityAddTraits(.isHeader)
        }
        .textCase(nil)
      }
    }
  }

  private func transitionDates(for state: SyncOperationState, lastSuccess: Date?) -> [Date] {
    var dates = [Date.distantPast]
    if case .running(let progress) = state, progress.trigger != .background {
      dates.append(progress.startedAt.addingTimeInterval(3))
    }
    if case .failed(let failure) = state, let deadline = failure.retryAfter { dates.append(deadline) }
    if let lastSuccess { dates.append(lastSuccess.addingTimeInterval(AppConstants.staleSyncInterval)) }
    if let nextDay = localCalendar.dateInterval(of: .day, for: .now)?.end {
      dates.append(nextDay)
      // All relative labels become absolute within two day boundaries.
      if let followingDay = localCalendar.date(byAdding: .day, value: 1, to: nextDay) { dates.append(followingDay) }
    }
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
      if case .succeeded(let result) = state, let notice = result.notice {
        return SyncStatusPresentation(title: String(localized: "Sync needs attention"), notice: notice,
                                      systemImage: "exclamationmark.circle")
      }
      return nil
    case .running, .failed:
      return SyncStatusPresentation.make(for: state, now: now)
    }
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
  let id: RecentSync.ID

  var body: some View {
    let coordinator = services.syncCoordinator
    Form {
      if let run = coordinator.retainedSync(id: id) {
        Section {
          LabeledContent("Completed", value: run.completedAt.formatted(date: .abbreviated, time: .standard))
          LabeledContent("Records received", value: run.returned?.formatted() ?? String(localized: "Not recorded"))
            .accessibilityIdentifier("SyncRecordsReceived")
          LabeledContent("Samples saved", value: run.saved?.formatted() ?? String(localized: "Not recorded"))
            .accessibilityIdentifier("SyncSamplesSaved")
          if let skipped = run.permissionSkipped, skipped > 0 {
            LabeledContent("Awaiting Health write access", value: skipped.formatted())
          }
        }
        if run.id == coordinator.recentSyncs.first?.id,
           case .succeeded(let result) = coordinator.dashboardState,
           result.permissionSkipped > 0, services.healthKitService.hasAnyWritePermission, !services.healthKitService.isAuthorized {
          // People who intentionally grant only one Health permission can continue manual imports.
          Button("Sync Allowed Types") { coordinator.startManualSync() }
            .disabled(coordinator.hasActiveSyncExecution)
        }
      } else {
        ContentUnavailableView("Sync details unavailable", systemImage: "clock.badge.questionmark")
      }
    }
    .navigationTitle("Sync Details")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RecentSyncRow: View {
  let run: RecentSync
  let isNewest: Bool
  let connectsAbove: Bool
  let connectsBelow: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(run.completedAt, format: .dateTime.hour().minute())
        .font(isNewest ? .headline : .subheadline.weight(.semibold))
      Text(isNewest ? run.summary : run.compactSummary)
        .font(isNewest ? .body : .subheadline)
    }
    .foregroundStyle(Color(uiColor: .label))
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
    .padding(.leading, 40)
    .background(alignment: .leading) {
      VStack(spacing: 0) {
        Rectangle().fill(connectsAbove ? Color.secondary.opacity(0.25) : .clear).frame(width: 2)
        Image(systemName: (run.permissionSkipped ?? 0) > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(.tint)
        Rectangle().fill(connectsBelow ? Color.secondary.opacity(0.25) : .clear).frame(width: 2)
      }
      .frame(width: 28)
      .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}
