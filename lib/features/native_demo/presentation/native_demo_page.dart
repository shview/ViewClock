import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/native_focus_bridge.dart';

class NativeDemoPage extends StatefulWidget {
  const NativeDemoPage({super.key, this.bridge});

  final NativeFocusBridge? bridge;

  @override
  State<NativeDemoPage> createState() => _NativeDemoPageState();
}

class _NativeDemoPageState extends State<NativeDemoPage> {
  final List<String> _logs = [];
  late final NativeFocusBridge _bridge;
  StreamSubscription<Map<String, Object?>>? _eventSubscription;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? NativeFocusBridge();
    _eventSubscription = _bridge.events.listen(
      (event) => _log('EVENT ${jsonEncode(event)}'),
      onError: (Object error) => _log('EVENT ERROR $error'),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    final time = TimeOfDay.now().format(context);
    setState(() {
      _logs.insert(0, '[$time] $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      _log('$label: ${_format(result)}');
    } on PlatformException catch (error) {
      _log('$label 失败 [${error.code}]: ${error.message}');
    } catch (error) {
      _log('$label 失败: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _format(Object? value) {
    if (value is Map && value['apps'] is List) {
      final apps = value['apps']! as List;
      final summary = Map<Object?, Object?>.from(value)..remove('apps');
      return '${jsonEncode(summary)}\n'
          '前 8 项: ${jsonEncode(apps.take(8).toList())}';
    }
    if (value is List && value.length > 8) {
      return '${value.length} 项\n${jsonEncode(value.take(8).toList())}';
    }
    if (value is Map || value is List) return jsonEncode(value);
    return value?.toString() ?? 'null';
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_DemoAction>[
      _DemoAction('Channel Ping', Icons.cable, _bridge.ping),
      _DemoAction('设备信息', Icons.phone_android, _bridge.getDeviceInfo),
      _DemoAction('应用列表诊断', Icons.apps, _bridge.getInstalledApps),
      _DemoAction(
        'Usage Access 状态',
        Icons.query_stats,
        _bridge.isUsageAccessGranted,
      ),
      _DemoAction('打开 Usage Access 设置', Icons.settings, () async {
        await _bridge.openUsageAccessSettings();
        return '已打开设置页';
      }),
      _DemoAction(
        '当前前台 App',
        Icons.visibility,
        _bridge.getCurrentForegroundApp,
      ),
      _DemoAction(
        'Device Owner 状态',
        Icons.admin_panel_settings,
        _bridge.isDeviceOwner,
      ),
      _DemoAction(
        'Lock Task 是否允许',
        Icons.lock_outline,
        _bridge.isLockTaskPermitted,
      ),
      _DemoAction('停止 Lock Task', Icons.lock_open, () async {
        await _bridge.stopLockTaskMode();
        return '已请求停止';
      }),
      _DemoAction(
        'Accessibility 状态',
        Icons.accessibility_new,
        _bridge.isAccessibilityEnabled,
      ),
      _DemoAction('停止前台监控', Icons.stop, () async {
        await _bridge.stopFocusMonitor();
        return '已停止';
      }),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('View Clock 能力验证'),
        actions: [
          IconButton(
            tooltip: '清空日志',
            onPressed: () => setState(_logs.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            MaterialBanner(
              content: const Text(
                '主力机安全模式：这里只提供只读诊断和停止操作。'
                '不会启用 Device Owner、Accessibility、Lock Task 或 root。',
              ),
              actions: const [SizedBox.shrink()],
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          childAspectRatio: 2.7,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: actions.length,
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _run(action.label, action.callback),
                        icon: Icon(action.icon),
                        label: Text(action.label, textAlign: TextAlign.center),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('日志', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(minHeight: 220),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      _logs.isEmpty ? '点击上方按钮开始验证。' : _logs.join('\n\n'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAction {
  const _DemoAction(this.label, this.icon, this.callback);

  final String label;
  final IconData icon;
  final Future<Object?> Function() callback;
}
