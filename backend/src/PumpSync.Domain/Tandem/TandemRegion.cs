namespace PumpSync.Domain.Tandem;

public enum TandemRegion
{
    Us = 1,
    Eu = 2
}

public static class TandemRegionParser
{
    public static TandemRegion Parse(string value) =>
        value.Trim().ToUpperInvariant() switch
        {
            "US" or "USA" => TandemRegion.Us,
            "EU" => TandemRegion.Eu,
            _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unsupported Tandem region.")
        };

    public static string ToWireValue(this TandemRegion region) =>
        region switch
        {
            TandemRegion.Us => "US",
            TandemRegion.Eu => "EU",
            _ => throw new ArgumentOutOfRangeException(nameof(region), region, "Unsupported Tandem region.")
        };
}
