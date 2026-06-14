import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../native_demo/presentation/native_demo_page.dart';
import '../application/focus_controller.dart';
import '../domain/focus_models.dart';
import 'mode_editor_page.dart';

class FocusShell extends StatefulWidget {
  const FocusShell({super.key, required this.controller});

  final FocusController controller;

  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.controller.activeFocus != null) {
      return ActiveFocusPage(controller: widget.controller);
    }
    final pages = [
      _HomeTab(controller: widget.controller),
      _HistoryTab(controller: widget.controller),
      _SettingsTab(controller: widget.controller),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: '专注'),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.controller});

  final FocusController controller;

  @override
  Widget build(BuildContext context) {
    final todayMinutes = controller.todayFocusedSeconds ~/ 60;
    final completed = controller.sessions
        .where((item) => item.completed)
        .length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('View Clock', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text('把今天留给真正重要的事', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(value: '$todayMinutes', label: '今日分钟'),
                ),
                Expanded(
                  child: _Metric(value: '$completed', label: '累计完成'),
                ),
                Expanded(
                  child: _Metric(
                    value: '${controller.sessions.length}',
                    label: '全部记录',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '专注模式',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: '新建模式',
              onPressed: () => _editMode(context, null),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final mode in controller.modes) ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
              leading: CircleAvatar(child: Text('${mode.focusMinutes}')),
              title: Text(mode.name),
              subtitle: Text(
                '${mode.focusMinutes}+${mode.breakMinutes} 分钟'
                ' · ${mode.cycles} 轮 · ${mode.lockStrength.label}锁定'
                ' · 白名单 ${mode.whitelist.length}',
              ),
              onTap: () => _start(context, mode),
              trailing: IconButton(
                tooltip: '编辑',
                onPressed: () => _editMode(context, mode),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        if (!controller.usageAccessGranted)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('使用情况访问权限未开启'),
              subtitle: const Text('可正常计时，但无法记录离开白名单的行为。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.bridge.openUsageAccessSettings,
            ),
          ),
      ],
    );
  }

  Future<void> _start(BuildContext context, FocusMode mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('开始“${mode.name}”？'),
        content: Text(
          '每轮专注 ${mode.focusMinutes} 分钟、休息 ${mode.breakMinutes} 分钟，'
          '共 ${mode.cycles} 轮。当前版本使用轻度监控，'
          '离开白名单会记录，但不会强制拉回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.startFocus(mode);
  }

  Future<void> _editMode(BuildContext context, FocusMode? mode) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ModeEditorPage(controller: controller, mode: mode),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      Text(label),
    ],
  );
}

class ActiveFocusPage extends StatefulWidget {
  const ActiveFocusPage({super.key, required this.controller});

  final FocusController controller;

  @override
  State<ActiveFocusPage> createState() => _ActiveFocusPageState();
}

class _ActiveFocusPageState extends State<ActiveFocusPage> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    final active = widget.controller.activeFocus;
    if (active == null) return;
    final remaining = active.endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      if (_transitioning) return;
      _transitioning = true;
      await widget.controller.advancePhase();
      _transitioning = false;
      if (mounted) _tick();
      return;
    }
    final unlock = active.unlockUntil;
    if (unlock != null && !unlock.isAfter(DateTime.now())) {
      unawaited(widget.controller.resumeMonitorIfNeeded());
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.activeFocus!;
    final mode = widget.controller.activeMode!;
    final isBreak = active.phase == FocusPhase.breakTime;
    final totalSeconds = (isBreak ? mode.breakMinutes : mode.focusMinutes) * 60;
    final remainingSeconds = _remaining.inSeconds
        .clamp(0, totalSeconds)
        .toInt();
    final progress = 1 - remainingSeconds / totalSeconds;
    final unlockRemaining = active.unlockUntil?.difference(DateTime.now());
    final isUnlocked = unlockRemaining != null && !unlockRemaining.isNegative;
    return Scaffold(
      appBar: AppBar(
        title: Text(isBreak ? '${mode.name} · 休息' : mode.name),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: Center(
                  child: SizedBox.square(
                    dimension: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 14,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _format(_remaining),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.displayMedium,
                            ),
                            Text(
                              isBreak
                                  ? '休息中'
                                  : isUnlocked
                                  ? '临时解锁中'
                                  : '正在专注',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  Chip(
                    avatar: Icon(
                      isBreak ? Icons.coffee_outlined : Icons.shield_outlined,
                      size: 18,
                    ),
                    label: Text(
                      isBreak ? '休息阶段' : '${mode.lockStrength.label}锁定',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.repeat, size: 18),
                    label: Text('第 ${active.currentCycle}/${mode.cycles} 轮'),
                  ),
                  if (!isBreak) ...[
                    Chip(
                      avatar: const Icon(Icons.warning_amber, size: 18),
                      label: Text('离开 ${active.violations} 次'),
                    ),
                    Chip(
                      avatar: const Icon(Icons.lock_open, size: 18),
                      label: Text(
                        '临时解锁 ${active.temporaryUnlocks}/'
                        '${mode.temporaryUnlockLimit}',
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              if (isBreak)
                FilledButton.tonalIcon(
                  onPressed: widget.controller.skipBreak,
                  icon: const Icon(Icons.skip_next),
                  label: Text(
                    active.currentCycle >= mode.cycles ? '完成本次专注' : '跳过休息',
                  ),
                )
              else if (isUnlocked)
                Text('将在 ${_format(unlockRemaining)} 后恢复监控')
              else
                FilledButton.tonalIcon(
                  onPressed:
                      active.temporaryUnlocks >= mode.temporaryUnlockLimit
                      ? null
                      : () => _unlock(context),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('短时临时解锁'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _confirmStop(context),
                child: const Text('提前结束并记为失败'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlock(BuildContext context) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('选择临时解锁时长')),
            for (final value in const [1, 3, 5])
              ListTile(
                title: Text('$value 分钟'),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (minutes != null) {
      await widget.controller.temporaryUnlock(Duration(minutes: minutes));
    }
  }

  Future<void> _confirmStop(BuildContext context) async {
    var confirmation = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('确认提前结束'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本次专注会记录为失败。请输入“结束”或“END”确认。'),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (value) {
                  setDialogState(() => confirmation = value.trim());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('继续专注'),
            ),
            FilledButton(
              onPressed:
                  confirmation == '结束' || confirmation.toUpperCase() == 'END'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('确认结束'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.finish(completed: false, reason: '用户提前结束');
    }
  }

  String _format(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.controller});

  final FocusController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64),
            SizedBox(height: 12),
            Text('还没有专注记录'),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('专注记录', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    value: '${controller.weekFocusedSeconds ~/ 60}',
                    label: '本周分钟',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: '${controller.monthFocusedSeconds ~/ 60}',
                    label: '本月分钟',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: '${(controller.completionRate * 100).round()}%',
                    label: '完成率',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final session in controller.sessions) ...[
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: session.completed
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: Icon(session.completed ? Icons.check : Icons.close),
              ),
              title: Text(session.modeName),
              subtitle: Text(
                '${_date(session.endedAt)} · '
                '${session.focusedSeconds ~/ 60} 分钟 · '
                '离开 ${session.violations} 次',
              ),
              trailing: Text(session.completed ? '完成' : '失败'),
              onTap: () => _showDetails(context, session),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _date(DateTime value) =>
      '${value.month}月${value.day}日 '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _showDetails(BuildContext context, FocusSession session) async {
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                session.modeName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              _DetailRow(label: '结果', value: session.completed ? '完成' : '失败'),
              _DetailRow(
                label: '实际专注',
                value: '${session.focusedSeconds ~/ 60} 分钟',
              ),
              _DetailRow(label: '计划时长', value: '${session.plannedMinutes} 分钟'),
              _DetailRow(label: '离开次数', value: '${session.violations}'),
              _DetailRow(label: '临时解锁', value: '${session.temporaryUnlocks}'),
              if (session.failureReason != null)
                _DetailRow(label: '失败原因', value: session.failureReason!),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除这条记录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (delete != true || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除专注记录？'),
        content: const Text('删除后统计会同步更新，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteSession(session.id);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.controller});

  final FocusController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('设置', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                controller.usageAccessGranted
                    ? Icons.check_circle
                    : Icons.warning_amber,
              ),
              title: const Text('使用情况访问权限'),
              subtitle: Text(controller.usageAccessGranted ? '已开启' : '未开启'),
              onTap: controller.bridge.openUsageAccessSettings,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新权限状态'),
              onTap: controller.refreshPermission,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.import_export),
          title: const Text('数据导入与导出'),
          subtitle: const Text('完整模式、白名单和专注记录 JSON 备份'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => BackupPage(controller: controller),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('原生能力与调试'),
          subtitle: const Text('包含 Device Owner 状态查询，但不会自动启用'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const NativeDemoPage()),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Card(
        child: ListTile(
          leading: Icon(Icons.security),
          title: Text('当前安全边界'),
          subtitle: Text(
            '仅使用 Usage Access 和可见前台服务。未启用设备管理员、'
            '无障碍、Root，也不会自动拉回或阻止紧急操作。',
          ),
        ),
      ),
    ],
  );
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.controller});

  final FocusController controller;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _input = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据导入与导出')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('本地 JSON 备份'),
            subtitle: Text(
              '导出不会包含进行中的会话。导入会替换模式和历史，'
              '执行前会把当前数据备份到剪贴板。',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _export,
          icon: const Icon(Icons.copy_all),
          label: const Text('复制全部数据到剪贴板'),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _input,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: '粘贴 View Clock JSON',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _paste,
          icon: const Icon(Icons.content_paste),
          label: const Text('从剪贴板粘贴'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _import,
          icon: const Icon(Icons.file_download_done),
          label: const Text('校验并导入'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!, textAlign: TextAlign.center),
        ],
      ],
    ),
  );

  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: widget.controller.exportJson()),
    );
    setState(() => _message = '完整备份已复制到剪贴板');
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _input.text = data!.text!;
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入并替换当前数据？'),
        content: const Text('当前模式和历史会被替换，旧数据将先备份到剪贴板。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final backup = await widget.controller.importJson(_input.text);
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) setState(() => _message = '导入成功；旧数据已复制到剪贴板');
    } catch (error) {
      if (mounted) setState(() => _message = '导入失败：$error');
    }
  }
}
