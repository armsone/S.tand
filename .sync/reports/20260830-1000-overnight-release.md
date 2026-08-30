# S.tand 2.4.0 overnight monitoring sync report

- Product version: `2.4.0`
- Common build: `202608301000`
- Apple internal build: `202608301000`
- Android versionCode: `347640`

## Contract result

Apple and Android now share the `mate_mode.overnight_reliability_and_status` contract:

- background monitoring defaults on with a one-time existing-install migration;
- automatic mode becomes Mate before the app loses foreground execution rights;
- eligible microphone monitoring and the same sleep session continue across screen lock/background;
- home/notification status is derived from real microphone state;
- a monitored quiet night is distinct from an unmonitored or failed session.

## Verification

- Apple: 233 `STandTests` passed on one iPhone 17 Pro simulator destination.
- Android: `testDebugUnitTest`, `assembleDebug`, and `lintDebug` passed.
- Android devices: final `2.4.0` APK installed without clearing data on `SM-F956N` Fold and `SM-F968N` TriFold. After screen-off, both reported an active microphone foreground service and running `RECORD_AUDIO` app-op.
- The Android paired-device trace is recorded at `.parity/evidence/2026-08-30/mate-overnight-device-trace.md` in the Android repository.

## Intentional platform adaptation

- Apple uses `UIBackgroundModes=audio` and `AVAudioSession` recording.
- Android uses a microphone foreground service, ongoing low-importance notification, and a service-scoped partial wake lock.
- Google TV remains Object-only and does not enter this contract.
