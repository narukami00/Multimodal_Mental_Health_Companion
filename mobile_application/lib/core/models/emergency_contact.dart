/// A person the user can reach for support, stored on their own device.
///
/// Contacts are entirely user-managed: Solace never invents, verifies or
/// dials a number on the user's behalf.
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.isIce = false,
  });

  final String id;
  final String name;
  final String phone;

  /// Whether this is the person the user most trusts to call first.
  final bool isIce;

  EmergencyContact copyWith({String? name, String? phone, bool? isIce}) {
    return EmergencyContact(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isIce: isIce ?? this.isIce,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'isIce': isIce,
    };
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      isIce: map['isIce'] as bool? ?? false,
    );
  }

  /// Strips characters a dialer does not need, so the number works with
  /// `tel:` URIs regardless of how the user typed it.
  String get dialableNumber => phone.replaceAll(RegExp(r'[^0-9+]'), '');
}
