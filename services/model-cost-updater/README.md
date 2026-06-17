# PumpSync Model Cost Updater Service

This folder contains the scheduled model cost updater.

Keep this service separate from `backend/` because it is operational support code, not part of the product API. It can still share future packages for auth, telemetry, and configuration once those packages exist.

Expected responsibilities:

- refresh model pricing metadata on a schedule;
- write non-user operational configuration;
- emit run metrics and failures;
- avoid any Tandem or HealthKit data path.

Required app settings:

- `ModelCostUpdater__Schedule`, for example `0 0 4 * * *`
- `ModelCostUpdater__CatalogUrl`, optional; the worker is inert when unset
