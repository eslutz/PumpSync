namespace PumpSync.ApiContracts;

public sealed record StatusResponse(
    bool EntitlementActive,
    string ServiceMode,
    string TandemCredentialStorage,
    string TandemDataRetention);
