import Foundation

enum InstallStateReconciliationResult: Equatable {
  case freshInstall
  case existingInstall
}

enum InstallStateReconciler {
  static let legacyInstallationIdKey = "backend.installationId"
  private static let installMarker = "direct.install.present"

  static func reconcile(
    defaults: UserDefaults = .standard,
    clearKeychain: () throws -> Void
  ) rethrows -> InstallStateReconciliationResult {
    if defaults.bool(forKey: installMarker) { return .existingInstall }
    if let legacyID = defaults.string(forKey: legacyInstallationIdKey), !legacyID.isEmpty {
      defaults.set(true, forKey: installMarker)
      return .existingInstall
    }
    try clearKeychain()
    defaults.set(true, forKey: installMarker)
    return .freshInstall
  }
}
