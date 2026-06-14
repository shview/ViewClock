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

  int focusedSecondsSince(DateTime start) => sessions
      .where((session) => !session.endedAt.isBefore(start))
      .fold(0, (sum, session) => sum + session.focusedSeconds);

  int get weekFocusedSeconds {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return focusedSecondsSince(start);
  }

  int get monthFocusedSeconds {
    final now = DateTime.now();
    return focusedSecondsSince(DateTime(now.year, now.month));
  }

  double get completionRate {
    if (sessions.isEmpty) return 0;
    return sessions.where((session) => session.completed).length /
        sessions.length;
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

  Future<void> deleteMode(String modeId) async {
    if (activeFocus?.modeId == modeId) {
      throw StateError('进行中的模式不能删除');
    }
    if (modes.length <= 1) {
      throw StateError('至少保留一个专注模式');
    }
    modes.removeWhere((mode) => mode.id == modeId);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    sessions.removeWhere((session) => session.id == sessionId);
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
      phase: FocusPhase.focus,
    );
    await _persist();
    await _startMonitor();
    notifyListeners();
  }

  Future<void> temporaryUnlock(Duration duration) async {
    final active = activeFocus;
    final mode = activeMode;
    if (active == null || mode == null || active.phase != FocusPhase.focus) {
      return;
    }
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
    final currentSegment = active.phase == FocusPhase.focus
        ? endedAt
              .difference(
                active.endsAt.subtract(Duration(minutes: mode.focusMinutes)),
              )
              .inSeconds
              .clamp(0, mode.focusMinutes * 60)
              .toInt()
        : 0;
    final elapsed = active.focusedSecondsBeforePhase + currentSegment;
    sessions.insert(
      0,
      FocusSession(
        id: active.id,
        modeId: mode.id,
        modeName: mode.name,
        startedAt: active.startedAt,
        endedAt: endedAt,
        plannedMinutes: mode.focusMinutes * mode.cycles,
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

  Future<void> advancePhase() async {
    final active = activeFocus;
    final mode = activeMode;
    if (active == null || mode == null) return;
    final now = DateTime.now();
    if (active.phase == FocusPhase.focus) {
      final focused = active.focusedSecondsBeforePhase + mode.focusMinutes * 60;
      await bridge.stopFocusMonitor();
      if (mode.breakMinutes <= 0 && active.currentCycle >= mode.cycles) {
        activeFocus = active.copyWith(
          focusedSecondsBeforePhase: focused,
          endsAt: now,
        );
        await finish(completed: true);
        return;
      }
      if (mode.breakMinutes <= 0) {
        activeFocus = active.copyWith(
          phase: FocusPhase.focus,
          currentCycle: active.currentCycle + 1,
          focusedSecondsBeforePhase: focused,
          endsAt: now.add(Duration(minutes: mode.focusMinutes)),
          clearUnlock: true,
        );
        await _persist();
        await _startMonitor();
        notifyListeners();
        return;
      }
      activeFocus = active.copyWith(
        phase: FocusPhase.breakTime,
        focusedSecondsBeforePhase: focused,
        endsAt: now.add(Duration(minutes: mode.breakMinutes)),
        clearUnlock: true,
      );
      await _persist();
      notifyListeners();
      return;
    }

    if (active.currentCycle >= mode.cycles) {
      await finish(completed: true);
      return;
    }
    activeFocus = active.copyWith(
      phase: FocusPhase.focus,
      currentCycle: active.currentCycle + 1,
      endsAt: now.add(Duration(minutes: mode.focusMinutes)),
      clearUnlock: true,
    );
    await _persist();
    await _startMonitor();
    notifyListeners();
  }

  Future<void> skipBreak() async {
    if (activeFocus?.phase != FocusPhase.breakTime) return;
    await advancePhase();
  }

  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert(_stateMap(includeActiveFocus: false));

  Future<String> importJson(String raw) async {
    if (activeFocus != null) {
      throw StateError('专注进行中不能导入数据');
    }
    final backup = exportJson();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('JSON 根节点必须是对象');
    final json = Map<String, Object?>.from(decoded);
    final importedModes = (json['modes'] as List? ?? const [])
        .map(
          (item) => FocusMode.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList();
    final importedSessions = (json['sessions'] as List? ?? const [])
        .map(
          (item) =>
              FocusSession.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList();
    if (importedModes.isEmpty) {
      throw const FormatException('备份中至少需要一个专注模式');
    }
    modes
      ..clear()
      ..addAll(importedModes);
    sessions
      ..clear()
      ..addAll(importedSessions);
    activeFocus = null;
    await _persist();
    notifyListeners();
    return backup;
  }

  Future<void> _startMonitor() async {
    if (!usageAccessGranted ||
        activeFocus == null ||
        activeFocus?.phase != FocusPhase.focus) {
      return;
    }
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

  Map<String, Object?> _stateMap({bool includeActiveFocus = true}) => {
    'schemaVersion': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'modes': modes.map((mode) => mode.toJson()).toList(),
    'sessions': sessions.map((session) => session.toJson()).toList(),
    'activeFocus': includeActiveFocus ? activeFocus?.toJson() : null,
  };

  Future<void> _persist() => bridge.writeAppState(jsonEncode(_stateMap()));

  List<FocusMode> _defaultModes() => const [
    FocusMode(
      id: 'pomodoro',
      name: '标准番茄钟',
      focusMinutes: 25,
      breakMinutes: 5,
      lockStrength: LockStrength.light,
      whitelist: [],
      cycles: 4,
    ),
    FocusMode(
      id: 'deep_focus',
      name: '长专注',
      focusMinutes: 45,
      breakMinutes: 10,
      lockStrength: LockStrength.light,
      whitelist: [],
      cycles: 1,
    ),
  ];

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
