import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('focus_lock/native');
  String? storedState;

  setUp(() {
    storedState = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'readAppState' => storedState,
            'isUsageAccessGranted' => true,
            'writeAppState' => null,
            'startFocusMonitor' => null,
            'stopFocusMonitor' => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders the focus MVP home', (tester) async {
    await tester.pumpWidget(const FocusLockApp());
    await tester.pumpAndSettle();

    expect(find.text('View Clock'), findsOneWidget);
    expect(find.text('标准番茄钟'), findsOneWidget);
    expect(find.text('长专注'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
  });

  testWidgets('active timer is centered and full close is safe', (
    tester,
  ) async {
    final now = DateTime.now();
    storedState = jsonEncode({
      'schemaVersion': 1,
      'modes': [
        {
          'id': 'test',
          'name': '测试专注',
          'focusMinutes': 25,
          'breakMinutes': 5,
          'lockStrength': 'light',
          'whitelist': <String>[],
          'temporaryUnlockLimit': 2,
        },
      ],
      'sessions': <Object?>[],
      'activeFocus': {
        'id': 'active',
        'modeId': 'test',
        'startedAt': now.toIso8601String(),
        'endsAt': now.add(const Duration(minutes: 25)).toIso8601String(),
        'violations': 0,
        'temporaryUnlocks': 0,
        'unlockUntil': null,
      },
    });

    await tester.pumpWidget(const FocusLockApp());
    await tester.pumpAndSettle();

    final ring = find.byType(CircularProgressIndicator);
    expect(ring, findsOneWidget);
    expect(tester.getCenter(ring).dx, closeTo(400, 0.5));

    await tester.tap(find.text('提前结束并记为失败'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不是结束');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认结束'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'END');
    await tester.pump();
    await tester.tap(find.text('确认结束'));
    await tester.pumpAndSettle();

    expect(find.text('View Clock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
