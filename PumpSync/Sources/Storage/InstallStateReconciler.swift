import Foundation

enum InstallStateReconciliationResult: Equatable {
  case freshInstall
  case existingInstall
}

enum InstallStateReconciler {
  static func reconcile(
    defaults: UserDefaults = .standard,
    clearKeychain: () throws -> Void
  ) rethrows -> InstallStateReconciliationResult {
    if let installationId = defaults.string(forKey: BackendConfigurationStore.installationIdDefaultsKey),
       !installationId.isEmpty {
      return .existingInstall
    }

    try clearKeychain()
    return .freshInstall
  }
}
