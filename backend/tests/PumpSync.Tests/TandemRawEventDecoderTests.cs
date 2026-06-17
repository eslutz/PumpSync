using System.Buffers.Binary;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Tandem;
using PumpSync.Infrastructure.Options;
using PumpSync.Infrastructure.Tandem.Parsing;
using Xunit;

namespace PumpSync.Tests;

public sealed class TandemRawEventDecoderTests
{
    [Fact]
    public void Decode_RejectsMalformedBase64()
    {
        var decoder = new TandemRawEventDecoder(Options.Create(new TandemSourceOptions()));

        Assert.Throws<InvalidOperationException>(() => decoder.Decode("not base64"));
    }

    [Fact]
    public void Decode_RejectsPartialRecords()
    {
        var decoder = new TandemRawEventDecoder(Options.Create(new TandemSourceOptions()));

        Assert.Throws<InvalidOperationException>(() => decoder.Decode(Convert.ToBase64String([1, 2, 3])));
    }

    [Fact]
    public void Map_ParsesBolusRequestAndCompletion()
    {
        var decoder = new TandemRawEventDecoder(Options.Create(new TandemSourceOptions()));
        var mapper = new TandemDomainEventMapper();
        var payload = Convert.ToBase64String(
        [
            .. BolusRequestedMsg1(seq: 100, bolusId: 12345, carbs: 42, bg: 118),
            .. BolusCompleted(seq: 101, bolusId: 12345, delivered: 4.2f, status: 3)
        ]);

        var events = mapper.Map(decoder.Decode(payload), "pump-1", DateTimeOffset.Parse("2026-06-17T13:00:00Z"));

        var request = Assert.Single(events.OfType<TandemBolusRequestedEvent>());
        Assert.Equal("12345", request.BolusId);
        Assert.Equal(42m, request.CarbGrams);
        Assert.Equal(118m, request.BloodGlucoseMgDl);

        var completed = Assert.Single(events.OfType<TandemBolusCompletedEvent>());
        Assert.Equal("12345", completed.BolusId);
        Assert.Equal(4.2m, decimal.Round(completed.InsulinDeliveredIu, 1));
        Assert.False(completed.IsExtended);
        Assert.Equal(3, completed.CompletionStatusRaw);
    }

    [Fact]
    public void Map_ConvertsBasalDeliveryMilliunitsToSegments()
    {
        var decoder = new TandemRawEventDecoder(Options.Create(new TandemSourceOptions()));
        var mapper = new TandemDomainEventMapper();
        var maxDate = DateTimeOffset.Parse("2008-01-01T00:10:00Z");
        var payload = Convert.ToBase64String(
        [
            .. BasalDelivery(seq: 200, timestampRaw: 0, commandedMilliunitsPerHour: 900),
            .. BasalDelivery(seq: 201, timestampRaw: 300, commandedMilliunitsPerHour: 600)
        ]);

        var events = mapper.Map(decoder.Decode(payload), "pump-1", maxDate);

        var basal = events.OfType<TandemBasalSegmentEvent>().ToArray();
        Assert.Equal(2, basal.Length);
        Assert.Equal(0.9m, basal[0].RateIuPerHour);
        Assert.Equal(TimeSpan.FromMinutes(5), basal[0].EndAt - basal[0].StartAt);
        Assert.Equal(0.6m, basal[1].RateIuPerHour);
        Assert.Equal(maxDate, basal[1].EndAt);
    }

    [Fact]
    public void TandemCredentials_ToStringRedactsSecretValues()
    {
        var credentials = new TandemCredentials("user@example.com", "password", TandemRegion.Us);

        var text = credentials.ToString();

        Assert.DoesNotContain("user@example.com", text, StringComparison.Ordinal);
        Assert.DoesNotContain("password", text, StringComparison.Ordinal);
        Assert.Contains("<redacted>", text, StringComparison.Ordinal);
    }

    private static byte[] BolusRequestedMsg1(uint seq, ushort bolusId, ushort carbs, ushort bg)
    {
        var bytes = Record(64, seq, 0);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(12, 2), bolusId);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(16, 2), carbs);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(14, 2), bg);
        return bytes;
    }

    private static byte[] BolusCompleted(uint seq, ushort bolusId, float delivered, ushort status)
    {
        var bytes = Record(20, seq, 60);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(10, 2), bolusId);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(12, 2), status);
        BinaryPrimitives.WriteSingleBigEndian(bytes.AsSpan(18, 4), delivered);
        return bytes;
    }

    private static byte[] BasalDelivery(uint seq, uint timestampRaw, ushort commandedMilliunitsPerHour)
    {
        var bytes = Record(279, seq, timestampRaw);
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(16, 2), commandedMilliunitsPerHour);
        return bytes;
    }

    private static byte[] Record(ushort eventId, uint seq, uint timestampRaw)
    {
        var bytes = new byte[26];
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(0, 2), eventId);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(2, 4), timestampRaw);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(6, 4), seq);
        return bytes;
    }
}
