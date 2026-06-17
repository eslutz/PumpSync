using Microsoft.Extensions.Options;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Tandem.Parsing;

internal sealed class TandemRawEventDecoder(IOptions<TandemSourceOptions> options)
{
    private const int EventLength = 26;

    public IReadOnlyList<TandemRawRecord> Decode(string rawBase64)
    {
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(rawBase64);
        }
        catch (FormatException ex)
        {
            throw new InvalidOperationException("Tandem event payload was not valid base64.", ex);
        }

        if (bytes.Length % EventLength != 0)
        {
            throw new InvalidOperationException("Tandem event payload length was not a multiple of the event record length.");
        }

        var timeZone = ResolveTimeZone(options.Value.EventTimeZoneId);
        var records = new List<TandemRawRecord>(bytes.Length / EventLength);
        for (var offset = 0; offset < bytes.Length; offset += EventLength)
        {
            records.Add(TandemRawRecord.Parse(bytes.AsSpan(offset, EventLength), timeZone));
        }

        return records;
    }

    private static TimeZoneInfo ResolveTimeZone(string id)
    {
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(string.IsNullOrWhiteSpace(id) ? "UTC" : id);
        }
        catch (TimeZoneNotFoundException)
        {
            return TimeZoneInfo.Utc;
        }
        catch (InvalidTimeZoneException)
        {
            return TimeZoneInfo.Utc;
        }
    }
}
