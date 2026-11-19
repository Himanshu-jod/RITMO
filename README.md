# RITMO

**Plan. Execute. Improve.**

RITMO is an Android-first, offline personal routine planner built with Flutter, Dart, SQLite and native Android notification/alarm integration.

## Implemented modules

- Premium dark Liquid Glass-inspired dashboard and bottom navigation.
- Daily timeline and weekly schedule.
- Add/edit/delete activities with weekday recurrence and duration.
- SQLite persistence for activities and occurrence history.
- Scheduled local alarms with full-screen-intent notifications where Android permits.
- Alarm notification actions: snooze 5/10/15 minutes; swipe the notification away to dismiss, or mark the activity complete in RITMO.
- Automatic marking of overdue today's activities as missed.
- Smart Routine Recovery: manually select a replacement time, with overlap warning. Recovery changes that activity's recurring time; it does not silently move other activities.
- Functional focus countdown with start, pause, resume, reset and local state restoration after reopening the app.
- Focus session history.
- Seven-day completion analytics and focus-time summary.
- Offline JSON backup export/import for activities, completion history and focus sessions.
- GitHub Actions workflow for analysis, tests and debug APK artifact.

## App identity

- User-facing app name: **RITMO** (ALL CAPS).
- Android launcher label: **RITMO**.
- Downloaded debug APK filename: `RITMO.apk`.
- Internal Flutter package and Android identifiers remain lowercase where required by platform conventions.

## Requirements

- Flutter stable (Dart 3.4+)
- Android Studio / Android SDK
- Android device or emulator (physical-device alarm testing strongly recommended)

## Run locally

```bash
flutter create --platforms=android --org com.ritmo --project-name ritmo .
python3 tool/configure_android.py
flutter pub get
flutter run
```

If Android platform files already exist, do not regenerate them; run `flutter pub get` and `flutter run`.

## Alarm behaviour and limitations

RITMO uses `flutter_local_notifications` with exact scheduling, alarm-category notifications and action buttons. Android may require the user to grant notification and Alarms & reminders access. Full-screen presentation depends on Android version, permission, device policy and full-screen-intent eligibility. Notification sound behaviour is controlled by Android notification channels and device settings; this implementation does not claim a continuously looping foreground alarm tone. Battery restrictions vary by manufacturer. Force-stopping the app from Android Settings can prevent scheduled work until the app is opened again.

The notification plugin's reboot receiver is configured in the generated manifest. Verify delivery, snooze actions, lock-screen presentation, reboot recovery, permission revocation and Doze behaviour on a physical device before relying on it for critical alarms.

## Smart Routine Recovery

When an activity's scheduled end time passes without a completion record, RITMO marks today's occurrence as missed. The user can choose a new time. In this initial implementation, recovering an activity updates its recurring activity time for future repeats too; it does not create a one-off exception or automatically move other activities.

## Focus timer

Focus sessions use a persisted end timestamp and local preferences so the countdown can be reconstructed after app backgrounding or reopening. A paused or active session is restored locally. The app does not promise that the timer will keep the device awake or play an alarm after Android force-stops the app.

## Backup

Settings → Export backup creates a JSON file containing activities, activity history and focus sessions. Settings → Restore backup imports a compatible RITMO JSON backup. Restore replaces the current local data, so keep a copy before importing. No cloud account is used.

## GitHub Actions

Push to `main` or open a pull request. The workflow creates the Android platform scaffold if needed, installs dependencies, runs analysis/tests, builds a debug APK and uploads it as `RITMO-Android-APK`.

## Privacy

No login, backend, analytics SDK or cloud dependency. Activity and focus data remain in app-local storage. Uninstalling the app may remove its local data; export a backup before uninstalling.

## Build verification status

Source changes are prepared, but the Flutter SDK is not available in this authoring environment. The project has not been compiled here. GitHub Actions or a local Flutter installation must run `flutter pub get`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. Alarm delivery and full-screen behaviour must be verified on a physical Android device.
