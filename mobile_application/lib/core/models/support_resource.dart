enum SupportResourceKind { trustedPerson, localEmergency, professionalSupport }

class SupportResource {
  const SupportResource({
    required this.regionCode,
    required this.kind,
    required this.title,
    required this.description,
    required this.isVerified,
    this.phone,
    this.url,
  });

  final String regionCode;
  final SupportResourceKind kind;
  final String title;
  final String description;
  final bool isVerified;
  final String? phone;
  final String? url;
}
