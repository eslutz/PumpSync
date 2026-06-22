using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.DataDeletion;

public sealed class HmacDataDeletionAuditHasher(IOptions<DataDeletionOptions> options) : IDataDeletionAuditHasher
{
    private readonly DataDeletionOptions options = options.Value;

    public string HashInstallationId(string installationId)
    {
        if (string.IsNullOrWhiteSpace(options.AuditHashSalt))
        {
            throw new InvalidOperationException("DataDeletion__AuditHashSalt is required before writing deletion audit events.");
        }

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(options.AuditHashSalt));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(installationId));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
