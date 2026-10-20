/// Where the person is based decides which local emergency number and
/// listening line the app can point to.
///
/// Only numbers that were checked against the service's own published
/// information belong here, with the date in [verifiedOn]. A country with no
/// verified entry gets [CountryResources.other]: no invented numbers, just
/// "your local emergency number". Add a country by adding one entry.
class Helpline {
  const Helpline({
    required this.name,
    required this.phone,
    required this.hours,
    required this.about,
  });

  final String name;

  /// Dialable number, digits only (a leading zero or plus is allowed).
  final String phone;

  /// Opening hours in plain words, as the service publishes them.
  final String hours;

  final String about;
}

class CountryResources {
  const CountryResources({
    required this.code,
    required this.name,
    required this.emergencyNumber,
    this.helplines = const [],
    this.verifiedOn,
  });

  /// ISO 3166-1 alpha-2, upper case. `ZZ` stands for "somewhere else".
  final String code;
  final String name;

  /// National emergency number, or null when none is verified for the country.
  final String? emergencyNumber;
  final List<Helpline> helplines;
  final String? verifiedOn;

  static const defaultCode = 'BD';

  static const bangladesh = CountryResources(
    code: 'BD',
    name: 'Bangladesh',
    emergencyNumber: '999',
    helplines: [
      Helpline(
        name: 'Kaan Pete Roi',
        phone: '09612119911',
        hours: 'Every day, 3 PM to 3 AM',
        about: 'Free, confidential listening line',
      ),
    ],
    // 999: National Emergency Service. Kaan Pete Roi: kaanpeteroi.org/helpline-service.
    verifiedOn: '2026-10-12',
  );

  static const other = CountryResources(
    code: 'ZZ',
    name: 'Somewhere else',
    emergencyNumber: null,
  );

  /// Countries offered in the picker, default first.
  static const all = [bangladesh, other];

  static CountryResources byCode(String? code) {
    final wanted = code?.trim().toUpperCase();
    for (final country in all) {
      if (country.code == wanted) return country;
    }
    return wanted == null || wanted.isEmpty ? bangladesh : other;
  }
}
