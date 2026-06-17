namespace PumpSync.Domain.Tandem;

public abstract record TandemEvent(
    string SourceEventId,
    string DeviceId,
    DateTimeOffset EventTimestamp);

public sealed record TandemBolusRequestedEvent(
    string SourceEventId,
    string DeviceId,
    DateTimeOffset EventTimestamp,
    string BolusId,
    decimal? CarbGrams,
    decimal? BloodGlucoseMgDl) : TandemEvent(SourceEventId, DeviceId, EventTimestamp);

public sealed record TandemBolusCompletedEvent(
    string SourceEventId,
    string DeviceId,
    DateTimeOffset EventTimestamp,
    string BolusId,
    decimal InsulinDeliveredIu,
    string? CompletionStatus,
    int CompletionStatusRaw = 0,
    bool IsExtended = false) : TandemEvent(SourceEventId, DeviceId, EventTimestamp);

public sealed record TandemBasalSegmentEvent(
    string SourceEventId,
    string DeviceId,
    DateTimeOffset StartAt,
    DateTimeOffset EndAt,
    decimal RateIuPerHour,
    string SourceKind = "BasalDelivery") : TandemEvent(SourceEventId, DeviceId, StartAt);
