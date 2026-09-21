import '../../core/models/support_resource.dart';

abstract final class SupportResourceCatalog {
  static List<SupportResource> forRegion(String regionCode) {
    final normalizedRegion = regionCode.trim().toUpperCase();
    final regionEntries = _entries[normalizedRegion];
    return List.unmodifiable(regionEntries ?? _globalEntries);
  }

  static bool hasUnverifiedEntries(String regionCode) {
    return forRegion(regionCode).any((resource) => !resource.isVerified);
  }

  static const _globalEntries = [
    SupportResource(
      regionCode: 'GLOBAL',
      kind: SupportResourceKind.trustedPerson,
      title: 'Reach someone you trust',
      description: 'If you can, tell someone nearby or someone you trust how today is feeling.',
      isVerified: true,
    ),
    SupportResource(
      regionCode: 'GLOBAL',
      kind: SupportResourceKind.localEmergency,
      title: 'Local emergency support',
      description: 'If you may act on thoughts of harm, contact your local emergency service or go to the nearest emergency department.',
      isVerified: false,
    ),
    SupportResource(
      regionCode: 'GLOBAL',
      kind: SupportResourceKind.professionalSupport,
      title: 'A professional you already know',
      description: 'A therapist, doctor, counselor, or other trusted professional can help you decide what support fits next.',
      isVerified: true,
    ),
  ];

  // Regional phone numbers must be manually verified before this table is
  // exposed to external users. The Bangladesh entry intentionally contains no
  // invented number while the project team completes that review.
  static const _entries = <String, List<SupportResource>>{
    'BD': [
      SupportResource(
        regionCode: 'BD',
        kind: SupportResourceKind.trustedPerson,
        title: 'Reach someone you trust',
        description: 'If you can, tell someone nearby or someone you trust how today is feeling.',
        isVerified: true,
      ),
      SupportResource(
        regionCode: 'BD',
        kind: SupportResourceKind.localEmergency,
        title: 'Local emergency support',
        description: 'Use your verified local emergency number or go to the nearest emergency department.',
        isVerified: false,
      ),
      SupportResource(
        regionCode: 'BD',
        kind: SupportResourceKind.professionalSupport,
        title: 'A local professional',
        description: 'Contact a therapist, doctor, counselor, or clinic you already trust.',
        isVerified: true,
      ),
    ],
  };
}
