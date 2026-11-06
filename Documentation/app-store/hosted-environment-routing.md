# Hosted subscription environment routing

Purchase, restore, entitlement recovery, and transaction updates carry a typed entitlement containing the signed transaction and StoreKit-verified transaction environment. Unverified, inactive, unrelated-product, and local Xcode transactions cannot create a hosted entitlement in shipping builds. The signed transaction remains the existing server request field; no backend wire change is required.

Sandbox transactions use the fixed `SANDBOX_API_BASE_URL`; production transactions use `PRODUCTION_API_BASE_URL`. These are bundled HTTPS configuration, never transaction-provided destinations. Build configuration selects the initial environment only. A verified environment selection is persisted independently of the build so an App Review sandbox purchase in a Release archive continues to recover against nonproduction after relaunch.

Before switching destinations, authentication drains the previous renewable refresh, acquires the mutation lease, invalidates durable authentication, and updates the backend configuration revision. Session and pending operation identities include the backend binding; import snapshots include backend identity and configuration revision. Stale work cannot grant credentials or import authorization for the replacement backend. Failure to invalidate blocks enrollment.

Background recovery uses the persisted route and bound session without requiring interactive StoreKit synchronization. Missing or unrecognized route state requires foreground recovery; it cannot migrate an unbound legacy hosted session silently. A foreground owner that ends while waiting cannot authorize a route switch. Self-hosted routing remains independent.

Both servers retain strict signed-transaction, bundle/product, subscription-status, and environment verification. Production must reject sandbox transactions. Client routing is not server authorization.

Simulator tests establish client contracts only. Production readiness, Apple sandbox purchases, real App Attest, physical Health imports, and natural background execution remain independent release gates. See `release-status-2026-11-05.md` for current evidence and blockers.
