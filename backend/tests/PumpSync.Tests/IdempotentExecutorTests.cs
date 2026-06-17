using PumpSync.Application.Abstractions;
using PumpSync.Application.Idempotency;
using PumpSync.Domain.Common;
using PumpSync.Domain.Users;
using Xunit;

namespace PumpSync.Tests;

public sealed class IdempotentExecutorTests
{
    [Fact]
    public async Task ExecuteAsync_ReplaysStoredResponseForSameKeyAndBody()
    {
        var store = new MemoryIdempotencyStore();
        var executor = new IdempotentExecutor(store, new FixedClock());
        var userId = UserId.New();
        var calls = 0;

        var first = await executor.ExecuteAsync(
            userId,
            "POST /test",
            "key-1",
            new TestRequest("same"),
            _ =>
            {
                calls++;
                return Task.FromResult(new TestResponse("created"));
            },
            CancellationToken.None);

        var second = await executor.ExecuteAsync(
            userId,
            "POST /test",
            "key-1",
            new TestRequest("same"),
            _ =>
            {
                calls++;
                return Task.FromResult(new TestResponse("unexpected"));
            },
            CancellationToken.None);

        Assert.Equal("created", first.Value);
        Assert.Equal("created", second.Value);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsSameKeyWithDifferentBody()
    {
        var store = new MemoryIdempotencyStore();
        var executor = new IdempotentExecutor(store, new FixedClock());
        var userId = UserId.New();

        await executor.ExecuteAsync(
            userId,
            "POST /test",
            "key-1",
            new TestRequest("first"),
            _ => Task.FromResult(new TestResponse("created")),
            CancellationToken.None);

        await Assert.ThrowsAsync<InvalidOperationException>(() => executor.ExecuteAsync(
            userId,
            "POST /test",
            "key-1",
            new TestRequest("second"),
            _ => Task.FromResult(new TestResponse("unexpected")),
            CancellationToken.None));
    }

    private sealed record TestRequest(string Value);

    private sealed record TestResponse(string Value);

    private sealed class FixedClock : IClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.Parse("2026-06-17T00:00:00Z");
    }

    private sealed class MemoryIdempotencyStore : IIdempotencyStore
    {
        private readonly Dictionary<(UserId UserId, string Endpoint, string Key), IdempotencyRecord> records = [];

        public Task<IdempotencyRecord?> TryGetAsync(UserId userId, string endpoint, string key, CancellationToken cancellationToken)
        {
            records.TryGetValue((userId, endpoint, key), out var record);
            return Task.FromResult(record);
        }

        public Task StoreAsync(IdempotencyRecord record, CancellationToken cancellationToken)
        {
            records[(record.UserId, record.Endpoint, record.Key)] = record;
            return Task.CompletedTask;
        }
    }
}
