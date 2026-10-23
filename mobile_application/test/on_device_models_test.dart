import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/features/models/on_device_model_widgets.dart';
import 'package:solace_mobile/features/profile/permissions_page.dart';
import 'package:solace_mobile/services/app_permission_service.dart';
import 'package:solace_mobile/services/face_reading_choice.dart';
import 'package:solace_mobile/services/model_pack_store.dart';
import 'package:solace_mobile/services/phone_speech.dart';

/// A model pack that lives in memory: no files, no network.
class _FakePack extends ModelPackStore {
  _FakePack({this.downloadWorks = true, this.failure = ModelDownload.serverAway}) : super(pack: 'fake', files: const ['a.bin'], folderName: 'fake', sizeMegabytes: 153);

  bool present = false;
  bool downloadWorks;
  ModelDownload failure; // why a download that does not work does not work
  int downloads = 0;

  @override
  Future<int?> installedBytes() async => present ? 153 * 1024 * 1024 : null;

  @override
  Future<ModelDownload> downloadResult({void Function(double progress)? onProgress}) async {
    downloads++;
    onProgress?.call(0.5);
    if (downloadWorks) present = true;
    onProgress?.call(1);
    notifyListeners();
    return downloadWorks ? ModelDownload.installed : failure;
  }

  @override
  Future<void> remove() async {
    present = false;
    notifyListeners();
  }
}

class _Perms extends AppPermissionService {
  @override
  Future<bool> notificationsGranted() async => true;
  @override
  Future<bool> microphoneGranted() async => true;
  @override
  Future<bool> cameraGranted() async => true;
}

OnDeviceModelRow _row(_FakePack pack, String prefix, {VoidCallback? onInstalled, VoidCallback? onRemoved}) => OnDeviceModelRow(
      store: pack,
      keyPrefix: prefix,
      icon: Icons.graphic_eq_rounded,
      color: Colors.orange,
      title: 'Title $prefix',
      offer: 'Offer $prefix',
      onText: () => 'It is on: $prefix',
      removeTitle: 'Remove $prefix?',
      removeBody: 'It will be gone from this phone.',
      onInstalled: onInstalled,
      onRemoved: onRemoved,
    );

Widget _panel(List<OnDeviceModelRow> rows) => MaterialApp(home: Scaffold(body: Center(child: OnDeviceModelsPanel(rows: rows))));

void main() {
  tearDown(() => PhoneFace.pipelineReady = true);

  group('the grouped panel on a journal page', () {
    testWidgets('offers each model, downloads on a tap, and says when everything is ready without the server', (tester) async {
      final a = _FakePack();
      await tester.pumpWidget(_panel([_row(a, 'a')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a-card')), findsOneWidget);
      expect(find.text('Offer a'), findsOneWidget);
      expect(find.text('Make this work without the server'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('a-download')));
      await tester.pumpAndSettle();
      expect(a.downloads, 1);
      expect(find.byKey(const ValueKey('a-on')), findsOneWidget);
      expect(find.text('It is on: a'), findsOneWidget);
      expect(find.text('Ready without the server'), findsOneWidget);
    });

    testWidgets('two models share one card, and it is "ready" only when both are on', (tester) async {
      final speech = _FakePack(), face = _FakePack();
      await tester.pumpWidget(_panel([_row(speech, 's'), _row(face, 'f')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('models-panel')), findsOneWidget); // ONE panel for both
      expect(find.byKey(const ValueKey('s-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('f-card')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('s-download')));
      await tester.pumpAndSettle();
      expect(find.text('Make this work without the server'), findsOneWidget); // the camera one is still missing
      await tester.tap(find.byKey(const ValueKey('f-download')));
      await tester.pumpAndSettle();
      expect(find.text('Ready without the server'), findsOneWidget);
    });

    testWidgets('a failed download says so in plain words, keeps the offer, and can be tried again', (tester) async {
      final pack = _FakePack(downloadWorks: false);
      await tester.pumpWidget(_panel([_row(pack, 'a')]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('a-download')));
      await tester.pumpAndSettle();

      final message = tester.widget<Text>(find.byKey(const ValueKey('a-message'))).data!;
      expect(message, contains('companion server'));
      expect(message.toLowerCase(), isNot(contains('exception')));
      expect(find.byKey(const ValueKey('a-download')), findsOneWidget);

      pack.downloadWorks = true;
      await tester.tap(find.byKey(const ValueKey('a-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('a-message')), findsNothing);
    });

    testWidgets('each way a download can fail is explained in its own words', (tester) async {
      const expected = {
        ModelDownload.serverAway: "Couldn't reach your companion server",
        ModelDownload.notOnServer: "doesn't have this set up yet",
        ModelDownload.interrupted: 'The download was interrupted',
        ModelDownload.noSpace: "There isn't enough free space on this phone (about 153 MB are needed)",
      };
      for (final entry in expected.entries) {
        await tester.pumpWidget(_panel([_row(_FakePack(downloadWorks: false, failure: entry.key), 'a')]));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('a-download')));
        await tester.pumpAndSettle();
        final message = tester.widget<Text>(find.byKey(const ValueKey('a-message'))).data!;
        expect(message, contains(entry.value), reason: '${entry.key}');
        expect(message.toLowerCase(), isNot(contains('exception')), reason: '${entry.key}');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('removing asks first, "Keep it" changes nothing, and the install and remove callbacks fire only for real', (tester) async {
      final pack = _FakePack();
      var installed = 0, removed = 0;
      await tester.pumpWidget(_panel([_row(pack, 'a', onInstalled: () => installed++, onRemoved: () => removed++)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('a-download')));
      await tester.pumpAndSettle();
      expect(installed, 1);

      await tester.tap(find.byKey(const ValueKey('a-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-model-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('remove-model-keep')));
      await tester.pumpAndSettle();
      expect(pack.present, isTrue);
      expect(removed, 0);

      await tester.tap(find.byKey(const ValueKey('a-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-model-confirm')));
      await tester.pumpAndSettle();
      expect(pack.present, isFalse);
      expect(removed, 1);
      expect(find.byKey(const ValueKey('a-card')), findsOneWidget); // offered again
    });

    testWidgets('a failed download does not run the install callback', (tester) async {
      var installed = 0;
      await tester.pumpWidget(_panel([_row(_FakePack(downloadWorks: false), 'a', onInstalled: () => installed++)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('a-download')));
      await tester.pumpAndSettle();
      expect(installed, 0);
    });
  });

  group('the choice of where the face is read', () {
    test('is the server until the person chooses the phone, and is remembered', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final choice = FaceReadingChoice(preferences: prefs);
      expect(choice.place, FaceReadingPlace.server);
      await choice.set(FaceReadingPlace.phone);
      expect(FaceReadingChoice(preferences: prefs).place, FaceReadingPlace.phone);
      await choice.set(FaceReadingPlace.server);
      expect(FaceReadingChoice(preferences: prefs).place, FaceReadingPlace.server);
    });

    test('an unknown stored value falls back to the server', () async {
      SharedPreferences.setMockInitialValues({FaceReadingChoice.preferenceKey: 'something-else'});
      expect(FaceReadingChoice(preferences: await SharedPreferences.getInstance()).place, FaceReadingPlace.server);
    });

    testWidgets('the control shows both options and switches on a tap', (tester) async {
      final choice = FaceReadingChoice();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FaceReadingChoiceControl(choice: choice)))));
      expect(find.text('On the companion server'), findsOneWidget);
      expect(find.text('On this phone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('face-place-phone')));
      await tester.pump();
      expect(choice.place, FaceReadingPlace.phone);
      await tester.tap(find.byKey(const ValueKey('face-place-server')));
      await tester.pump();
      expect(choice.place, FaceReadingPlace.server);
    });
  });

  group('Permissions & privacy', () {
    Future<void> openPage(WidgetTester tester, _FakePack speech, _FakePack face, FaceReadingChoice choice) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: PermissionsPage(permissions: _Perms(), speechModels: speech, faceModels: face, faceChoice: choice),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> scrollTo(WidgetTester tester, String key) =>
        tester.scrollUntilVisible(find.byKey(ValueKey(key)), 300, scrollable: find.byType(Scrollable).first);

    testWidgets('lists the speech model with an explanation, its size, and buttons to get and remove it', (tester) async {
      final speech = _FakePack();
      await openPage(tester, speech, _FakePack(), FaceReadingChoice());
      await scrollTo(tester, 'speech-model-model-card');

      expect(find.byKey(const ValueKey('models-intro')), findsOneWidget);
      expect(find.text('Offline transcription'), findsOneWidget);
      expect(find.textContaining('never from anyone else'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('speech-model-status'))).data, 'Not on this phone');

      await tester.tap(find.byKey(const ValueKey('speech-model-download')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('speech-model-status'))).data, 'On this phone · 153 MB');

      await tester.tap(find.byKey(const ValueKey('speech-model-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-model-confirm')));
      await tester.pumpAndSettle();
      expect(speech.present, isFalse);
      expect(tester.widget<Text>(find.byKey(const ValueKey('speech-model-status'))).data, 'Not on this phone');
    });

    testWidgets('the camera models can be hidden (when a build has no on-phone face reading)', (tester) async {
      PhoneFace.pipelineReady = false;
      await openPage(tester, _FakePack(), _FakePack(), FaceReadingChoice());
      await scrollTo(tester, 'speech-model-model-card');
      expect(find.byKey(const ValueKey('face-model-model-card')), findsNothing);
    });

    testWidgets('the camera models come with the choice of where the face is read, offered only once they are on the phone, and removing them goes back to the server', (tester) async {
      final face = _FakePack();
      final choice = FaceReadingChoice();
      await openPage(tester, _FakePack(), face, choice);
      await scrollTo(tester, 'face-model-model-card');
      expect(find.text('Camera models'), findsOneWidget);
      expect(find.text('Where should your face be read?'), findsNothing); // not before the models are there

      await tester.tap(find.byKey(const ValueKey('face-model-download')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('face-place-phone')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Where should your face be read?'), findsOneWidget);
      expect(choice.place, FaceReadingPlace.server); // downloading in settings changes nothing by itself

      await tester.tap(find.byKey(const ValueKey('face-place-phone')));
      await tester.pump();
      expect(choice.place, FaceReadingPlace.phone);

      await tester.tap(find.byKey(const ValueKey('face-model-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-model-confirm')));
      await tester.pumpAndSettle();
      expect(face.present, isFalse);
      expect(choice.place, FaceReadingPlace.server);
    });
  });
}
