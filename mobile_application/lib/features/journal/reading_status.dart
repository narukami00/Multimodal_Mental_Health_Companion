import '../../core/models/consent.dart';
import '../../services/journal_analysis_client.dart';
import '../checkin/check_in_mode_page.dart';

/// Why an emotion reading could not be made, as far as the app can tell.
enum ReadingStatus {
  /// Nothing stands in the way: a reading that still failed was a one-off.
  ready,

  /// The person has not agreed to emotion reading.
  needsConsent,

  /// The companion server cannot be reached.
  serverAway,

  /// The server is connected, but emotion reading is switched off on it.
  emotionOff,

  /// The server is connected, but its emotion service is not answering (still starting, or not running).
  emotionNotAnswering,
}

/// Works out [ReadingStatus] with a look at consent and at the server's own health report, so a message can say what is
/// actually wrong instead of guessing ("the server isn't reachable, or reading isn't switched on").
Future<ReadingStatus> readingStatus({JournalAnalysisClient? client, bool? consentGranted}) async {
  final granted = consentGranted ?? CheckInModePage.consent?.isGranted(ConsentKey.emotionEstimate) ?? true;
  if (!granted) return ReadingStatus.needsConsent;
  final state = await (client ?? JournalAnalysisClient()).emotionState();
  return switch (state) {
    null => ReadingStatus.serverAway,
    'off' => ReadingStatus.emotionOff,
    'unavailable' => ReadingStatus.emotionNotAnswering,
    _ => ReadingStatus.ready, // "ready", or an older server that does not say
  };
}

/// One calm sentence for the person, for a reading that did not happen.
String explainReadingStatus(ReadingStatus status) => switch (status) {
      ReadingStatus.needsConsent => 'Reading how you feel needs your OK first. You can give it any time in Permissions & privacy.',
      ReadingStatus.serverAway => "Your companion server isn't reachable right now. Nothing is lost; try again when it's back.",
      ReadingStatus.emotionOff => 'Your companion server is connected, but emotion reading is switched off on it.',
      ReadingStatus.emotionNotAnswering =>
        "Your companion server is connected, but its emotion reading isn't answering yet. It may still be starting; try again in a minute.",
      ReadingStatus.ready => "The reading didn't work this time. Try again in a moment.",
    };

/// [readingStatus] and [explainReadingStatus] in one step.
Future<String> explainNoReading({JournalAnalysisClient? client, bool? consentGranted}) async =>
    explainReadingStatus(await readingStatus(client: client, consentGranted: consentGranted));
