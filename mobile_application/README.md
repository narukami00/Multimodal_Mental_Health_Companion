# solace_mobile

Solace is a Flutter self-care app with a local journal, reflection tools, a growing forest, and optional online companion features.

## Local use

Install the dependencies with `flutter pub get`, then run on Android with `flutter run`.
Local onboarding, check-ins and history do not require a Firebase account or a reachable companion server.
Voice transcription requires the optional downloaded model for offline operation.

## Optional online accounts

Email/password and Google authentication use Firebase Authentication. An account identifies requests to the companion server; it does not synchronize, upload or restore the device's history.

For Android, register `com.sysmentalhealth.solace_mobile` in your Firebase project, enable Email/Password and Google providers, add the signing certificate SHA fingerprints, and put the downloaded `google-services.json` in `android/app/`. Apply the Google Services Gradle plugin when that file is present. The app initializes Firebase after the local interface is launched; unavailable configuration or authentication does not block local use.

The optional account page is available during the name/profile onboarding step and from the profile. Google may suggest a name and photo; the person can edit these before saving. Email signup leaves both optional. Existing local identity choices are preserved.

A device remembers the first explicitly accepted account UID. Signing out keeps local data and the binding. Signing in with a different UID is refused so one person's history cannot silently become another account's data. To change ownership, save a copy if desired and explicitly erase local app data first. Backups do not contain the device-account binding or authentication tokens. This is not support for multiple local profiles.

Firebase manages credential persistence. Never put passwords, ID tokens, service account keys or token values in app preferences, logs, screenshots, source or backups. Backend credentials belong only on the server. The app supplies refreshed Firebase ID tokens to protected APIs; authentication failures leave the local journal available.

## Local encryption, mood review, and data lifecycle

- **At-rest encryption & backup exclusion**: Sensitive repositories (journal sessions, safety events, consent ledger, user profile, therapist contact, memory moments, chat conversations) and queued offline recordings (`.pcm.enc` / `.face.enc`) are encrypted at rest via `AndroidKeystoreCipher` (`AES/GCM/NoPadding`, 256-bit key in `AndroidKeyStore`, atomic `.tmp` write-readback-rename) and excluded from Android Auto Backup and device-to-device transfers (`backup_rules.xml`, `data_extraction_rules.xml`).
- **Offline queue & consent**: Pending recordings recheck both emotion and face consents independently at upload time; revoking face consent deletes pending `.face` vectors before upload. Orphaned and expired (>14 days) pending recordings are reconciled automatically.
- **Mood confirmation & trajectory review**: Journal reading cards preserve model abstention and let the person confirm or correct *How I felt then* (stored separately from model estimates). Chat conversations record independent shift-fit and proposed-context agreement statistics without mutating model scores.
- **Deletion & local-only TTS**: Erasing app data clears encrypted stores, avatars, pending recordings, and cancels all scheduled local notifications (`CheckInReminderService.cancelAllNotifications`). Chat/call voice configuration sends `tts.local_only` (default `true`) so speech synthesis does not silently fall back to cloud TTS.

## Checks

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
The account tests use fake provider and ownership boundaries. Native Google sign-in, email delivery, Firebase project configuration (`android/app/google-services.json`), and signing fingerprints require a live Firebase project and device verification; unit tests cannot verify them.
