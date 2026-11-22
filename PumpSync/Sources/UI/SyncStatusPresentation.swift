import Foundation

extension SyncCompletion {
  var message: String {
    if saved > 0 {
      let text = AttributedString(localized: "^[\(saved, format: .number) sample](inflect: true) saved to Apple Health")
      return String(text.inflected().characters)
    }
    if received == 0 { return String(localized: "No new samples") }
    if permissionSkipped > 0 { return String(localized: "No samples saved to Apple Health") }
    return String(localized: "All samples already imported")
  }

  var notice: String? {
    var notices: [String] = []
    if permissionSkipped > 0 {
      let text = AttributedString(localized: "^[\(permissionSkipped, format: .number) record](inflect: true) awaiting Health write access.")
      notices.append(String(text.inflected().characters))
    }
    if let gapBefore {
      notices.append(String(localized: "History before \(gapBefore.formatted(date: .abbreviated, time: .omitted)) was outside the 14-day import window."))
    }
    return notices.isEmpty ? nil : notices.joined(separator: " ")
  }
}

struct SyncStatusPresentation: Equatable {
  let title: String
  var detail: String?
  var notice: String?
  let systemImage: String
  var showsProgress = false

  var announcement: String {
    [title, detail, notice].compactMap { $0 }.joined(separator: ". ")
  }

  static func lastSynced(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    formatter.formattingContext = .middleOfSentence
    return String(localized: "Last synced \(formatter.string(from: date))")
  }

  static func make(for state: SyncOperationState, now: Date) -> Self? {
    switch state {
    case .idle:
      return nil
    case .running(let progress):
      let showHint = progress.trigger != .background && now.timeIntervalSince(progress.startedAt) >= 3
      return Self(title: progress.phase.message, detail: showHint ? String(localized: "Keep PumpSync open while syncing.") : nil,
                  systemImage: "arrow.triangle.2.circlepath", showsProgress: true)
    case .succeeded(let result):
      return Self(title: lastSynced(result.completedAt), detail: result.message, notice: result.notice,
                  systemImage: result.notice == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
    case .failed(let failure):
      var detail = failure.message
      if let until = failure.retryAfter, until > now {
        detail += " " + String(localized: "Try again after \(until.formatted(date: .abbreviated, time: .shortened)).")
      }
      return Self(title: String(localized: "Sync needs attention"), detail: detail, systemImage: "exclamationmark.triangle")
    }
  }
}
