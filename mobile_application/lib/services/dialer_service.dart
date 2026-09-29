import 'package:url_launcher/url_launcher.dart';

/// Hands a phone number off to the platform dialer or messaging app.
///
/// Solace never places a call on its own: every launch opens the user's own
/// dialer pre-filled, and they still confirm it. Failures are reported as a
/// boolean so callers can show a gentle explanation instead of an error.
class DialerService {
  const DialerService();

  /// Opens the dialer pre-filled with [phone].
  Future<bool> openDialer(String phone) async {
    final number = _normalise(phone);
    if (number.isEmpty) return false;
    return _launch(Uri(scheme: 'tel', path: number));
  }

  /// Opens the SMS composer for [phone].
  Future<bool> openSms(String phone, {String? body}) async {
    final number = _normalise(phone);
    if (number.isEmpty) return false;
    return _launch(
      Uri(
        scheme: 'sms',
        path: number,
        queryParameters: body == null ? null : {'body': body},
      ),
    );
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Keeps digits and a leading plus, which is all a dialer needs.
  static String _normalise(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }
}
