using PumpSync.Domain.Users;

namespace PumpSync.Domain.Samples;

public enum NormalizedSampleType
{
    InsulinBolus = 1,
    InsulinBasal = 2,
    NutritionCarbohydrates = 3
}

public sealed record NormalizedSample(
    string ExternalId,
    UserId UserId,
    string DeviceId,
    NormalizedSampleType Type,
    decimal Value,
    string Unit,
    DateTimeOffset StartAt,
    DateTimeOffset EndAt,
    string[] SourceEventIds,
    IReadOnlyDictionary<string, string> Metadata)
{
    public string Cursor => $"{StartAt:yyyyMMddHHmmssfffffff}_{ExternalId}";

    public bool IsInsulin => Type is NormalizedSampleType.InsulinBolus or NormalizedSampleType.InsulinBasal;
}
