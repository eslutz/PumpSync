using System.Security.Cryptography;
using System.Text;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Users;

namespace PumpSync.Application.UseCases;

internal static class SubjectIdentity
{
    public static AuthenticatedUser Hosted(string originalTransactionId, string installationId) =>
        Create($"hosted:{originalTransactionId}:{installationId}", originalTransactionId, installationId, AuthenticatedUserMode.Hosted);

    public static AuthenticatedUser SelfHosted(string installationId) =>
        Create($"self-hosted:{installationId}", installationId, installationId, AuthenticatedUserMode.SelfHosted);

    private static AuthenticatedUser Create(string seed, string subjectId, string installationId, AuthenticatedUserMode mode)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(seed));
        Span<byte> guidBytes = stackalloc byte[16];
        hash.AsSpan(0, 16).CopyTo(guidBytes);
        return new AuthenticatedUser(new UserId(new Guid(guidBytes)), subjectId, installationId, mode, ["ios"]);
    }
}
