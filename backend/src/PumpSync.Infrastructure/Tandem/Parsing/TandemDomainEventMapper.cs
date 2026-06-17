using System.Buffers.Binary;
using PumpSync.Domain.Tandem;

namespace PumpSync.Infrastructure.Tandem.Parsing;

internal sealed class TandemDomainEventMapper
{
    public IReadOnlyList<TandemEvent> Map(IReadOnlyList<TandemRawRecord> records, string deviceId, DateTimeOffset? maxDate)
    {
        var events = new List<TandemEvent>();
        var basalPoints = new List<BasalPoint>();

        foreach (var record in records.OrderBy(x => x.EventTimestamp).ThenBy(x => x.SequenceNumber))
        {
            switch (record.EventId)
            {
                case 3:
                    basalPoints.Add(new BasalPoint(
                        SourceId(record),
                        record.EventTimestamp,
                        (decimal)ReadSingle(record.Bytes, 10),
                        "BasalRateChange"));
                    break;
                case 20:
                    events.Add(MapBolusCompleted(record, deviceId, false));
                    break;
                case 21:
                    events.Add(MapBolusCompleted(record, deviceId, true));
                    break;
                case 64:
                    events.Add(new TandemBolusRequestedEvent(
                        SourceId(record),
                        deviceId,
                        record.EventTimestamp,
                        ReadUInt16(record.Bytes, 12).ToString(),
                        ReadUInt16(record.Bytes, 16),
                        ReadUInt16(record.Bytes, 14)));
                    break;
                case 279:
                    basalPoints.Add(new BasalPoint(
                        SourceId(record),
                        record.EventTimestamp,
                        ReadUInt16(record.Bytes, 16) / 1000m,
                        "BasalDelivery"));
                    break;
            }
        }

        events.AddRange(MapBasalSegments(basalPoints, deviceId, maxDate));
        return events
            .OrderBy(x => x.EventTimestamp)
            .ThenBy(x => x.SourceEventId, StringComparer.Ordinal)
            .ToArray();
    }

    private static TandemBolusCompletedEvent MapBolusCompleted(TandemRawRecord record, string deviceId, bool isExtended)
    {
        var completionStatusRaw = ReadUInt16(record.Bytes, 12);
        return new TandemBolusCompletedEvent(
            SourceId(record),
            deviceId,
            record.EventTimestamp,
            ReadUInt16(record.Bytes, 10).ToString(),
            (decimal)ReadSingle(record.Bytes, 18),
            CompletionStatusName(completionStatusRaw),
            completionStatusRaw,
            isExtended);
    }

    private static IEnumerable<TandemBasalSegmentEvent> MapBasalSegments(
        IReadOnlyCollection<BasalPoint> points,
        string deviceId,
        DateTimeOffset? maxDate)
    {
        var sorted = points
            .OrderBy(x => x.Timestamp)
            .ThenBy(x => x.SourceId, StringComparer.Ordinal)
            .ToArray();

        for (var i = 0; i < sorted.Length; i++)
        {
            var start = sorted[i].Timestamp;
            var end = i + 1 < sorted.Length
                ? sorted[i + 1].Timestamp
                : maxDate ?? start.AddMinutes(5);
            if (maxDate is not null && end > maxDate.Value)
            {
                end = maxDate.Value;
            }

            if (end <= start)
            {
                continue;
            }

            yield return new TandemBasalSegmentEvent(
                sorted[i].SourceId,
                deviceId,
                start,
                end,
                sorted[i].RateIuPerHour,
                sorted[i].SourceKind);
        }
    }

    private static int ReadUInt16(byte[] bytes, int offset) =>
        BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(offset, 2));

    private static float ReadSingle(byte[] bytes, int offset) =>
        BinaryPrimitives.ReadSingleBigEndian(bytes.AsSpan(offset, 4));

    private static string SourceId(TandemRawRecord record) =>
        $"{record.EventId}-{record.SequenceNumber}";

    private static string CompletionStatusName(int status) =>
        status switch
        {
            0 => "User Aborted",
            1 => "Terminated by Alarm",
            2 => "Terminated by Malfunction",
            3 => "Completed",
            5 => "Bolus rejected",
            6 => "Aborted by PLGS",
            _ => "Unknown"
        };

    private sealed record BasalPoint(
        string SourceId,
        DateTimeOffset Timestamp,
        decimal RateIuPerHour,
        string SourceKind);
}
