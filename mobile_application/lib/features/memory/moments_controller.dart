import 'package:flutter/foundation.dart';

import '../../core/day_key.dart';
import '../../core/models/memory_moment.dart';
import '../../data/contracts/moment_repository.dart';
import '../../domain/memory/moment_extractor.dart';

/// The person's moments: proposed by an extractor, kept only on their yes, and
/// always theirs to edit, hide, or delete.
///
/// Nothing here reaches Sol or Insights until it is confirmed.
class MomentsController extends ChangeNotifier {
  MomentsController({
    required MomentRepository repository,
    MomentExtractor extractor = const RuleBasedMomentExtractor(),
    DateTime Function()? clock,
  }) : _repository = repository,
       _extractor = extractor,
       _clock = clock ?? DateTime.now;

  /// At most this many wait for an answer; more would turn a gentle question
  /// into a chore.
  static const maxPending = 3;

  /// A question nobody answered fades away on its own.
  static const pendingLifetime = Duration(days: 14);

  /// What Sol is told is the most recent few, never the whole archive.
  static const maxForSol = 5;

  final MomentRepository _repository;
  final MomentExtractor _extractor;
  final DateTime Function() _clock;

  List<MemoryMoment> _moments = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    _moments = await _repository.loadAll();
    await _expireOld();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _expireOld() async {
    final now = _clock();
    for (final moment in _moments.toList()) {
      if (moment.state == MomentState.pending &&
          now.difference(moment.createdAt) > pendingLifetime) {
        await _repository.delete(moment.id, at: now);
        _moments = [for (final m in _moments) if (m.id != moment.id) m];
      }
    }
  }

  /// Waiting for a yes, newest first.
  List<MemoryMoment> get pending => _of(MomentState.pending);

  /// What the person agreed to keep, newest first.
  List<MemoryMoment> get confirmed => _of(MomentState.confirmed);

  /// Kept but set aside: not used by anything, and still theirs to bring back.
  List<MemoryMoment> get hidden => _of(MomentState.hidden);

  /// Everything, for the "What Sol remembers" list.
  List<MemoryMoment> get all => List.unmodifiable(_moments.reversed);

  /// The warm moments for Insights. Hard ones are never listed there.
  List<MemoryMoment> get forInsights => [
    for (final m in confirmed)
      if (m.tone == MomentTone.warm) m,
  ];

  /// What may be told to Sol: confirmed, most recent first, few and short.
  List<MemoryMoment> get forSol => confirmed.take(maxForSol).toList();

  List<MemoryMoment> _of(MomentState state) => [
    for (final m in _moments.reversed)
      if (m.state == state) m,
  ];

  /// Looks at an entry and, if it holds a moment worth asking about, adds it as
  /// pending. Returns it, or null when there was nothing to ask.
  ///
  /// Skips an entry already looked at, a moment the same as one already known,
  /// and anything sensitive even if an extractor missed it.
  Future<MemoryMoment?> consider(MomentCandidate candidate) async {
    if (candidate.sourceRef != null &&
        _moments.any((m) => m.sourceRef == candidate.sourceRef)) {
      return null;
    }
    if (pending.length >= maxPending) return null;

    final proposal = await _extractor.extract(candidate);
    if (proposal == null || momentIsSensitive(proposal.text)) return null;
    if (_moments.any((m) => _sameThing(m.text, proposal.text))) return null;

    final now = _clock();
    final moment = MemoryMoment(
      id: 'moment_${now.microsecondsSinceEpoch}',
      text: proposal.text,
      createdAt: now,
      occurredOn: proposal.occurredOn,
      source: proposal.source,
      tone: proposal.tone,
      moodWord: proposal.moodWord,
      emotionClass: proposal.emotionClass,
      emotionConfidence: proposal.emotionConfidence,
      sourceRef: proposal.sourceRef,
    );
    await _save(moment);
    return moment;
  }

  /// Adds a moment the person wrote themselves. Theirs to add, so it is kept at
  /// once and is not subject to the topics Sol avoids offering on its own.
  Future<MemoryMoment?> addManual(String text, {MomentTone tone = MomentTone.warm}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final now = _clock();
    final moment = MemoryMoment(
      id: 'moment_${now.microsecondsSinceEpoch}',
      text: trimmed.length > MemoryMoment.maxLength
          ? trimmed.substring(0, MemoryMoment.maxLength)
          : trimmed,
      createdAt: now,
      occurredOn: dayKey(now),
      source: MomentSource.manual,
      state: MomentState.confirmed,
      tone: tone,
      editedByUser: true,
      updatedAt: now,
    );
    await _save(moment);
    return moment;
  }

  /// Yes, remember it. [text] is the person's own edit, if they changed it.
  Future<void> confirm(String id, {String? text}) => _change(id, (m) {
    final edited = text != null && text.trim().isNotEmpty && text.trim() != m.text;
    return m.copyWith(
      state: MomentState.confirmed,
      text: edited ? _cap(text.trim()) : null,
      editedByUser: edited ? true : null,
      updatedAt: _clock(),
    );
  });

  Future<void> edit(String id, String text) => _change(id, (m) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == m.text) return m;
    return m.copyWith(text: _cap(trimmed), editedByUser: true, updatedAt: _clock());
  });

  Future<void> hide(String id) => _change(
    id,
    (m) => m.copyWith(state: MomentState.hidden, updatedAt: _clock()),
  );

  Future<void> unhide(String id) => _change(
    id,
    (m) => m.copyWith(state: MomentState.confirmed, updatedAt: _clock()),
  );

  /// Gone for good, leaving only a tombstone with the id.
  Future<void> delete(String id) async {
    await _repository.delete(id, at: _clock());
    _moments = [for (final m in _moments) if (m.id != id) m];
    notifyListeners();
  }

  /// Gone with the entry they came from.
  Future<void> deleteForSource(String sourceRef) async {
    final ids = [
      for (final m in _moments)
        if (m.sourceRef == sourceRef) m.id,
    ];
    for (final id in ids) {
      await _repository.delete(id, at: _clock());
    }
    if (ids.isNotEmpty) {
      _moments = [for (final m in _moments) if (!ids.contains(m.id)) m];
      notifyListeners();
    }
  }

  Future<void> deleteAll() async {
    await _repository.deleteAll();
    _moments = const [];
    notifyListeners();
  }

  Future<void> _save(MemoryMoment moment) async {
    await _repository.save(moment);
    _moments = [..._moments.where((m) => m.id != moment.id), moment];
    notifyListeners();
  }

  Future<void> _change(String id, MemoryMoment Function(MemoryMoment) change) async {
    final current = _moments.where((m) => m.id == id).firstOrNull;
    if (current == null) return;
    final next = change(current);
    if (identical(next, current)) return;
    await _save(next);
  }

  static String _cap(String text) => text.length > MemoryMoment.maxLength
      ? text.substring(0, MemoryMoment.maxLength)
      : text;

  static String _normal(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _sameThing(String a, String b) => _normal(a) == _normal(b);
}
