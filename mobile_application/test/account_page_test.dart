import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/account/account_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/services/account_service.dart';
import 'support/account_fakes.dart';

void main() {
  late FakeAccountBackend backend;
  late AccountService account;
  late ProfileController profile;
  setUp(() async {
    backend = FakeAccountBackend();
    account = AccountService(
      backend: backend,
      ownership: MemoryAccountOwnership(),
    );
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
  });
  tearDown(() async {
    account.dispose();
    profile.dispose();
    await backend.events.close();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AccountPage(profile: profile, service: account),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'offline continuation remains available when auth configuration is unavailable',
    (tester) async {
      backend.unavailable = true;
      await open(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-offline')),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(find.byKey(const ValueKey('account-offline')));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(profile.profile.displayName, isNull);
      expect(account.identity, isNull);
    },
  );
  testWidgets(
    'Google suggests editable name and saves local profile only when confirmed',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('account-google')));
      await tester.pumpAndSettle();
      expect(profile.profile.displayName, isNull);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('account-display-name')),
            )
            .controller
            ?.text,
        'Google Name',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-display-name')),
        'My nickname',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-save-profile')),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(find.byKey(const ValueKey('account-save-profile')));
      await tester.pumpAndSettle();
      expect(profile.profile.displayName, 'My nickname');
      expect(find.text('Open'), findsOneWidget);
    },
  );
  testWidgets('sign-in does not replace a previously chosen local name', (
    tester,
  ) async {
    await profile.saveIdentity(displayName: 'My existing name');
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('account-google')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('account-display-name')))
          .controller
          ?.text,
      'My existing name',
    );
    expect(profile.profile.displayName, 'My existing name');
  });

  testWidgets('delete account prompts for re-auth when required and clears account', (
    tester,
  ) async {
    backend.requireRecentLogin = true;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('account-google')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-delete')),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-reauth-google')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-reauth-google')));
    await tester.pumpAndSettle();
    expect(backend.reauths, 1);
    expect(backend.deletes, 1);
    expect(account.identity, isNull);
  });
}
