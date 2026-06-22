import AppIntents

struct OpenPumpSyncIntent: AppIntent {
  static let title: LocalizedStringResource = "Open PumpSync"
  static let description = IntentDescription("Opens PumpSync.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct PumpSyncShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenPumpSyncIntent(),
      phrases: [
        "Open \(.applicationName)",
        "Launch \(.applicationName)"
      ],
      shortTitle: "Open PumpSync",
      systemImageName: "arrow.triangle.2.circlepath"
    )
  }
}
