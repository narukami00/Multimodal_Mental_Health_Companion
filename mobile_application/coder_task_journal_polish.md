# CODER TASK: Polish Journal & Session Detail MaxWidth and Route Support

### 1. In `lib/features/onboarding/onboarding_gate.dart`
Add import:
`import '../journal/session_detail_page.dart';`
Add route check in `build`:
```dart
      if (route == 'session_detail') {
        final session = widget.sessionController.sessions.isNotEmpty
            ? widget.sessionController.sessions.first
            : null;
        if (session != null) {
          return SessionDetailPage(session: session);
        }
      }
```

### 2. In `lib/features/journal/journal_page.dart`
Change `maxWidth: 390` to `maxWidth: 360`.

### 3. In `lib/features/journal/session_detail_page.dart`
Change `maxWidth: 390` to `maxWidth: 360`.

### 4. In `lib/features/checkin/text_check_in_page.dart`
Ensure `maxWidth: 360` on the content container and bottom navigation container so nothing clips on mobile viewports.

Run `flutter test` when done to verify 100% tests pass.
