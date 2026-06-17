namespace PumpSync.Domain.Users;

public readonly record struct UserId(Guid Value)
{
    public static UserId New() => new(Guid.CreateVersion7());

    public override string ToString() => Value.ToString("N");
}
