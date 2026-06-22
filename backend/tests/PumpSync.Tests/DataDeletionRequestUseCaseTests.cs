using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;
using PumpSync.Domain.Common;
using PumpSync.Domain.Users;
using Xunit;

namespace PumpSync.Tests;

public sealed class DataDeletionRequestUseCaseTests
{
    [Fact]
    public async Task ExecuteAsync_ReturnsNoRecordsFoundWhenInstallationIdDoesNotMatch()
    {
        var repository = new FakeDeletionRepository();
        var useCase = new DataDeletionRequestUseCase(repository, new FakeAuditHasher(), new FixedClock());

        var report = await useCase.ExecuteAsync(
            new HostedDataDeletionRequest("installation-1", "prod", Execute: false),
            CancellationToken.None);

        Assert.Equal(HostedDataDeletionStatus.NoRecordsFound, report.Status);
        Assert.False(report.Execute);
        Assert.Equal("prod", report.Environment);
        Assert.Equal("installation-1", report.InstallationId);
        Assert.Empty(report.OriginalTransactionIds);
        Assert.Null(report.AuditEventId);
        Assert.Equal(0, report.Found);
        Assert.Equal(0, report.Purged);
        Assert.Empty(report.Tables);
        Assert.Empty(repository.DeletedRecords);
        Assert.Empty(repository.AuditEvents);
    }

    [Fact]
    public async Task ExecuteAsync_DryRunReportsMatchesWithoutDeleting()
    {
        var repository = FakeDeletionRepository.WithRecords();
        var useCase = new DataDeletionRequestUseCase(repository, new FakeAuditHasher(), new FixedClock());

        var report = await useCase.ExecuteAsync(
            new HostedDataDeletionRequest("installation-1", "nonprod", Execute: false),
            CancellationToken.None);

        Assert.Equal(HostedDataDeletionStatus.DryRun, report.Status);
        Assert.False(report.Execute);
        Assert.Equal(["original-transaction-1"], report.OriginalTransactionIds);
        Assert.Equal(5, report.Found);
        Assert.Equal(0, report.Purged);
        Assert.Equal(new HostedDataDeletionTableCount(1, 0), report.Tables["InstallationLookup"]);
        Assert.Equal(new HostedDataDeletionTableCount(1, 0), report.Tables["Installations"]);
        Assert.Equal(new HostedDataDeletionTableCount(1, 0), report.Tables["SubscriptionEntitlements"]);
        Assert.Equal(new HostedDataDeletionTableCount(1, 0), report.Tables["SyncAttempts"]);
        Assert.Equal(new HostedDataDeletionTableCount(1, 0), report.Tables["RateLimitBuckets"]);
        Assert.Empty(repository.DeletedRecords);
        Assert.Empty(repository.AuditEvents);
    }

    [Fact]
    public async Task ExecuteAsync_ExecuteDeletesMatchesAndWritesHashedAuditEvent()
    {
        var repository = FakeDeletionRepository.WithRecords();
        var useCase = new DataDeletionRequestUseCase(repository, new FakeAuditHasher(), new FixedClock());

        var report = await useCase.ExecuteAsync(
            new HostedDataDeletionRequest("installation-1", "prod", Execute: true),
            CancellationToken.None);

        Assert.Equal(HostedDataDeletionStatus.Purged, report.Status);
        Assert.True(report.Execute);
        Assert.NotNull(report.AuditEventId);
        Assert.Equal(5, report.Found);
        Assert.Equal(5, report.Purged);
        Assert.Equal(5, repository.DeletedRecords.Count);

        var audit = Assert.Single(repository.AuditEvents);
        Assert.Equal(report.AuditEventId, audit.EventId);
        Assert.Equal("prod", audit.Environment);
        Assert.Equal(HostedDataDeletionStatus.Purged, audit.Status);
        Assert.Equal("audit-hash", audit.InstallationIdHash);
        Assert.DoesNotContain("installation-1", audit.InstallationIdHash, StringComparison.Ordinal);
        Assert.Equal(["original-transaction-1"], audit.OriginalTransactionIds);
        Assert.Equal(5, audit.Found);
        Assert.Equal(5, audit.Purged);
        Assert.Equal(new HostedDataDeletionTableCount(1, 1), audit.Tables["InstallationLookup"]);
    }

    private sealed class FakeDeletionRepository : IHostedDataDeletionRequestRepository
    {
        private readonly HostedDataDeletionInstallationLinks installationLinks;
        private readonly IReadOnlyList<HostedDataDeletionRecord> entitlementRecords;
        private readonly IReadOnlyList<HostedDataDeletionRecord> hostedUserRecords;

        private FakeDeletionRepository(
            HostedDataDeletionInstallationLinks installationLinks,
            IReadOnlyList<HostedDataDeletionRecord> entitlementRecords,
            IReadOnlyList<HostedDataDeletionRecord> hostedUserRecords)
        {
            this.installationLinks = installationLinks;
            this.entitlementRecords = entitlementRecords;
            this.hostedUserRecords = hostedUserRecords;
        }

        public FakeDeletionRepository()
            : this(new HostedDataDeletionInstallationLinks([], []), [], [])
        {
        }

        public List<HostedDataDeletionRecord> DeletedRecords { get; } = [];

        public List<HostedDataDeletionAuditEvent> AuditEvents { get; } = [];

        public static FakeDeletionRepository WithRecords() => new(
            new HostedDataDeletionInstallationLinks(
                ["original-transaction-1"],
                [
                    new HostedDataDeletionRecord("InstallationLookup", "installation", "installation-1"),
                    new HostedDataDeletionRecord("Installations", "original-transaction-1", "installation-1")
                ]),
            [new HostedDataDeletionRecord("SubscriptionEntitlements", "appstore", "original-transaction-1")],
            [
                new HostedDataDeletionRecord("SyncAttempts", "hosted-user-id", "sync-1"),
                new HostedDataDeletionRecord("RateLimitBuckets", "hosted-user-id:sync-tandem", "2026062207")
            ]);

        public Task<HostedDataDeletionInstallationLinks> FindInstallationLinksAsync(string installationId, CancellationToken cancellationToken) =>
            Task.FromResult(installationLinks);

        public Task<IReadOnlyList<HostedDataDeletionRecord>> FindSubscriptionEntitlementRecordsAsync(
            IReadOnlyCollection<string> originalTransactionIds,
            CancellationToken cancellationToken) =>
            Task.FromResult(entitlementRecords);

        public Task<IReadOnlyList<HostedDataDeletionRecord>> FindHostedUserRecordsAsync(
            IReadOnlyCollection<UserId> hostedUserIds,
            CancellationToken cancellationToken) =>
            Task.FromResult(hostedUserRecords);

        public Task DeleteRecordsAsync(IReadOnlyCollection<HostedDataDeletionRecord> records, CancellationToken cancellationToken)
        {
            DeletedRecords.AddRange(records);
            return Task.CompletedTask;
        }

        public Task RecordAuditEventAsync(HostedDataDeletionAuditEvent auditEvent, CancellationToken cancellationToken)
        {
            AuditEvents.Add(auditEvent);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeAuditHasher : IDataDeletionAuditHasher
    {
        public string HashInstallationId(string installationId) => "audit-hash";
    }

    private sealed class FixedClock : IClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.Parse("2026-06-22T07:00:00Z");
    }
}
