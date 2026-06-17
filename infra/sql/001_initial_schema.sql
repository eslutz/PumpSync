CREATE TABLE dbo.Users
(
    UserId uniqueidentifier NOT NULL PRIMARY KEY,
    AppleSubject nvarchar(255) NOT NULL UNIQUE,
    Email nvarchar(320) NULL,
    EmailVerified bit NOT NULL CONSTRAINT DF_Users_EmailVerified DEFAULT 0,
    Status nvarchar(32) NOT NULL,
    CreatedAt datetimeoffset NOT NULL,
    UpdatedAt datetimeoffset NOT NULL
);

CREATE TABLE dbo.BillingEntitlements
(
    BillingEntitlementId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserId uniqueidentifier NOT NULL,
    OriginalTransactionId nvarchar(128) NOT NULL,
    ProductId nvarchar(128) NOT NULL,
    Status nvarchar(32) NOT NULL,
    ExpiresAt datetimeoffset NULL,
    UpdatedAt datetimeoffset NOT NULL,
    CONSTRAINT FK_BillingEntitlements_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
);
CREATE INDEX IX_BillingEntitlements_User_Status ON dbo.BillingEntitlements(UserId, Status, ExpiresAt);

CREATE TABLE dbo.SyncJobs
(
    JobId uniqueidentifier NOT NULL PRIMARY KEY,
    UserId uniqueidentifier NOT NULL,
    DeviceId nvarchar(128) NULL,
    RequestedAt datetimeoffset NOT NULL,
    CompletedAt datetimeoffset NULL,
    Status nvarchar(32) NOT NULL,
    LastError nvarchar(256) NULL,
    CONSTRAINT FK_SyncJobs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
);
CREATE INDEX IX_SyncJobs_User_Status ON dbo.SyncJobs(UserId, Status, RequestedAt DESC);

CREATE TABLE dbo.IdempotencyRequests
(
    UserId uniqueidentifier NOT NULL,
    Endpoint nvarchar(128) NOT NULL,
    IdempotencyKey nvarchar(128) NOT NULL,
    RequestHash char(64) NOT NULL,
    ResponseJson nvarchar(max) NOT NULL,
    ExpiresAt datetimeoffset NOT NULL,
    CreatedAt datetimeoffset NOT NULL,
    CONSTRAINT PK_IdempotencyRequests PRIMARY KEY (UserId, Endpoint, IdempotencyKey),
    CONSTRAINT FK_IdempotencyRequests_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
);
CREATE INDEX IX_IdempotencyRequests_ExpiresAt ON dbo.IdempotencyRequests(ExpiresAt);

CREATE TABLE dbo.RateLimitEvents
(
    RateLimitEventId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserId uniqueidentifier NOT NULL,
    Operation nvarchar(128) NOT NULL,
    OccurredAt datetimeoffset NOT NULL,
    CONSTRAINT FK_RateLimitEvents_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
);
CREATE INDEX IX_RateLimitEvents_User_Operation_Time ON dbo.RateLimitEvents(UserId, Operation, OccurredAt);

CREATE TABLE dbo.AuditEvents
(
    AuditEventId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserId uniqueidentifier NULL,
    EventType nvarchar(128) NOT NULL,
    CorrelationId nvarchar(128) NULL,
    RedactedMetadataJson nvarchar(max) NULL,
    OccurredAt datetimeoffset NOT NULL
);
