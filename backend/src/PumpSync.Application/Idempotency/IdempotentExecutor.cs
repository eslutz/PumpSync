using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Idempotency;

public sealed class IdempotentExecutor(IIdempotencyStore store, IClock clock)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<TResponse> ExecuteAsync<TRequest, TResponse>(
        UserId userId,
        string endpoint,
        string key,
        TRequest request,
        Func<CancellationToken, Task<TResponse>> execute,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            throw new InvalidOperationException("Idempotency-Key is required.");
        }

        var requestHash = Hash(JsonSerializer.Serialize(request, JsonOptions));
        var existing = await store.TryGetAsync(userId, endpoint, key, cancellationToken);
        if (existing is not null)
        {
            if (!string.Equals(existing.RequestHash, requestHash, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Idempotency-Key was already used with a different request body.");
            }

            return JsonSerializer.Deserialize<TResponse>(existing.ResponseJson, JsonOptions)
                ?? throw new InvalidOperationException("Stored idempotency response could not be deserialized.");
        }

        var response = await execute(cancellationToken);
        var responseJson = JsonSerializer.Serialize(response, JsonOptions);
        await store.StoreAsync(new IdempotencyRecord(
            userId,
            endpoint,
            key,
            requestHash,
            responseJson,
            clock.UtcNow.AddHours(24)),
            cancellationToken);

        return response;
    }

    private static string Hash(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes);
    }
}
