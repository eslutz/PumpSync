using PumpSync.Application.Abstractions;
using PumpSync.Domain.Samples;
using PumpSync.Domain.Tandem;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Normalization;

public sealed class TandemSampleNormalizer : ISampleNormalizer
{
    public IReadOnlyList<NormalizedSample> Normalize(UserId userId, IReadOnlyList<TandemEvent> events)
    {
        var samples = new List<NormalizedSample>();
        var requestsByBolusId = events
            .OfType<TandemBolusRequestedEvent>()
            .GroupBy(x => x.BolusId, StringComparer.Ordinal)
            .ToDictionary(x => x.Key, x => x.OrderBy(y => y.EventTimestamp).First(), StringComparer.Ordinal);

        foreach (var completed in events.OfType<TandemBolusCompletedEvent>())
        {
            if (completed.InsulinDeliveredIu > 0)
            {
                samples.Add(new NormalizedSample(
                    $"tandem-bolus-{completed.BolusId}",
                    userId,
                    completed.DeviceId,
                    NormalizedSampleType.InsulinBolus,
                    completed.InsulinDeliveredIu,
                    "IU",
                    completed.EventTimestamp,
                    completed.EventTimestamp,
                    [completed.SourceEventId],
                    new Dictionary<string, string>
                    {
                        ["deliveryReason"] = "bolus",
                        ["bolusId"] = completed.BolusId,
                        ["completionStatusRaw"] = completed.CompletionStatusRaw.ToString(),
                        ["isExtended"] = completed.IsExtended.ToString()
                    }));
            }

            if (requestsByBolusId.TryGetValue(completed.BolusId, out var request) && request.CarbGrams is > 0)
            {
                samples.Add(new NormalizedSample(
                    $"tandem-carb-{completed.BolusId}",
                    userId,
                    request.DeviceId,
                    NormalizedSampleType.NutritionCarbohydrates,
                    request.CarbGrams.Value,
                    "g",
                    request.EventTimestamp,
                    request.EventTimestamp,
                    [request.SourceEventId],
                    new Dictionary<string, string>
                    {
                        ["bolusId"] = completed.BolusId
                    }));
            }
        }

        foreach (var basal in events.OfType<TandemBasalSegmentEvent>())
        {
            var durationHours = (decimal)(basal.EndAt - basal.StartAt).TotalHours;
            var deliveredIu = decimal.Round(basal.RateIuPerHour * durationHours, 6, MidpointRounding.AwayFromZero);
            if (deliveredIu <= 0)
            {
                continue;
            }

            samples.Add(new NormalizedSample(
                $"tandem-basal-{basal.SourceEventId}",
                userId,
                basal.DeviceId,
                NormalizedSampleType.InsulinBasal,
                deliveredIu,
                "IU",
                basal.StartAt,
                basal.EndAt,
                [basal.SourceEventId],
                new Dictionary<string, string>
                {
                    ["deliveryReason"] = "basal",
                    ["rateIUPerHour"] = basal.RateIuPerHour.ToString("0.######"),
                    ["sourceKind"] = basal.SourceKind
                }));
        }

        return samples
            .GroupBy(x => x.ExternalId, StringComparer.Ordinal)
            .Select(x => x.OrderByDescending(y => y.StartAt).First())
            .OrderBy(x => x.StartAt)
            .ThenBy(x => x.ExternalId, StringComparer.Ordinal)
            .ToArray();
    }
}
