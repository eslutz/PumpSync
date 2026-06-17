using PumpSync.Domain.Users;

namespace PumpSync.Domain.Sync;

public enum SyncJobStatus
{
    Accepted = 1,
    Running = 2,
    Succeeded = 3,
    Failed = 4,
    Duplicate = 5
}

public sealed record SyncJob(
    Guid JobId,
    UserId UserId,
    string? DeviceId,
    DateTimeOffset RequestedAt,
    SyncJobStatus Status);
