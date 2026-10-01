import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_consent_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';

void main() {
  late InMemoryConsentRepository repository;
  late ConsentController controller;
  var now = DateTime(2026, 10, 2, 9);

  setUp(() async {
    now = DateTime(2026, 10, 2, 9);
    repository = InMemoryConsentRepository();
    controller = ConsentController(repository: repository, clock: () => now);
    await controller.load();
  });

  group('ConsentKey', () {
    test('uses the CONSENT.md key format', () {
      expect(
        ConsentKey.usageFootprint.key,
        'usageFootprint:metadata:localInsights',
      );
      expect(
        ConsentKey.profileSnippet.key,
        'profileSnippet:text:chatCompanion',
      );
    });

    test('keys resolve back from their string', () {
      for (final key in ConsentKey.all) {
        expect(ConsentKey.fromKey(key.key), same(key));
      }
      expect(ConsentKey.fromKey('nope:text:none'), isNull);
    });
  });

  group('ConsentController', () {
    test('everything is denied until granted, including before load', () async {
      final fresh = ConsentController(repository: repository);

      for (final key in ConsentKey.all) {
        expect(fresh.isGranted(key), isFalse);
        expect(fresh.statusOf(key), ConsentStatus.notAsked);
        expect(controller.isGranted(key), isFalse);
      }
    });

    test('granting allows only that key', () async {
      await controller.grant(ConsentKey.usageFootprint);

      expect(controller.isGranted(ConsentKey.usageFootprint), isTrue);
      expect(controller.isGranted(ConsentKey.profileSnippet), isFalse);
      expect(
        controller.statusOf(ConsentKey.usageFootprint),
        ConsentStatus.granted,
      );
    });

    test('declining is a completed choice, not a grant', () async {
      await controller.decline(ConsentKey.profileSnippet);

      expect(controller.isGranted(ConsentKey.profileSnippet), isFalse);
      expect(
        controller.statusOf(ConsentKey.profileSnippet),
        ConsentStatus.declined,
      );
    });

    test('revoking stops the grant and is remembered', () async {
      await controller.grant(ConsentKey.usageFootprint);
      await controller.revoke(ConsentKey.usageFootprint);

      expect(controller.isGranted(ConsentKey.usageFootprint), isFalse);
      expect(
        controller.statusOf(ConsentKey.usageFootprint),
        ConsentStatus.revoked,
      );
    });

    test('revoking something never granted does not invent a revocation', () async {
      await controller.revoke(ConsentKey.profileSnippet);

      expect(
        controller.statusOf(ConsentKey.profileSnippet),
        ConsentStatus.notAsked,
      );
      expect(controller.history, isEmpty);
    });

    test('a granted key can be granted again after revocation', () async {
      await controller.grant(ConsentKey.usageFootprint);
      await controller.revoke(ConsentKey.usageFootprint);
      await controller.grant(ConsentKey.usageFootprint);

      expect(controller.isGranted(ConsentKey.usageFootprint), isTrue);
      expect(controller.history.map((e) => e.status), [
        ConsentStatus.granted,
        ConsentStatus.revoked,
        ConsentStatus.granted,
      ]);
    });

    test('a sub-grant only counts while its parent is granted', () async {
      await controller.grant(ConsentKey.topAppNames);
      expect(controller.isGranted(ConsentKey.topAppNames), isFalse);

      await controller.grant(ConsentKey.usageFootprint);
      expect(controller.isGranted(ConsentKey.topAppNames), isTrue);

      await controller.revoke(ConsentKey.usageFootprint);
      expect(controller.isGranted(ConsentKey.topAppNames), isFalse);
    });

    test('history records when each decision was made and on which text', () async {
      await controller.grant(ConsentKey.profileSnippet);
      now = DateTime(2026, 10, 3, 18, 30);
      await controller.revoke(ConsentKey.profileSnippet);

      final events = controller.history;
      expect(events, hasLength(2));
      expect(events.first.occurredAt, DateTime(2026, 10, 2, 9));
      expect(events.last.occurredAt, DateTime(2026, 10, 3, 18, 30));
      expect(events.first.textVersion, ConsentKey.profileSnippet.currentVersion);
    });

    test('listeners hear about each decision', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.grant(ConsentKey.usageFootprint);
      await controller.decline(ConsentKey.profileSnippet);

      expect(notifications, 2);
    });
  });

  group('ConsentLedger', () {
    test('a grant on an older major version needs re-consent and fails closed', () {
      final ledger = ConsentLedger([
        ConsentEvent(
          key: ConsentKey.usageFootprint.key,
          status: ConsentStatus.granted,
          textVersion: '0.9',
          occurredAt: DateTime(2026, 9, 1),
        ),
      ]);

      expect(
        ledger.statusOf(ConsentKey.usageFootprint),
        ConsentStatus.needsReconsent,
      );
      expect(ledger.isGranted(ConsentKey.usageFootprint), isFalse);
    });

    test('a newer minor version does not need re-consent', () {
      final ledger = ConsentLedger([
        ConsentEvent(
          key: ConsentKey.usageFootprint.key,
          status: ConsentStatus.granted,
          textVersion: '1.0',
          occurredAt: DateTime(2026, 9, 1),
        ),
      ]);

      expect(ledger.isGranted(ConsentKey.usageFootprint), isTrue);
    });

    test('unreadable or unknown events are dropped, never read as a grant', () {
      final ledger = ConsentLedger.fromMap({
        'events': [
          'junk',
          {'key': 'x', 'occurredAt': 'not a date'},
          {
            'key': ConsentKey.usageFootprint.key,
            'status': 'granted',
            'textVersion': '1.0',
            'occurredAt': '2026-10-01T08:00:00.000',
          },
          {
            'key': ConsentKey.profileSnippet.key,
            'status': 'something-new',
            'occurredAt': '2026-10-01T08:00:00.000',
          },
        ],
      });

      expect(ledger.events, hasLength(2));
      expect(ledger.isGranted(ConsentKey.usageFootprint), isTrue);
      // An unrecognised status degrades to declined, not granted.
      expect(ledger.isGranted(ConsentKey.profileSnippet), isFalse);
    });
  });

  group('SharedPreferencesConsentRepository', () {
    test('round-trips the ledger', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final saved = ConsentController(
        repository: SharedPreferencesConsentRepository(preferences),
        clock: () => now,
      );
      await saved.load();
      await saved.grant(ConsentKey.usageFootprint);
      await saved.decline(ConsentKey.profileSnippet);

      final reopened = ConsentController(
        repository: SharedPreferencesConsentRepository(preferences),
      );
      await reopened.load();

      expect(reopened.isGranted(ConsentKey.usageFootprint), isTrue);
      expect(
        reopened.statusOf(ConsentKey.profileSnippet),
        ConsentStatus.declined,
      );
      expect(reopened.history, hasLength(2));
    });

    test('a corrupted ledger fails closed instead of blocking startup', () async {
      SharedPreferences.setMockInitialValues({'consent.ledger': '{not json'});
      final preferences = await SharedPreferences.getInstance();
      final controller = ConsentController(
        repository: SharedPreferencesConsentRepository(preferences),
      );

      await controller.load();

      expect(controller.isLoaded, isTrue);
      for (final key in ConsentKey.all) {
        expect(controller.isGranted(key), isFalse);
      }
    });
  });
}
