import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/footprint/life_pulse_policy.dart';
import '../../domain/personalization/personal_calibration.dart';

/// Manages gentle periodic "Is everything alright / anything on your mind?"
/// check-ins that gather light life context without waiting for extreme anomalies.
class LifePulseController extends ChangeNotifier {
  LifePulseController({
    SharedPreferences? preferences,
    DateTime Function()? clock,
    bool Function()? safetyActive,
    bool Function()? breakPromptActive,
  })  : _prefs = preferences,
        _clock = clock ?? DateTime.now,
        _safetyActive = safetyActive ?? (() => false),
        _breakPromptActive = breakPromptActive ?? (() => false);

  static const _entriesKey = 'personalization.lifePulse.entries.v1';
  static const _enabledKey = 'personalization.lifePulse.enabled.v1';

  SharedPreferences? _prefs;
  final DateTime Function() _clock;
  final bool Function() _safetyActive;
  final bool Function() _breakPromptActive;

  List<LifePulseEntry> _entries = const [];
  LifePulseEntry? _current;
  bool _enabled = true;

  bool get enabled => _enabled;
  LifePulseEntry? get current => _current;
  List<LifePulseEntry> get entries => List.unmodifiable(_entries);

  LifePulseSignal? get latestFreshSignal =>
      latestFreshLifePulse(_entries, _clock());

  Future<void> refresh() async {
    _prefs ??= await SharedPreferences.getInstance();
    _enabled = _prefs?.getBool(_enabledKey) ?? true;
    _entries = _readEntries();

    final now = _clock();
    final next = currentLifePulse(
      entries: _entries,
      now: now,
      enabled: _enabled,
      safetyActive: _safetyActive(),
      breakPromptActive: _breakPromptActive(),
    );

    if (next != null && !_entries.any((e) => e.key == next.key)) {
      _entries = [..._entries, next];
      await _writeEntries();
    }
    _current = next;
    notifyListeners();
  }

  Future<void> answer({required String moodTag, String? note}) async {
    final active = _current;
    final now = _clock();
    final cleanNote = note?.trim();
    final normalizedNote =
        (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote;
    final entry = (active ??
            LifePulseEntry(
              key: lifePulseKeyFor(now),
              status: LifePulseStatus.shown,
              shownAt: now,
            ))
        .answered(moodTag: moodTag, at: now, note: normalizedNote);

    await _saveEntry(entry);
    _current = null;
    notifyListeners();
  }

  Future<void> dismiss() async {
    final active = _current;
    if (active == null) return;
    final now = _clock();
    await _saveEntry(active.dismissed(at: now));
    _current = null;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool(_enabledKey, value);
    _enabled = value;
    if (!value) {
      _current = null;
      notifyListeners();
    } else {
      await refresh();
    }
  }

  Future<void> clearAll() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_entriesKey);
    _entries = const [];
    _current = null;
    notifyListeners();
  }

  /// Active theme tags for recommendation ranking when a recent check-in named one.
  List<String> activeThemes() {
    final signal = latestFreshSignal;
    if (signal == null) return const [];
    return switch (signal.moodTag) {
      'work' => const ['work'],
      'relationships' => const ['relationships'],
      'sleep' => const ['sleep'],
      'stressed' => const ['work'],
      'tired' => const ['sleep'],
      _ => const [],
    };
  }

  List<LifePulseEntry> _readEntries() {
    final raw = _prefs?.getString(_entriesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (LifePulseEntry.fromMap(item) case final entry?) entry,
      ]..sort((a, b) => a.shownAt.compareTo(b.shownAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveEntry(LifePulseEntry entry) async {
    _prefs ??= await SharedPreferences.getInstance();
    _entries = [
      for (final item in _entries)
        if (item.key != entry.key) item,
      entry,
    ]..sort((a, b) => a.shownAt.compareTo(b.shownAt));
    if (_entries.length > 40) {
      _entries = _entries.sublist(_entries.length - 40);
    }
    await _writeEntries();
  }

  Future<void> _writeEntries() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(
      _entriesKey,
      jsonEncode([for (final e in _entries) e.toMap()]),
    );
  }
}
