using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Tandem;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Tandem;

public sealed class TandemSourceAuthenticator(HttpClient httpClient, IOptions<TandemSourceOptions> options) : ITandemAuthenticator
{
    public async Task<TandemSession> LoginAsync(TandemCredentials credentials, CancellationToken cancellationToken)
    {
        var config = credentials.Region is TandemRegion.Eu ? options.Value.Eu : options.Value.Us;
        using var loginResponse = await httpClient.PostAsJsonAsync(config.LoginUrl, new
        {
            username = credentials.Username,
            password = credentials.Password
        }, cancellationToken);
        loginResponse.EnsureSuccessStatusCode();

        var verifier = Base64Url(RandomNumberGenerator.GetBytes(32));
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        var authorizeUri = $"{config.AuthorizeUrl}?client_id={Uri.EscapeDataString(config.ClientId)}" +
            "&response_type=code" +
            "&scope=openid%20profile%20email" +
            $"&redirect_uri={Uri.EscapeDataString(config.RedirectUri)}" +
            $"&code_challenge={Uri.EscapeDataString(challenge)}" +
            "&code_challenge_method=S256";

        using var authorizeResponse = await httpClient.GetAsync(authorizeUri, cancellationToken);
        var code = ExtractCode(authorizeResponse.RequestMessage?.RequestUri)
            ?? ExtractCode(authorizeResponse.Headers.Location)
            ?? throw new InvalidOperationException("Tandem authorization response did not include an authorization code.");

        using var tokenResponse = await httpClient.PostAsync(config.TokenUrl, new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = config.ClientId,
            ["code"] = code,
            ["redirect_uri"] = config.RedirectUri,
            ["code_verifier"] = verifier
        }), cancellationToken);
        tokenResponse.EnsureSuccessStatusCode();

        using var tokenJson = await JsonDocument.ParseAsync(await tokenResponse.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
        var accessToken = tokenJson.RootElement.GetProperty("access_token").GetString()
            ?? throw new InvalidOperationException("Tandem token response did not include access_token.");
        var idToken = tokenJson.RootElement.GetProperty("id_token").GetString()
            ?? throw new InvalidOperationException("Tandem token response did not include id_token.");
        var expiresIn = tokenJson.RootElement.TryGetProperty("expires_in", out var expiresElement)
            ? expiresElement.GetInt32()
            : 3600;

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(idToken);
        var pumperId = ClaimValue(jwt, "pumperId") ?? ClaimValue(jwt, "pumper_id")
            ?? throw new InvalidOperationException("Tandem id_token did not include pumperId.");
        var accountId = ClaimValue(jwt, "accountId") ?? ClaimValue(jwt, "account_id")
            ?? throw new InvalidOperationException("Tandem id_token did not include accountId.");

        return new TandemSession(credentials.Region, accessToken, pumperId, accountId, null, DateTimeOffset.UtcNow.AddSeconds(expiresIn));
    }

    private static string? ClaimValue(JwtSecurityToken token, string type) =>
        token.Claims.FirstOrDefault(x => string.Equals(x.Type, type, StringComparison.OrdinalIgnoreCase))?.Value;

    private static string? ExtractCode(Uri? uri)
    {
        if (uri is null)
        {
            return null;
        }

        var query = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries);
        foreach (var item in query)
        {
            var parts = item.Split('=', 2);
            if (parts.Length == 2 && string.Equals(parts[0], "code", StringComparison.Ordinal))
            {
                return Uri.UnescapeDataString(parts[1]);
            }
        }

        return null;
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
