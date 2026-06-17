namespace PumpSync.ApiContracts;

public sealed record StatusResponse(
    bool EntitlementActive,
    string TandemCredentialStorage,
    string TandemDataRetention);
