namespace PumpSync.ApiContracts;

public sealed record TandemCredentialsDto(
    string Username,
    string Password,
    string Region);

public sealed record TandemSyncRequest(
    TandemCredentialsDto Tandem,
    string? DeviceId,
    DateTimeOffset? MinDate,
    DateTimeOffset? MaxDate);

public sealed record TandemSyncResponse(
    string? Cursor,
    IReadOnlyList<SampleDto> Samples);
