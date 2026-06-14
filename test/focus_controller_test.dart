import 'dart:async';
import 'dart:convert';

import 'package:flutter_application_2/core/platform/native_focus_bridge.dart';
import 'package:flutter_application_2/features/focus/application/focus_controller.dart';
import 'package:flutter_application_2/features/focus/domain/focus_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBridge extends NativeFocusBridge {
  String? state;
  bool monitorRunning = false;
  bool accessibilityEnabled = false;
  bool? enforce;
  final eventController = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get events => eventController.stream;

  @override
  Future<String?> readAppState() async => state;

  @override
  Future<void> writeAppState(String value) async => state = value;

  @override
  Future<bool> isUsageAccessGranted() async => true;

  @override
  Future<bool> isAccessibilityEnabled() async => accessibilityEnabled;

  @override
  Future<bool> isNotificationPermissionGranted() async => true;

  @override
  Future<void> startFocusMonitor(
    List<String> whitelist, {
    bool enforce = false,
  }) async {
    monitorRunning = true;
    this.enforce = enforce;
  }

  @override
  Future<void> stopFocusMonitor() async {
    monitorRunning = false;
  }

  Future<void> disposeBridge() async {
    await eventController.close();
  }
}

void main() {
  test('old mode data migrates with one cycle', () async {
    final bridge = _FakeBridge()
      ..state = jsonEncode({
        'modes': [
          {
            'id': 'old',
            'name': '旧模式',
            'focusMinutes': 25,
            'breakMinutes': 5,
            'lockStrength': 'light',
            'whitelist': <String>[],
          },
        ],
        'sessions': <Object?>[],
        'activeFocus': null,
      });
    final controller = FocusController(bridge: bridge);

    await controller.initialize();

    expect(controller.modes.single.cycles, 1);
    controller.dispose();
    await bridge.disposeBridge();
  });

  test('focus advances to break and then next cycle', () async {
    final bridge = _FakeBridge();
    final controller = FocusController(bridge: bridge);
    await controller.initialize();
    const mode = FocusMode(
      id: 'cycle',
      name: '循环测试',
      focusMinutes: 1,
      breakMinutes: 1,
      cycles: 2,
      lockStrength: LockStrength.light,
      whitelist: [],
    );
    await controller.saveMode(mode);
    await controller.startFocus(mode);

    await controller.advancePhase();
    expect(controller.activeFocus?.phase, FocusPhase.breakTime);
    expect(controller.activeFocus?.currentCycle, 1);
    expect(bridge.monitorRunning, isFalse);

    await controller.advancePhase();
    expect(controller.activeFocus?.phase, FocusPhase.focus);
    expect(controller.activeFocus?.currentCycle, 2);
    expect(bridge.monitorRunning, isTrue);
    controller.dispose();
    await bridge.disposeBridge();
  });

  test('last break completes the whole session', () async {
    final bridge = _FakeBridge();
    final controller = FocusController(bridge: bridge);
    await controller.initialize();
    const mode = FocusMode(
      id: 'single',
      name: '单轮测试',
      focusMinutes: 1,
      breakMinutes: 1,
      cycles: 1,
      lockStrength: LockStrength.light,
      whitelist: [],
    );
    await controller.saveMode(mode);
    await controller.startFocus(mode);

    await controller.advancePhase();
    expect(controller.activeFocus?.phase, FocusPhase.breakTime);
    await controller.advancePhase();

    expect(controller.activeFocus, isNull);
    expect(controller.sessions.first.completed, isTrue);
    expect(controller.sessions.first.focusedSeconds, 60);
    controller.dispose();
    await bridge.disposeBridge();
  });

  test('export excludes active session and import validates modes', () async {
    final bridge = _FakeBridge();
    final controller = FocusController(bridge: bridge);
    await controller.initialize();
    await controller.startFocus(controller.modes.first);

    final exported =
        jsonDecode(controller.exportJson()) as Map<String, Object?>;
    expect(exported['activeFocus'], isNull);

    await expectLater(
      controller.importJson('{"modes": [], "sessions": []}'),
      throwsA(isA<StateError>()),
    );
    await controller.finish(completed: false, reason: '测试清理');

    await expectLater(
      controller.importJson('{"modes": [], "sessions": []}'),
      throwsA(isA<FormatException>()),
    );
    controller.dispose();
    await bridge.disposeBridge();
  });

  test('medium mode requires accessibility and enables enforcement', () async {
    final bridge = _FakeBridge();
    final controller = FocusController(bridge: bridge);
    await controller.initialize();
    const mode = FocusMode(
      id: 'medium',
      name: '中度测试',
      focusMinutes: 1,
      breakMinutes: 0,
      lockStrength: LockStrength.medium,
      whitelist: [],
    );
    await controller.saveMode(mode);

    await expectLater(controller.startFocus(mode), throwsA(isA<StateError>()));

    bridge.accessibilityEnabled = true;
    await controller.startFocus(mode);
    expect(bridge.monitorRunning, isTrue);
    expect(bridge.enforce, isTrue);
    controller.dispose();
    await bridge.disposeBridge();
  });

  test('duplicate usage and accessibility events count once', () async {
    final bridge = _FakeBridge()..accessibilityEnabled = true;
    final controller = FocusController(bridge: bridge);
    await controller.initialize();
    const mode = FocusMode(
      id: 'medium',
      name: '中度测试',
      focusMinutes: 1,
      breakMinutes: 0,
      lockStrength: LockStrength.medium,
      whitelist: [],
    );
    await controller.saveMode(mode);
    await controller.startFocus(mode);
    final now = DateTime.now().millisecondsSinceEpoch;

    bridge.eventController.add({
      'type': 'violationDetected',
      'packageName': 'example.blocked',
      'timestamp': now,
    });
    bridge.eventController.add({
      'type': 'appBlocked',
      'packageName': 'example.blocked',
      'timestamp': now + 100,
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeFocus?.violations, 1);
    expect(controller.blockedPackage, 'example.blocked');
    controller.dispose();
    await bridge.disposeBridge();
  });
}
