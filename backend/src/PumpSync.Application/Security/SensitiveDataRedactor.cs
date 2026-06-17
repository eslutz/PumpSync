namespace PumpSync.Application.Security;

public static class SensitiveDataRedactor
{
    private static readonly string[] SensitiveKeys =
    [
        "password",
        "username",
        "authorization",
        "token",
        "secret",
        "credential",
        "cookie"
    ];

    public static string RedactKeyValue(string key, string? value)
    {
        if (SensitiveKeys.Any(x => key.Contains(x, StringComparison.OrdinalIgnoreCase)))
        {
            return "[redacted]";
        }

        return value ?? string.Empty;
    }

    public static IReadOnlyDictionary<string, string> Redact(IReadOnlyDictionary<string, string> values)
    {
        return values.ToDictionary(
            pair => pair.Key,
            pair => RedactKeyValue(pair.Key, pair.Value),
            StringComparer.OrdinalIgnoreCase);
    }
}
