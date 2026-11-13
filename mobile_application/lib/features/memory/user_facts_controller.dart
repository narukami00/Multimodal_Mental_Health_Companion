import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user_fact.dart';
export '../../core/models/user_fact.dart' show UserFact, UserFactExtractionResult;
import '../../domain/memory/moment_extractor.dart';
import '../../services/secure_storage.dart';

typedef UserFactExtractor = Future<UserFactExtractionResult?> Function(
  List<Map<String, String>> turns,
  List<String> existingFacts,
);

/// Manages durable non-clinical user facts and the compiled identity summary
/// stored locally in encrypted device storage.
class UserFactsController extends ChangeNotifier {
  UserFactsController({
    SharedPreferences? preferences,
    SecureKeyValueStore? secureStore,
    DateTime Function()? clock,
    this.extractor,
  })  : _prefs = preferences,
        _secureStore = secureStore,
        _clock = clock ?? DateTime.now;

  static const String storageKeyFacts = 'memory.userFacts';
  static const String storageKeySummary = 'memory.identitySummary';
  static const String storageKeyScanned = 'memory.factScannedTurns';

  static const int maxFacts = 50;
  static const int maxIdentitySummaryChars = 240;

  SharedPreferences? _prefs;
  final SecureKeyValueStore? _secureStore;
  final DateTime Function() _clock;
  UserFactExtractor? extractor;

  final List<UserFact> _facts = [];
  String _identitySummary = '';
  final Map<String, int> _scannedTurns = {};
  final Set<String> _inFlight = {};
  bool _isLoaded = false;
  int _idCounter = 0;

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _facts.isEmpty && _identitySummary.isEmpty;
  String get identitySummary => _identitySummary;

  /// Pinned facts first, then newest updated first.
  List<UserFact> get facts {
    final sorted = List<UserFact>.from(_facts)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(sorted);
  }

  /// Counts how many facts are pinned (used as `pinned_count` / ordering aid).
  int get pinnedCount => _facts.where((f) => f.pinned).length;

  /// Ordered fact texts matching [facts] (pinned first, then newest).
  List<String> factLines({int? maxCount}) {
    final list = [for (final f in facts) f.text];
    if (maxCount != null && list.length > maxCount) {
      return list.sublist(0, maxCount);
    }
    return list;
  }

  /// Parallel `[0.15, 1.0]` recency weights aligned with [factLines].
  List<double> factRecencyScores({int? maxCount}) {
    final now = _clock();
    final scores = [for (final f in facts) f.recencyScore(now)];
    if (maxCount != null && scores.length > maxCount) {
      return scores.sublist(0, maxCount);
    }
    return scores;
  }

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();

    final rawFacts = await _readString(storageKeyFacts);
    _facts.clear();
    if (rawFacts != null && rawFacts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFacts);
        if (decoded is List) {
          for (final item in decoded.whereType<Map<String, dynamic>>()) {
            final parsed = UserFact.fromMap(item);
            if (parsed.text.isNotEmpty && !momentIsSensitive(parsed.text)) {
              _facts.add(parsed);
            }
          }
        }
      } catch (e) {
        debugPrint('[UserFacts] Could not decode stored facts: $e');
      }
    }

    final rawSummary = await _readString(storageKeySummary);
    final cleanSummary = _cleanText(rawSummary ?? '', maxIdentitySummaryChars);
    _identitySummary = momentIsSensitive(cleanSummary) ? '' : cleanSummary;

    final rawScanned = await _readString(storageKeyScanned);
    _scannedTurns.clear();
    if (rawScanned != null && rawScanned.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawScanned);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final count = entry.value;
            if (entry.key is String && count is num) {
              _scannedTurns[entry.key as String] = count.toInt();
            }
          }
        }
      } catch (_) {}
    }

    _isLoaded = true;
    notifyListeners();
  }

  /// Manually adds a personal detail so the user owns their profile directly.
  Future<UserFact?> addManual(String rawText) async {
    final clean = _cleanText(rawText, UserFact.maxLength);
    if (clean.length < 4 || momentIsSensitive(clean)) return null;
    if (_facts.any((existing) => _sameFact(existing.text, clean))) {
      return null;
    }
    final now = _clock();
    final fact = _makeFact(clean, now: now, pinned: true);
    _insertCapped(fact);
    if (_identitySummary.isEmpty) {
      _identitySummary = _fallbackSummary();
    }
    await _persist();
    notifyListeners();
    return fact;
  }

  Future<void> togglePin(String id) async {
    final idx = _facts.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final current = _facts[idx];
    _facts[idx] = current.copyWith(pinned: !current.pinned, updatedAt: _clock());
    await _persist();
    notifyListeners();
  }

  Future<void> deleteFact(String id) async {
    final removed = _facts.where((f) => f.id == id).isNotEmpty;
    if (!removed) return;
    _facts.removeWhere((f) => f.id == id);
    if (_facts.isEmpty) {
      _identitySummary = '';
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setIdentitySummary(String rawSummary) async {
    final clean = _cleanText(rawSummary, maxIdentitySummaryChars);
    if (clean.isNotEmpty && momentIsSensitive(clean)) return;
    _identitySummary = clean;
    await _persist();
    notifyListeners();
  }

  Future<void> clearIdentitySummary() => setIdentitySummary('');

  Future<void> forgetAll() async {
    _facts.clear();
    _identitySummary = '';
    _scannedTurns.clear();
    await _removeKey(storageKeyFacts);
    await _removeKey(storageKeySummary);
    await _removeKey(storageKeyScanned);
    notifyListeners();
  }

  /// Extracts durable facts after a conversation progresses/closes when at least
  /// 2 user turns exist and new user turns arrived since the last scan.
  Future<void> extractFromConversation({
    required String conversationId,
    required List<Map<String, String>> turns,
  }) async {
    final runExtractor = extractor;
    if (runExtractor == null || conversationId.trim().isEmpty) return;
    if (_inFlight.contains(conversationId)) return;

    final userTurns = [
      for (final t in turns)
        if (t['role'] == 'user' && (t['text'] ?? '').trim().isNotEmpty) t,
    ];
    if (userTurns.length < 2) return;
    final previousCount = _scannedTurns[conversationId] ?? 0;
    if (userTurns.length <= previousCount) return;

    _inFlight.add(conversationId);
    try {
      final result = await runExtractor(turns, factLines());
      if (result == null) return;

      _scannedTurns[conversationId] = userTurns.length;
      final now = _clock();
      var changed = false;

      for (final raw in result.facts) {
        final clean = _cleanText(raw, UserFact.maxLength);
        if (clean.length < 8 || momentIsSensitive(clean)) continue;
        if (_facts.any((f) => _sameFact(f.text, clean))) continue;
        _insertCapped(_makeFact(
          clean,
          now: now,
          sourceConversationId: conversationId,
        ));
        changed = true;
      }

      final cleanSummary =
          _cleanText(result.identitySummary, maxIdentitySummaryChars);
      if (cleanSummary.length >= 12 &&
          !momentIsSensitive(cleanSummary) &&
          cleanSummary != _identitySummary &&
          _facts.isNotEmpty) {
        _identitySummary = cleanSummary;
        changed = true;
      }

      await _persist();
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('[UserFacts] Background extraction skipped: $e');
    } finally {
      _inFlight.remove(conversationId);
    }
  }

  UserFact _makeFact(
    String text, {
    required DateTime now,
    String? sourceConversationId,
    bool pinned = false,
  }) {
    _idCounter++;
    return UserFact(
      id: 'fact_${now.microsecondsSinceEpoch}_$_idCounter',
      text: text,
      createdAt: now,
      updatedAt: now,
      sourceConversationId: sourceConversationId,
      pinned: pinned,
    );
  }

  void _insertCapped(UserFact fact) {
    _facts.add(fact);
    if (_facts.length <= maxFacts) return;
    // Evict oldest unpinned fact first to preserve user-pinned items.
    final unpinned = _facts.where((f) => !f.pinned).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    if (unpinned.isNotEmpty) {
      _facts.removeWhere((f) => f.id == unpinned.first.id);
    } else {
      _facts.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      _facts.removeAt(0);
    }
  }

  String _fallbackSummary() {
    final top = factLines(maxCount: 3)
        .map((s) => s.endsWith('.') ? s.substring(0, s.length - 1) : s)
        .toList();
    if (top.isEmpty) return '';
    final joined = top.length == 1 ? '${top.first}.' : '${top.join('; ')}.';
    return joined.length <= maxIdentitySummaryChars
        ? joined
        : '${joined.substring(0, maxIdentitySummaryChars - 1).trimRight()}.';
  }

  static String _cleanText(String raw, int limit) {
    final singleLine = raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (singleLine.length <= limit) return singleLine;
    return singleLine.substring(0, limit).trim();
  }

  static bool _sameFact(String a, String b) {
    final na = a.toLowerCase().trim();
    final nb = b.toLowerCase().trim();
    if (na == nb) return true;
    final wa = _meaningfulWords(na);
    final wb = _meaningfulWords(nb);
    if (wa.isEmpty || wb.isEmpty) return false;
    final inter = wa.intersection(wb).length;
    final union = wa.union(wb).length;
    return union > 0 && (inter / union) >= 0.6;
  }

  static final RegExp _wordRe = RegExp(r'[a-z0-9]+');
  static const Set<String> _stop = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'been', 'being', 'by', 'called',
    'can', 'could', 'enjoy', 'enjoys', 'feel', 'feels', 'for', 'from', 'gets',
    'got', 'had', 'has', 'have', 'he', 'her', 'his', 'i', 'in', 'is', 'it',
    'its', 'like', 'likes', 'live', 'lives', 'love', 'loves', 'me', 'my',
    'named', 'of', 'on', 'or', 'person', 'prefer', 'prefers', 'she', 'should',
    'someone', 'studies', 'study', 'that', 'the', 'their', 'them', 'they',
    'this', 'to', 'user', 'uses', 'using', 'was', 'were', 'with', 'work',
    'works', 'would',
  };

  static Set<String> _meaningfulWords(String s) => {
        for (final m in _wordRe.allMatches(s))
          if (!_stop.contains(m.group(0)) && (m.group(0)?.length ?? 0) > 1)
            m.group(0)!,
      };

  Future<String?> _readString(String key) async {
    if (_secureStore != null) {
      return _secureStore.readString(key, legacyPreferences: _prefs);
    }
    return _prefs?.getString(key);
  }

  Future<void> _writeString(String key, String value) async {
    if (_secureStore != null) {
      await _secureStore.writeString(key, value);
    } else {
      await _prefs?.setString(key, value);
    }
  }

  Future<void> _removeKey(String key) async {
    if (_secureStore != null) {
      await _secureStore.remove(key, legacyPreferences: _prefs);
    } else {
      await _prefs?.remove(key);
    }
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _writeString(
      storageKeyFacts,
      jsonEncode([for (final f in _facts) f.toMap()]),
    );
    await _writeString(storageKeySummary, _identitySummary);
    await _writeString(storageKeyScanned, jsonEncode(_scannedTurns));
  }
}
