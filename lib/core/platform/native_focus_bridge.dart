import 'package:flutter/services.dart';

class NativeFocusBridge {
  NativeFocusBridge({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('focus_lock/native'),
      _eventChannel = eventChannel ?? const EventChannel('focus_lock/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<Map<String, Object?>> get events => _eventChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, Object?>.from(event as Map));

  Future<Object?> ping() => _methodChannel.invokeMethod<Object?>('ping');

  Future<Map<String, Object?>> getDeviceInfo() async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'getDeviceInfo',
    );
    return result ?? const {};
  }

  Future<Map<String, Object?>> getInstalledApps() async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'getInstalledApps',
    );
    return result ?? const {};
  }

  Future<String?> getAppIcon(String packageName) => _methodChannel
      .invokeMethod<String>('getAppIcon', {'packageName': packageName});

  Future<bool> isUsageAccessGranted() => _boolMethod('isUsageAccessGranted');

  Future<void> openUsageAccessSettings() =>
      _methodChannel.invokeMethod<void>('openUsageAccessSettings');

  Future<String?> getCurrentForegroundApp() =>
      _methodChannel.invokeMethod<String>('getCurrentForegroundApp');

  Future<String?> readAppState() =>
      _methodChannel.invokeMethod<String>('readAppState');

  Future<void> writeAppState(String value) =>
      _methodChannel.invokeMethod<void>('writeAppState', {'value': value});

  Future<bool> isDeviceOwner() => _boolMethod('isDeviceOwner');

  Future<bool> isLockTaskPermitted() => _boolMethod('isLockTaskPermitted');

  Future<void> startLockTaskMode() =>
      _methodChannel.invokeMethod<void>('startLockTaskMode');

  Future<void> stopLockTaskMode() =>
      _methodChannel.invokeMethod<void>('stopLockTaskMode');

  Future<bool> isAccessibilityEnabled() =>
      _boolMethod('isAccessibilityEnabled');

  Future<void> openAccessibilitySettings() =>
      _methodChannel.invokeMethod<void>('openAccessibilitySettings');

  Future<bool> isNotificationPermissionGranted() =>
      _boolMethod('isNotificationPermissionGranted');

  Future<bool> requestNotificationPermission() =>
      _boolMethod('requestNotificationPermission');

  Future<void> startFocusMonitor(
    List<String> whitelist, {
    bool enforce = false,
  }) => _methodChannel.invokeMethod<void>('startFocusMonitor', {
    'whitelist': whitelist,
    'enforce': enforce,
  });

  Future<void> stopFocusMonitor() =>
      _methodChannel.invokeMethod<void>('stopFocusMonitor');

  Future<bool> _boolMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    return await _methodChannel.invokeMethod<bool>(method, arguments) ?? false;
  }
}
