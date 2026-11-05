# Reviewer-access inquiry

Prepared November 5, 2026. **Draft only: not sent; no Apple approval or case number exists.**

Canonical process: [App Review access plan](https://github.com/eslutz/PumpSync/wiki/App-Review-Access-Plan).

## Proposed message to Apple

Please route this pre-submission reviewer-access request to App Review. We request prior approval under guideline 2.1(a) for an integrated demonstration arrangement for PumpSync 1.0.0, bundle ID `dev.ericslutz.PumpSync`, Apple ID `6781908162`, on iPhone and iPad.

The normal app imports a user's Tandem insulin delivery and carbohydrate records into Apple Health with permission. Providing a personal pump account would expose sensitive credentials and medical records. PumpSync does not diagnose, treat, control the pump, or recommend dosing.

Before implementing a replacement demonstration mode, we propose using ordinary setup, connection, account, insulin-concentration, sync/progress/recovery, and diagnostics screens with isolated demonstration data. Demonstration data would never be written to HealthKit or represented as actual Health imports. Any simulated result would be clearly identified and could not update the real import ledger or watermark. The dedicated former Sample Preview was removed; no replacement demonstration mode is currently implemented or approved.

We can prepare a privacy-scrubbed physical-iPhone video showing legitimate pump records importing into Apple Health and repeat-sync duplicate prevention. This evidence would supplement the arrangement, not be assumed to replace full review access. Normal sandbox subscription purchase and restore would remain available without a hidden entitlement bypass. Automatic and iOS-granted background sync require separate physical-device evidence.

Please confirm whether the proposed arrangement is acceptable under 2.1(a), what additional hands-on access or evidence is needed for actual HealthKit imports and background execution, and whether the same arrangement can support initial external TestFlight review and the first App Store submission. Please provide a written decision and its scope or conditions before we implement or submit the replacement mode. No personal credentials or health records are included in this request.

## Evidence coverage

| Boundary | Evidence available or required |
| --- | --- |
| Current screen layout | Refreshed iPhone/iPad screenshot fixtures captured November 5; these are presentation evidence only. |
| Normal connection/setup | Real-device walkthrough and working authorized account access, or Apple's agreed demonstration arrangement. |
| Subscription | Actual sandbox purchase, cancellation, restore, expiration, renewal, and release-binary routing evidence still required. |
| Device authentication | Physical-device App Attest enrollment and renewable-session acceptance still required. |
| Actual Health imports | Privacy-scrubbed video and device results using legitimate pump data; no synthetic Health writes. |
| Duplicate prevention | A repeated legitimate import with source, units, dates, and counts checked in Apple Health. |
| Background sync | Natural iOS-granted execution, renewal, and backend correlation evidence; foreground simulation is insufficient. |
| Demonstration isolation | Replacement not implemented. If approved, tests must prove it cannot write Health samples or alter real import state. |

## Contact preparation

The signed-in [App Review contact form](https://developer.apple.com/contact/app-store/) was filled with this draft on November 5, without clicking Send. The available general App Store Connect topic asks for routing to App Review; the form has no dedicated prior-demonstration-approval topic. A filled browser form is not a durable submitted support case. Preserve this file as the source if the form expires.
