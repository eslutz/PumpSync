using PumpSync.ApiContracts;

namespace PumpSync.Application.Validation;

public static class TandemSyncRequestValidator
{
    private const int MaxLookbackDays = 14;
    private static readonly HashSet<string> AllowedRegions = new(StringComparer.OrdinalIgnoreCase)
    {
        "us",
        "eu"
    };

    public static void Validate(TandemSyncRequest request, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.Tandem is null)
        {
            throw new InvalidOperationException("Tandem credentials are required.");
        }

        if (string.IsNullOrWhiteSpace(request.Tandem.Username))
        {
            throw new InvalidOperationException("Tandem username is required.");
        }

        if (string.IsNullOrWhiteSpace(request.Tandem.Password))
        {
            throw new InvalidOperationException("Tandem password is required.");
        }

        if (string.IsNullOrWhiteSpace(request.Tandem.Region) || !AllowedRegions.Contains(request.Tandem.Region))
        {
            throw new InvalidOperationException("Tandem region must be 'us' or 'eu'.");
        }

        if (request.MinDate is { } minDate && request.MaxDate is { } maxDate && minDate > maxDate)
        {
            throw new InvalidOperationException("MinDate must be before MaxDate.");
        }

        var earliestAllowed = now.AddDays(-MaxLookbackDays);
        if (request.MinDate is { } requestedMinDate && requestedMinDate < earliestAllowed)
        {
            throw new InvalidOperationException($"Tandem sync windows cannot exceed {MaxLookbackDays} days.");
        }

        if (request.MaxDate is { } requestedMaxDate && requestedMaxDate > now.AddMinutes(5))
        {
            throw new InvalidOperationException("MaxDate cannot be in the future.");
        }
    }
}
