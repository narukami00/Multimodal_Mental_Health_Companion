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

## Checks

Run `flutter analyze` and `flutter test test/account_service_test.dart test/account_page_test.dart test/onboarding_flow_test.dart test/profile_controller_settings_test.dart test/data_registry_test.dart`.
The account tests use fake provider and ownership boundaries. Native Google sign-in, email delivery, Firebase project configuration and signing fingerprints also need a device check with the configured project; unit tests cannot verify them.
