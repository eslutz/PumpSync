using PumpSync.ApiContracts;
using PumpSync.Domain.Samples;

namespace PumpSync.Application.Mapping;

public static class SampleMapper
{
    public static SampleDto ToDto(this NormalizedSample sample) =>
        new(
            sample.ExternalId,
            sample.Type.ToWireName(),
            sample.Value,
            sample.Unit,
            sample.StartAt,
            sample.EndAt,
            sample.Metadata,
            new SourceDto(sample.DeviceId, sample.SourceEventIds));
}
