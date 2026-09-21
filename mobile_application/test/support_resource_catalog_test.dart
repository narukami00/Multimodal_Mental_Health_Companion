import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/safety/support_resource_catalog.dart';

void main() {
  test('regional resources do not silently fall back to a US hotline', () {
    final resources = SupportResourceCatalog.forRegion('BD');

    expect(resources, isNotEmpty);
    expect(resources.every((resource) => resource.regionCode == 'BD'), isTrue);
    expect(
      resources.any((resource) => resource.phone != null),
      isFalse,
    );
    expect(SupportResourceCatalog.hasUnverifiedEntries('BD'), isTrue);
  });

  test('unknown regions use a clearly marked global fallback', () {
    final resources = SupportResourceCatalog.forRegion('XX');

    expect(resources.every((resource) => resource.regionCode == 'GLOBAL'), isTrue);
    expect(SupportResourceCatalog.hasUnverifiedEntries('XX'), isTrue);
  });
}
