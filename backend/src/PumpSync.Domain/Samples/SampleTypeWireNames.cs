namespace PumpSync.Domain.Samples;

public static class SampleTypeWireNames
{
    public const string InsulinBolus = "insulin.bolus";
    public const string InsulinBasal = "insulin.basal";
    public const string NutritionCarbohydrates = "nutrition.carbohydrates";

    public static string ToWireName(this NormalizedSampleType type) =>
        type switch
        {
            NormalizedSampleType.InsulinBolus => InsulinBolus,
            NormalizedSampleType.InsulinBasal => InsulinBasal,
            NormalizedSampleType.NutritionCarbohydrates => NutritionCarbohydrates,
            _ => throw new ArgumentOutOfRangeException(nameof(type), type, "Unsupported sample type.")
        };

    public static NormalizedSampleType FromWireName(string value) =>
        value.Trim().ToLowerInvariant() switch
        {
            InsulinBolus => NormalizedSampleType.InsulinBolus,
            InsulinBasal => NormalizedSampleType.InsulinBasal,
            NutritionCarbohydrates or "carbohydrates" => NormalizedSampleType.NutritionCarbohydrates,
            "insulin" => NormalizedSampleType.InsulinBolus,
            _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unsupported sample type.")
        };
}
