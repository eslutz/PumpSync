# PumpSync Log Drain Service

This folder contains the deployable log drain endpoint.

Keep this service separate from `backend/` because it is operational support code, not part of the product API. It can still share future packages for auth, telemetry, and configuration once those packages exist.

Expected responsibilities:

- accept provider log webhooks;
- validate webhook authenticity;
- normalize and forward operational logs;
- avoid storing user Tandem credentials or Tandem health data.

Required app settings:

- `LogDrain__SharedSecret`
