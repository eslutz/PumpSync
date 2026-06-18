using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Auth;

public sealed class AppleServerNotificationValidator : IAppleServerNotificationValidator
{
    private readonly AppleOptions options;
    private readonly ConfigurationManager<OpenIdConnectConfiguration> configurationManager;
    private readonly JwtSecurityTokenHandler tokenHandler = new();

    public AppleServerNotificationValidator(IOptions<AppleOptions> options)
    {
        this.options = options.Value;
        var documentRetriever = new HttpDocumentRetriever { RequireHttps = true };
        configurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
            "https://appleid.apple.com/.well-known/openid-configuration",
            new OpenIdConnectConfigurationRetriever(),
            documentRetriever);
    }

    public async Task<AppleServerNotification> ValidateAsync(string payload, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ClientId))
        {
            throw new InvalidOperationException("Apple ClientId configuration is required.");
        }

        var configuration = await configurationManager.GetConfigurationAsync(cancellationToken);
        var result = await tokenHandler.ValidateTokenAsync(payload, new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.Issuer,
            ValidateAudience = true,
            ValidAudience = options.ClientId,
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = configuration.SigningKeys,
            RequireExpirationTime = false,
            ValidateLifetime = false
        });

        if (!result.IsValid)
        {
            throw new SecurityTokenValidationException("Apple notification payload validation failed.", result.Exception);
        }

        var jwt = tokenHandler.ReadJwtToken(payload);
        if (!jwt.Payload.TryGetValue("events", out var eventsValue))
        {
            throw new SecurityTokenValidationException("Apple notification payload did not include events.");
        }

        return new AppleServerNotification(ParseEvents(eventsValue));
    }

    private static IReadOnlyList<AppleServerNotificationEvent> ParseEvents(object eventsValue)
    {
        using var document = JsonDocument.Parse(ToJson(eventsValue));
        return document.RootElement.ValueKind switch
        {
            JsonValueKind.Object => [ParseEvent(document.RootElement)],
            JsonValueKind.Array => document.RootElement.EnumerateArray().Select(ParseEvent).ToArray(),
            _ => throw new SecurityTokenValidationException("Apple notification events claim is not an object or array.")
        };
    }

    private static AppleServerNotificationEvent ParseEvent(JsonElement element)
    {
        var type = RequiredString(element, "type");
        var subject = RequiredString(element, "sub");
        var email = OptionalString(element, "email");
        return new AppleServerNotificationEvent(type, subject, email);
    }

    private static string RequiredString(JsonElement element, string propertyName) =>
        OptionalString(element, propertyName)
        ?? throw new SecurityTokenValidationException($"Apple notification event did not include {propertyName}.");

    private static string? OptionalString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind is JsonValueKind.String
            ? property.GetString()
            : null;

    private static string ToJson(object value) =>
        value switch
        {
            JsonElement element => element.GetRawText(),
            string text when LooksLikeJson(text) => text,
            string text => JsonSerializer.Serialize(text),
            _ => JsonSerializer.Serialize(value)
        };

    private static bool LooksLikeJson(string value)
    {
        var trimmed = value.TrimStart();
        return trimmed.StartsWith('{') || trimmed.StartsWith('[');
    }
}
