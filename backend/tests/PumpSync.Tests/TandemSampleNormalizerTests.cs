using PumpSync.Application.Normalization;
using PumpSync.Domain.Samples;
using PumpSync.Domain.Tandem;
using PumpSync.Domain.Users;
using Xunit;

namespace PumpSync.Tests;

public sealed class TandemSampleNormalizerTests
{
    [Fact]
    public void Normalize_UsesDeliveredBolusAndLinkedCarbs()
    {
        var userId = UserId.New();
        var normalizer = new TandemSampleNormalizer();
        var timestamp = DateTimeOffset.Parse("2026-06-17T12:34:56Z");

        var samples = normalizer.Normalize(userId,
        [
            new TandemBolusRequestedEvent("req-1", "pump-1", timestamp.AddMinutes(-1), "12345", 42m, 118m),
            new TandemBolusCompletedEvent("done-1", "pump-1", timestamp, "12345", 4.2m, "Completed")
        ]);

        Assert.Equal(2, samples.Count);
        var bolus = Assert.Single(samples, x => x.Type == NormalizedSampleType.InsulinBolus);
        Assert.Equal("tandem-bolus-12345", bolus.ExternalId);
        Assert.Equal(4.2m, bolus.Value);
        Assert.Equal("IU", bolus.Unit);
        Assert.Equal("bolus", bolus.Metadata["deliveryReason"]);

        var carbs = Assert.Single(samples, x => x.Type == NormalizedSampleType.NutritionCarbohydrates);
        Assert.Equal("tandem-carb-12345", carbs.ExternalId);
        Assert.Equal(42m, carbs.Value);
        Assert.Equal("g", carbs.Unit);
        Assert.Equal(timestamp.AddMinutes(-1), carbs.StartAt);
    }

    [Fact]
    public void Normalize_ConvertsBasalRateToCumulativeInsulin()
    {
        var userId = UserId.New();
        var normalizer = new TandemSampleNormalizer();
        var start = DateTimeOffset.Parse("2026-06-17T13:00:00Z");

        var samples = normalizer.Normalize(userId,
        [
            new TandemBasalSegmentEvent("basal-1", "pump-1", start, start.AddMinutes(30), 0.9m)
        ]);

        var basal = Assert.Single(samples);
        Assert.Equal(NormalizedSampleType.InsulinBasal, basal.Type);
        Assert.Equal(0.45m, basal.Value);
        Assert.Equal("basal", basal.Metadata["deliveryReason"]);
        Assert.Equal("0.9", basal.Metadata["rateIUPerHour"]);
    }

    [Fact]
    public void Normalize_OmitsZeroDeliveredSamples()
    {
        var userId = UserId.New();
        var normalizer = new TandemSampleNormalizer();
        var timestamp = DateTimeOffset.Parse("2026-06-17T12:34:56Z");

        var samples = normalizer.Normalize(userId,
        [
            new TandemBolusCompletedEvent("done-1", "pump-1", timestamp, "12345", 0m, "Cancelled"),
            new TandemBasalSegmentEvent("basal-1", "pump-1", timestamp, timestamp.AddMinutes(30), 0m)
        ]);

        Assert.Empty(samples);
    }
}
