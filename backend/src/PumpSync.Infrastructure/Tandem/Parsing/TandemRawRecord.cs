using System.Buffers.Binary;
using Microsoft.Extensions.Options;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Tandem.Parsing;

internal sealed record TandemRawRecord(
    int Source,
    int EventId,
    uint TimestampRaw,
    uint SequenceNumber,
    byte[] Bytes,
    DateTimeOffset EventTimestamp)
{
    private const int EventLength = 26;
    private const long TandemEpochUnixSeconds = 1199145600;

    public static TandemRawRecord Parse(ReadOnlySpan<byte> bytes, TimeZoneInfo eventTimeZone)
    {
        if (bytes.Length != EventLength)
        {
            throw new InvalidOperationException($"Tandem event records must be {EventLength} bytes.");
        }

        var sourceAndId = BinaryPrimitives.ReadUInt16BigEndian(bytes[..2]);
        var timestampRaw = BinaryPrimitives.ReadUInt32BigEndian(bytes.Slice(2, 4));
        var sequenceNumber = BinaryPrimitives.ReadUInt32BigEndian(bytes.Slice(6, 4));
        var utcLikeTimestamp = DateTimeOffset
            .FromUnixTimeSeconds(TandemEpochUnixSeconds + timestampRaw)
            .UtcDateTime;
        var unspecifiedLocal = DateTime.SpecifyKind(utcLikeTimestamp, DateTimeKind.Unspecified);
        var offset = eventTimeZone.GetUtcOffset(unspecifiedLocal);

        return new TandemRawRecord(
            (sourceAndId & 0xF000) >> 12,
            sourceAndId & 0x0FFF,
            timestampRaw,
            sequenceNumber,
            bytes.ToArray(),
            new DateTimeOffset(unspecifiedLocal, offset));
    }
}
