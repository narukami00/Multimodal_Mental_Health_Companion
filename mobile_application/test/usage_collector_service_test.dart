import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/domain/footprint/app_categories.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

const _channelName = 'com.sysmentalhealth.solace_mobile/usage_collector';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(_channelName);
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) handler;

  setUp(() {
    calls = [];
    handler = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final service = MethodChannelUsageCollector(channel: channel);

  group('access', () {
    test('reports what the platform says', () async {
      handler = (_) async => true;
      expect(await service.hasAccess(), isTrue);
      handler = (_) async => false;
      expect(await service.hasAccess(), isFalse);
    });

    test('a platform failure reads as no access, never as granted', () async {
      handler = (_) async => throw PlatformException(code: 'boom');

      expect(await service.hasAccess(), isFalse);
      expect(await service.openAccessSettings(), isFalse);
    });

    test('opens the settings screen', () async {
      handler = (_) async => true;

      expect(await service.openAccessSettings(), isTrue);
      expect(calls.single.method, 'openAccessSettings');
    });
  });

  group('events', () {
    test('sends the window as epoch milliseconds', () async {
      handler = (_) async => <Object?>[];
      final from = DateTime(2026, 10, 1, 6);
      final to = DateTime(2026, 10, 2, 6);

      await service.events(from: from, to: to);

      expect(calls.single.method, 'events');
      expect(calls.single.arguments, {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });
    });

    test('maps platform events and drops the unreadable ones', () async {
      final at = DateTime(2026, 10, 1, 9).millisecondsSinceEpoch;
      handler = (_) async => <Object?>[
        {'time': at, 'type': 'screenOn', 'package': null},
        {'time': at + 1000, 'type': 'appForeground', 'package': 'chat.app'},
        {'time': at + 2000, 'type': 'teleport', 'package': null},
        'junk',
        {'time': 'x', 'type': 'screenOff'},
      ];

      final events = await service.events(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
      );

      expect(events.map((e) => e.type), [
        UsageEventType.screenOn,
        UsageEventType.appForeground,
      ]);
      expect(events.last.package, 'chat.app');
    });

    test('a platform failure is no events, not an exception', () async {
      handler = (_) async => throw PlatformException(code: 'boom');

      final events = await service.events(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
      );

      expect(events, isEmpty);
    });
  });

  group('describeApps', () {
    test('reads descriptions and omits unreadable ones', () async {
      handler = (_) async => <Object?, Object?>{
        'chat.app': {
          'label': 'Chat',
          'category': 'social',
          'ignore': false,
          'visible': true,
        },
        'hidden.app': {
          'label': 'hidden.app',
          'category': null,
          'ignore': false,
          'visible': false,
        },
        'broken': 'nope',
      };

      final described = await service.describeApps([
        'chat.app',
        'hidden.app',
        'broken',
      ]);

      expect(described.keys, ['chat.app', 'hidden.app']);
      expect(described['chat.app']!.category, 'social');
      expect(described['hidden.app']!.visible, isFalse);
    });

    test('asks for nothing when there is nothing to ask', () async {
      expect(await service.describeApps(const []), isEmpty);
      expect(calls, isEmpty);
    });

    test('a platform failure describes nothing', () async {
      handler = (_) async => throw PlatformException(code: 'boom');

      expect(await service.describeApps(['a']), isEmpty);
    });
  });

  group('categoryResolverFor', () {
    final described = {
      'feed.app': const AppDescription(label: 'Feed', category: 'social'),
      'stream.app': const AppDescription(label: 'Stream', category: 'video'),
      'play.app': const AppDescription(label: 'Play', category: 'games'),
      'docs.app': const AppDescription(label: 'Docs', category: 'productivity'),
      'maps.app': const AppDescription(label: 'Maps', category: 'maps'),
      'home.launcher': const AppDescription(label: 'Home', ignore: true),
      'hidden.app': const AppDescription(label: 'hidden.app', visible: false),
      'com.whatsapp': const AppDescription(label: 'Chat', category: 'social'),
    };
    final resolve = categoryResolverFor(described);

    test('uses the platform category for the ones that matter', () {
      expect(resolve('feed.app'), AppCategory.social);
      expect(resolve('stream.app'), AppCategory.video);
      expect(resolve('play.app'), AppCategory.games);
      expect(resolve('docs.app'), AppCategory.productivity);
    });

    test('a messaging app is messaging, even if the platform says social', () {
      expect(resolve('com.whatsapp'), AppCategory.messaging);
      expect(resolve('org.telegram.messenger'), AppCategory.messaging);
    });

    test('well-known feeds and video apps override a missing or generous label', () {
      final labelled = categoryResolverFor({
        'com.instagram.android': const AppDescription(
          label: 'Photos',
          category: 'productivity',
        ),
        'com.google.android.youtube': const AppDescription(label: 'Videos'),
        'com.reddit.frontpage': const AppDescription(label: 'Threads'),
      });

      expect(labelled('com.instagram.android'), AppCategory.social);
      expect(labelled('com.google.android.youtube'), AppCategory.video);
      expect(labelled('com.reddit.frontpage'), AppCategory.social);
    });

    test('an ignored app stays ignored even if it is on a list', () {
      final ignored = categoryResolverFor({
        'com.facebook.katana': const AppDescription(label: 'x', ignore: true),
      });

      expect(ignored('com.facebook.katana'), isNull);
    });

    test('anything not recognised, hidden, or undescribed is other', () {
      expect(resolve('maps.app'), AppCategory.other);
      expect(resolve('hidden.app'), AppCategory.other);
      expect(resolve('never.described'), AppCategory.other);
    });

    test('launchers and system apps stay out of the totals', () {
      expect(resolve('home.launcher'), isNull);
    });

    test('every category it can return is on the fixed list', () {
      for (final package in described.keys) {
        final category = resolve(package);
        if (category != null) expect(AppCategory.all, contains(category));
      }
    });
  });

  test('packagesIn collects each app once and skips events without one', () {
    final at = DateTime(2026, 10, 1);
    final packages = packagesIn([
      UsageEvent(time: at, type: UsageEventType.screenOn),
      UsageEvent(time: at, type: UsageEventType.appForeground, package: 'a'),
      UsageEvent(time: at, type: UsageEventType.appBackground, package: 'a'),
      UsageEvent(time: at, type: UsageEventType.appForeground, package: 'b'),
      UsageEvent(time: at, type: UsageEventType.appForeground, package: ''),
    ]);

    expect(packages, {'a', 'b'});
  });
}
