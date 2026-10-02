/// A therapist the user can store for quick contact, kept on their own device.
///
/// The user enters name, phone and email. Solace never verifies, dials, or
/// emails on its own: every action opens the platform's own app pre-filled.
class TherapistContact {
  const TherapistContact({
    required this.name,
    this.phone = '',
    this.email = '',
  });

  final String name;
  final String phone;
  final String email;

  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasEmail => email.trim().isNotEmpty;

  /// Keeps digits and a leading plus, which is all a dialer needs.
  String get dialablePhone => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Initials for the avatar circle, taken from the first two words.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words[1][0]}'.toUpperCase();
  }

  TherapistContact copyWith({String? name, String? phone, String? email}) {
    return TherapistContact(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
    };
  }

  factory TherapistContact.fromMap(Map<String, dynamic> map) {
    return TherapistContact(
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
    );
  }
}
