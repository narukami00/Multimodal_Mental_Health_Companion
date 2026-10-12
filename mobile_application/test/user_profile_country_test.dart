import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/country_resources.dart';
import 'package:solace_mobile/core/models/user_profile.dart';

void main() {
  test('a new profile is for Bangladesh', () {
    expect(const UserProfile().countryCode, 'BD');
    expect(UserProfile.fromMap(const {}).countryCode, 'BD');
  });

  test('the country survives a save and load', () {
    final saved = const UserProfile().copyWith(countryCode: 'ZZ').toMap();
    expect(UserProfile.fromMap(Map<String, dynamic>.from(saved)).countryCode, 'ZZ');
  });

  test('an unknown code falls back to no invented numbers', () {
    final other = CountryResources.byCode('XX');
    expect(other.emergencyNumber, isNull);
    expect(other.helplines, isEmpty);
    expect(CountryResources.byCode(null).code, 'BD');
    expect(CountryResources.byCode('bd').emergencyNumber, '999');
  });
}
