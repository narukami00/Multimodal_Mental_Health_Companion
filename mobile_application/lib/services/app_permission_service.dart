import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'check_in_reminder_service.dart';

/// What Solace can and cannot access, read from the platform.
///
/// Android owns these permissions, so this only reports their real state. The
/// app cannot flip them; the best it can do is send the user to the system
/// screen that can.
class AppPermissionService {
  /// Public so a test double can stand in without the platform channel.
  AppPermissionService();

  static final AppPermissionService instance = AppPermissionService();

  static const _channel = MethodChannel(
    'com.sysmentalhealth.solace_mobile/app_permissions',
  );

  /// Whether the OS is currently allowing Solace to post notifications.
  Future<bool> notificationsGranted() {
    return CheckInReminderService.instance.notificationsEnabled();
  }

  /// Whether microphone access is currently granted.
  Future<bool> microphoneGranted() async {
    try {
      return await _channel.invokeMethod<bool>('microphoneGranted') ?? false;
    } catch (error) {
      debugPrint('AppPermissionService microphone warning: $error');
      return false;
    }
  }

  /// Opens this app's page in system settings, where permissions are changed.
  ///
  /// Returns false when the screen could not be opened.
  Future<bool> openSystemSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (error) {
      debugPrint('AppPermissionService settings warning: $error');
      return false;
    }
  }
}
