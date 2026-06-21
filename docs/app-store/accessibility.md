# App Store Accessibility Support

PumpSync should claim the following App Store accessibility labels once the manual validation checklist below passes on both iPhone and iPad:

- VoiceOver
- Voice Control
- Larger Text
- Dark Interface
- Differentiate Without Color Alone
- Sufficient Contrast
- Reduced Motion

PumpSync should not claim Captions or Audio Descriptions because the app does not use audio or video media as part of its common tasks.

## Common Task Matrix

Validate each claimed feature against these common tasks on iPhone compact tab layout and iPad regular split-view layout:

- First launch and status: launch the app, understand connection state, pump credential state, last sync state, and switch between Status, Sync, and Settings.
- Hosted connection: choose PumpSync mode, read hosted service copy, open the subscription sheet, review benefits, subscribe or cancel, and restore a subscription.
- Self-hosted connection: switch to Self-hosted, enter a server URL, connect, and disconnect.
- Pump account: enter username and password, toggle password visibility, choose region, validate connection, save credentials, and remove credentials.
- Health access: review write permission status and understand instructions for changing Health permissions.
- Sync: choose the initial history range, understand readiness blockers, start initial or manual sync, and review last sync status.
- Settings and support: open Data Handling and Developer, review diagnostics, copy summaries, share a support bundle, and clear diagnostics.

## Manual Validation

Use current iOS and iPadOS simulators or devices, and repeat on a physical iPhone before release.

- VoiceOver: complete the full common task matrix and confirm reading order, labels, values, hints, selected states, and actions are understandable.
- Voice Control: complete the full common task matrix using voice only. Use visible control names where possible and "Show numbers" for dense forms.
- Larger Text: test normal, large, and the largest accessibility Dynamic Type sizes. Confirm meaningful text wraps, rows grow vertically, and key controls remain tappable.
- Dark Interface: test light and dark appearances. Confirm all controls and text remain legible.
- Differentiate Without Color Alone: test with grayscale or color filters. Confirm all status meanings are conveyed with text and icon shape, not color alone.
- Sufficient Contrast: test with Increase Contrast, Bold Text, and Reduce Transparency. Confirm secondary text, disabled states, cards, and buttons remain readable.
- Reduced Motion: enable Reduce Motion and confirm no required task depends on animation. Progress states should remain understandable without indefinite motion.

## Automated Coverage

The UI test suite includes screenshot-fixture navigation checks for:

- Unique Developer diagnostics action names.
- Largest accessibility Dynamic Type on iPhone.
- Dark-mode rendering on iPhone.
- iPad-specific screenshot/navigation coverage.

These tests are a guardrail only. App Store accessibility labels still require manual validation that users can complete the common tasks with each claimed feature.
