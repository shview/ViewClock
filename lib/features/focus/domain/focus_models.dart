enum LockStrength { light, medium }

enum FocusPhase { focus, breakTime }

extension LockStrengthLabel on LockStrength {
  String get label => switch (this) {
    LockStrength.light => '轻度',
    LockStrength.medium => '中度',
  };
}

class FocusMode {
  const FocusMode({
    required this.id,
    required this.name,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.lockStrength,
    required this.whitelist,
    this.temporaryUnlockLimit = 2,
    this.cycles = 1,
  });

  final String id;
  final String name;
  final int focusMinutes;
  final int breakMinutes;
  final LockStrength lockStrength;
  final List<String> whitelist;
  final int temporaryUnlockLimit;
  final int cycles;

  FocusMode copyWith({
    String? name,
    int? focusMinutes,
    int? breakMinutes,
    LockStrength? lockStrength,
    List<String>? whitelist,
    int? temporaryUnlockLimit,
    int? cycles,
  }) {
    return FocusMode(
      id: id,
      name: name ?? this.name,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      lockStrength: lockStrength ?? this.lockStrength,
      whitelist: whitelist ?? this.whitelist,
      temporaryUnlockLimit: temporaryUnlockLimit ?? this.temporaryUnlockLimit,
      cycles: cycles ?? this.cycles,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'lockStrength': lockStrength.name,
    'whitelist': whitelist,
    'temporaryUnlockLimit': temporaryUnlockLimit,
    'cycles': cycles,
  };

  factory FocusMode.fromJson(Map<String, Object?> json) => FocusMode(
    id: json['id']! as String,
    name: json['name']! as String,
    focusMinutes: json['focusMinutes']! as int,
    breakMinutes: json['breakMinutes']! as int,
    lockStrength: LockStrength.values.byName(json['lockStrength']! as String),
    whitelist: List<String>.from(json['whitelist'] as List? ?? const []),
    temporaryUnlockLimit: json['temporaryUnlockLimit'] as int? ?? 2,
    cycles: json['cycles'] as int? ?? 1,
  );
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.modeId,
    required this.modeName,
    required this.startedAt,
    required this.endedAt,
    required this.plannedMinutes,
    required this.focusedSeconds,
    required this.completed,
    required this.violations,
    required this.temporaryUnlocks,
    this.failureReason,
  });

  final String id;
  final String modeId;
  final String modeName;
  final DateTime startedAt;
  final DateTime endedAt;
  final int plannedMinutes;
  final int focusedSeconds;
  final bool completed;
  final int violations;
  final int temporaryUnlocks;
  final String? failureReason;

  Map<String, Object?> toJson() => {
    'id': id,
    'modeId': modeId,
    'modeName': modeName,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'plannedMinutes': plannedMinutes,
    'focusedSeconds': focusedSeconds,
    'completed': completed,
    'violations': violations,
    'temporaryUnlocks': temporaryUnlocks,
    'failureReason': failureReason,
  };

  factory FocusSession.fromJson(Map<String, Object?> json) => FocusSession(
    id: json['id']! as String,
    modeId: json['modeId']! as String,
    modeName: json['modeName']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    endedAt: DateTime.parse(json['endedAt']! as String),
    plannedMinutes: json['plannedMinutes']! as int,
    focusedSeconds: json['focusedSeconds']! as int,
    completed: json['completed']! as bool,
    violations: json['violations'] as int? ?? 0,
    temporaryUnlocks: json['temporaryUnlocks'] as int? ?? 0,
    failureReason: json['failureReason'] as String?,
  );
}

class ActiveFocus {
  const ActiveFocus({
    required this.id,
    required this.modeId,
    required this.startedAt,
    required this.endsAt,
    this.phase = FocusPhase.focus,
    this.currentCycle = 1,
    this.focusedSecondsBeforePhase = 0,
    this.violations = 0,
    this.temporaryUnlocks = 0,
    this.unlockUntil,
  });

  final String id;
  final String modeId;
  final DateTime startedAt;
  final DateTime endsAt;
  final FocusPhase phase;
  final int currentCycle;
  final int focusedSecondsBeforePhase;
  final int violations;
  final int temporaryUnlocks;
  final DateTime? unlockUntil;

  ActiveFocus copyWith({
    int? violations,
    int? temporaryUnlocks,
    DateTime? unlockUntil,
    bool clearUnlock = false,
    DateTime? startedAt,
    DateTime? endsAt,
    FocusPhase? phase,
    int? currentCycle,
    int? focusedSecondsBeforePhase,
  }) => ActiveFocus(
    id: id,
    modeId: modeId,
    startedAt: startedAt ?? this.startedAt,
    endsAt: endsAt ?? this.endsAt,
    phase: phase ?? this.phase,
    currentCycle: currentCycle ?? this.currentCycle,
    focusedSecondsBeforePhase:
        focusedSecondsBeforePhase ?? this.focusedSecondsBeforePhase,
    violations: violations ?? this.violations,
    temporaryUnlocks: temporaryUnlocks ?? this.temporaryUnlocks,
    unlockUntil: clearUnlock ? null : unlockUntil ?? this.unlockUntil,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'modeId': modeId,
    'startedAt': startedAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'phase': phase.name,
    'currentCycle': currentCycle,
    'focusedSecondsBeforePhase': focusedSecondsBeforePhase,
    'violations': violations,
    'temporaryUnlocks': temporaryUnlocks,
    'unlockUntil': unlockUntil?.toIso8601String(),
  };

  factory ActiveFocus.fromJson(Map<String, Object?> json) => ActiveFocus(
    id: json['id']! as String,
    modeId: json['modeId']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    endsAt: DateTime.parse(json['endsAt']! as String),
    phase: FocusPhase.values.byName(
      json['phase'] as String? ?? FocusPhase.focus.name,
    ),
    currentCycle: json['currentCycle'] as int? ?? 1,
    focusedSecondsBeforePhase: json['focusedSecondsBeforePhase'] as int? ?? 0,
    violations: json['violations'] as int? ?? 0,
    temporaryUnlocks: json['temporaryUnlocks'] as int? ?? 0,
    unlockUntil: json['unlockUntil'] == null
        ? null
        : DateTime.parse(json['unlockUntil']! as String),
  );
}
