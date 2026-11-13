// Model-free migration check. Run with: dart scripts/verify_emotion_consent.dart
import '../mobile_application/lib/core/models/consent.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

ConsentEvent grant(ConsentKey key, String version) => ConsentEvent(
  key: key.key,
  status: ConsentStatus.granted,
  textVersion: version,
  occurredAt: DateTime.utc(2026, 11, 13),
);

void main() {
  final legacy = ConsentLedger([
    grant(ConsentKey.emotionEstimate, '1.0'),
    grant(ConsentKey.faceFeatures, '1.0'),
    grant(ConsentKey.usageFootprint, '1.0'),
  ]);
  for (final key in [ConsentKey.emotionEstimate, ConsentKey.faceFeatures]) {
    require(legacy.statusOf(key) == ConsentStatus.needsReconsent,
        'Earlier emotion disclosures must require a fresh agreement.');
    require(!legacy.isGranted(key), 'Earlier emotion grants must fail closed.');
  }
  require(legacy.isGranted(ConsentKey.usageFootprint),
      'Unchanged phone-pattern consent must remain valid.');
  final audioOnly = legacy.record(
    grant(ConsentKey.emotionEstimate, ConsentKey.emotionEstimate.currentVersion),
  );
  require(audioOnly.isGranted(ConsentKey.emotionEstimate),
      'Agreeing to the new emotion disclosure must enable that scope.');
  require(!audioOnly.isGranted(ConsentKey.faceFeatures),
      'Emotion re-consent must not silently renew face consent.');
  final both = audioOnly.record(
    grant(ConsentKey.faceFeatures, ConsentKey.faceFeatures.currentVersion),
  );
  require(both.isGranted(ConsentKey.faceFeatures),
      'Face scope requires both current agreements.');
  final faceOnly = ConsentLedger([
    grant(ConsentKey.faceFeatures, ConsentKey.faceFeatures.currentVersion),
  ]);
  require(!faceOnly.isGranted(ConsentKey.faceFeatures),
      'Face consent must not bypass its parent.');
  final reopened = ConsentLedger.fromMap(both.toMap());
  require(reopened.isGranted(ConsentKey.faceFeatures),
      'Reopening the ledger must preserve current agreements.');
  print('Emotion consent migration checks passed.');
}
