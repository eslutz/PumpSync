namespace PumpSync.ApiContracts;

public sealed record ErrorResponse(
    string Code,
    string Message,
    string CorrelationId);
