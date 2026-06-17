namespace PumpSync.ApiContracts;

public sealed record SampleDto(
    string ExternalId,
    string Type,
    decimal Value,
    string Unit,
    DateTimeOffset StartAt,
    DateTimeOffset EndAt,
    IReadOnlyDictionary<string, string> Metadata,
    SourceDto Source);

public sealed record SourceDto(
    string DeviceId,
    IReadOnlyList<string> EventIds);
