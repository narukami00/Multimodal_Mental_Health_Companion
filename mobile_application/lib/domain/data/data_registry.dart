/// Everything Solace stores on the phone, declared once.
///
/// A new feature that keeps data adds ONE entry here, and saving a copy, bringing one back, erasing, and the
/// therapist summary all pick it up. A test reads the source for stored keys and fails if one is missing, so
/// forgetting is not possible.
enum DataKind {
  /// Things the person made or that describe them: check-ins, chats, moments, goals, the forest.
  personal,

  /// What the person chose: settings, consent, voices.
  choice,

  /// Tied to this phone or rebuilt on demand: moves nowhere, and is not part of a copy.
  device,
}

class DataEntry {
  const DataEntry({
    required this.id,
    required this.label,
    required this.kind,
    this.keys = const [],
    this.prefixes = const [],
    this.inTherapistSummary = false,
  });

  /// Short and stable; used in tests and, later, in reports.
  final String id;

  /// In the person's words.
  final String label;
  final DataKind kind;

  /// Exact preference keys.
  final List<String> keys;

  /// For families of keys (one per day, one per item).
  final List<String> prefixes;

  /// Whether it may appear in a summary the person chooses to hand to a therapist.
  final bool inTherapistSummary;

  bool covers(String key) => keys.contains(key) || prefixes.any(key.startsWith);

  /// Whether it travels in a saved copy.
  bool get inBackup => kind != DataKind.device;
}

const dataRegistry = <DataEntry>[
  DataEntry(
    id: 'check_ins',
    label: 'Check-ins and journal',
    kind: DataKind.personal,
    keys: ['sessions.records'],
    inTherapistSummary: true,
  ),
  DataEntry(
    id: 'chats',
    label: 'Conversations with Sol',
    kind: DataKind.personal,
    keys: ['solace_chat_conversations_v2', 'solace_active_chat_id_v2'],
  ),
  DataEntry(
    id: 'moments',
    label: 'Moments',
    kind: DataKind.personal,
    keys: ['memory.moments', 'memory.momentTombstones'],
  ),
  DataEntry(
    id: 'ideas',
    label: 'Ideas you tried',
    kind: DataKind.personal,
    keys: ['suggestions.records'],
    inTherapistSummary: true,
  ),
  DataEntry(id: 'forest', label: 'Your forest', kind: DataKind.personal, keys: ['forest_v1']),
  DataEntry(
    id: 'phone_patterns',
    label: 'Phone patterns',
    kind: DataKind.personal,
    keys: ['footprint.dailyFeatures', 'footprint.breakAnnotations'],
    inTherapistSummary: true,
  ),
  DataEntry(id: 'goals', label: 'Your phone goals', kind: DataKind.personal, keys: ['goals.list'], inTherapistSummary: true),
  DataEntry(id: 'safety', label: 'Support you were shown', kind: DataKind.personal, keys: ['safety.events']),
  DataEntry(id: 'profile', label: 'About you and your rhythm', kind: DataKind.personal, keys: ['profile.baseline']),
  DataEntry(id: 'therapist', label: 'Your therapist contact', kind: DataKind.personal, keys: ['profile.therapist_contact']),
  DataEntry(id: 'habits', label: 'Habit reminders', kind: DataKind.personal, keys: ['profile.habit_reminders']),
  DataEntry(id: 'quick_replies', label: 'Check-ins waiting to be saved', kind: DataKind.personal, keys: ['quick_replies.pending']),
  DataEntry(id: 'consent', label: 'What you agreed to', kind: DataKind.choice, keys: ['consent.ledger']),
  DataEntry(
    id: 'onboarding',
    label: 'Getting started',
    kind: DataKind.choice,
    keys: ['onboarding.complete', 'onboarding.current_page', 'onboarding.uses_media'],
  ),
  DataEntry(id: 'face_choice', label: 'Where your face is read', kind: DataKind.choice, keys: ['face_reading_place']),
  DataEntry(
    id: 'voice',
    label: 'How Sol speaks',
    kind: DataKind.choice,
    keys: ['companion_tts_enabled', 'companion_tts_voice_id', 'companion_tts_speed'],
  ),
  DataEntry(
    id: 'server',
    label: 'Your companion server address',
    kind: DataKind.device,
    keys: ['companion_server_host', 'companion_server_port', 'tailscale_migrated_v1'],
  ),
  DataEntry(
    id: 'widget_cache',
    label: 'Home-screen widget line and picture',
    kind: DataKind.device,
    keys: ['checkin_prompt', 'forest_scene_path'],
  ),
];

/// The entry that owns [key], or null for a key nobody declared.
DataEntry? registryEntryFor(String key) {
  for (final entry in dataRegistry) {
    if (entry.covers(key)) return entry;
  }
  return null;
}

/// Whether [key] travels in a saved copy. A key nobody declared is kept, never silently dropped.
bool keyInBackup(String key) => registryEntryFor(key)?.inBackup ?? true;
