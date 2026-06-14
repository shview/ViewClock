import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/platform/native_focus_bridge.dart';
import '../domain/focus_models.dart';

class FocusController extends ChangeNotifier {
  FocusController({NativeFocusBridge? bridge})
    : bridge = bridge ?? NativeFocusBridge();

  final NativeFocusBridge bridge;
  final List<FocusMode> modes = [];
  final List<FocusSession> sessions = [];
  ActiveFocus? activeFocus;
  bool usageAccessGranted = false;
  bool loading = true;
  String? lastError;
  StreamSubscription<Map<String, Object?>>? _events;

  FocusMode? get activeMode {
    final id = activeFocus?.modeId;
    if (id == null) return null;
    for (final mode in modes) {
      if (mode.id == id) return mode;
    }
    return null;
  }

  int get todayFocusedSeconds {
    final now = DateTime.now();
    return sessions
        .where(
          (session) =>
              session.endedAt.year == now.year &&
              session.endedAt.month == now.month &&
              session.endedAt.day == now.day,
        )
        .fold(0, (sum, session) => sum + session.focusedSeconds);
  }

  Future<void> initialize() async {
    try {
      final raw = await bridge.readAppState();
      if (raw == null) {
        modes.addAll(_defaultModes());
      } else {
        final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
        modes.addAll(
          (json['modes'] as List? ?? const []).map(
            (item) =>
                FocusMode.fromJson(Map<String, Object?>.from(item as Map)),
          ),
        );
        sessions.addAll(
          (json['sessions'] as List? ?? const []).map(
            (item) =>
                FocusSession.fromJson(Map<String, Object?>.from(item as Map)),
          ),
        );
        if (json['activeFocus'] case final Map active) {
          activeFocus = ActiveFocus.fromJson(Map<String, Object?>.from(active));
        }
        if (modes.isEmpty) modes.addAll(_defaultModes());
      }
      usageAccessGranted = await bridge.isUsageAccessGranted();
      _events = bridge.events.listen(_handleNativeEvent);
      if (activeFocus != null) await _startMonitor();
    } catch (error) {
      lastError = error.toString();
      if (modes.isEmpty) modes.addAll(_defaultModes());
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshPermission() async {
    usageAccessGranted = await bridge.isUsageAccessGranted();
    notifyListeners();
  }

  Future<void> saveMode(FocusMode mode) async {
    final index = modes.indexWhere((item) => item.id == mode.id);
    if (index < 0) {
      modes.add(mode);
    } else {
      modes[index] = mode;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> startFocus(FocusMode mode) async {
    final now = DateTime.now();
    activeFocus = ActiveFocus(
      id: now.microsecondsSinceEpoch.toString(),
      modeId: mode.id,
      startedAt: now,
      endsAt: now.add(Duration(minutes: mode.focusMinutes)),
    );
    await _persist();
    await _startMonitor();
    notifyListeners();
  }

  Future<void> temporaryUnlock(Duration duration) async {
    final active = activeFocus;
    final mode = activeMode;
    if (active == null || mode == null) return;
    if (active.temporaryUnlocks >= mode.temporaryUnlockLimit) return;
    activeFocus = active.copyWith(
      temporaryUnlocks: active.temporaryUnlocks + 1,
      unlockUntil: DateTime.now().add(duration),
    );
    await bridge.stopFocusMonitor();
    await _persist();
    notifyListeners();
  }

  Future<void> resumeMonitorIfNeeded() async {
    final active = activeFocus;
    if (active == null) return;
    if (active.unlockUntil != null &&
        active.unlockUntil!.isAfter(DateTime.now())) {
      return;
    }
    if (active.unlockUntil != null) {
      activeFocus = active.copyWith(clearUnlock: true);
      await _persist();
    }
    await _startMonitor();
    notifyListeners();
  }

  Future<void> finish({required bool completed, String? reason}) async {
    final active = activeFocus;
    final mode = activeMode;
    if (active == null || mode == null) return;
    final endedAt = DateTime.now();
    final elapsed = endedAt
        .difference(active.startedAt)
        .inSeconds
        .clamp(0, mode.focusMinutes * 60)
        .toInt();
    sessions.insert(
      0,
      FocusSession(
        id: active.id,
        modeId: mode.id,
        modeName: mode.name,
        startedAt: active.startedAt,
        endedAt: endedAt,
        plannedMinutes: mode.focusMinutes,
        focusedSeconds: elapsed,
        completed: completed,
        violations: active.violations,
        temporaryUnlocks: active.temporaryUnlocks,
        failureReason: reason,
      ),
    );
    activeFocus = null;
    await bridge.stopFocusMonitor();
    await _persist();
    notifyListeners();
  }

  Future<void> _startMonitor() async {
    if (!usageAccessGranted || activeFocus == null) return;
    await bridge.startFocusMonitor(activeMode?.whitelist ?? const []);
  }

  void _handleNativeEvent(Map<String, Object?> event) {
    if (event['type'] != 'violationDetected' || activeFocus == null) return;
    final active = activeFocus!;
    if (active.unlockUntil?.isAfter(DateTime.now()) ?? false) return;
    activeFocus = active.copyWith(violations: active.violations + 1);
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> _persist() => bridge.writeAppState(
    jsonEncode({
      'schemaVersion': 1,
      'modes': modes.map((mode) => mode.toJson()).toList(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
      'activeFocus': activeFocus?.toJson(),
    }),
  );

  List<FocusMode> _defaultModes() => const [
    FocusMode(
      id: 'pomodoro',
      name: '标准番茄钟',
      focusMinutes: 25,
      breakMinutes: 5,
      lockStrength: LockStrength.light,
      whitelist: [],
    ),
    FocusMode(
      id: 'deep_focus',
      name: '长专注',
      focusMinutes: 45,
      breakMinutes: 10,
      lockStrength: LockStrength.light,
      whitelist: [],
    ),
  ];

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
