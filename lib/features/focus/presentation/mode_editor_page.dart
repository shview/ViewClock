import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../application/focus_controller.dart';
import '../domain/focus_models.dart';

class ModeEditorPage extends StatefulWidget {
  const ModeEditorPage({super.key, required this.controller, this.mode});

  final FocusController controller;
  final FocusMode? mode;

  @override
  State<ModeEditorPage> createState() => _ModeEditorPageState();
}

class _ModeEditorPageState extends State<ModeEditorPage> {
  late final TextEditingController _name;
  late double _minutes;
  late double _unlockLimit;
  late List<String> _whitelist;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.mode?.name ?? '自定义专注');
    _minutes = (widget.mode?.focusMinutes ?? 30).toDouble();
    _unlockLimit = (widget.mode?.temporaryUnlockLimit ?? 2).toDouble();
    _whitelist = [...?widget.mode?.whitelist];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.mode == null ? '新建模式' : '编辑模式'),
      actions: [
        if (widget.mode != null)
          IconButton(
            tooltip: '删除模式',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '模式名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '专注时长：${_minutes.round()} 分钟',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: _minutes,
          min: 1,
          max: 120,
          divisions: 119,
          onChanged: (value) => setState(() => _minutes = value),
        ),
        const SizedBox(height: 16),
        Text(
          '每次允许临时解锁：${_unlockLimit.round()} 次',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: _unlockLimit,
          min: 0,
          max: 5,
          divisions: 5,
          onChanged: (value) => setState(() => _unlockLimit = value),
        ),
        const SizedBox(height: 16),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined),
          title: Text('轻度锁定'),
          subtitle: Text('记录离开白名单的行为，不自动拉回。主力机默认使用此模式。'),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('白名单'),
            subtitle: Text('已选择 ${_whitelist.length} 个应用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickApps,
          ),
        ),
      ],
    ),
  );

  Future<void> _pickApps() async {
    final selected = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AppPickerPage(controller: widget.controller, selected: _whitelist),
      ),
    );
    if (selected != null) setState(() => _whitelist = selected);
  }

  Future<void> _save() async {
    final old = widget.mode;
    final mode = FocusMode(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? '未命名模式' : _name.text.trim(),
      focusMinutes: _minutes.round(),
      breakMinutes: old?.breakMinutes ?? 5,
      lockStrength: LockStrength.light,
      whitelist: _whitelist,
      temporaryUnlockLimit: _unlockLimit.round(),
    );
    await widget.controller.saveMode(mode);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final mode = widget.mode;
    if (mode == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个模式？'),
        content: Text('“${mode.name}”将被删除，已有专注历史不会受影响。'),
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
    if (confirmed != true) return;
    try {
      await widget.controller.deleteMode(mode.id);
      if (mounted) Navigator.pop(context);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }
}

class AppPickerPage extends StatefulWidget {
  const AppPickerPage({
    super.key,
    required this.controller,
    required this.selected,
  });

  final FocusController controller;
  final List<String> selected;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  final _search = TextEditingController();
  late final Set<String> _selected = widget.selected.toSet();
  List<Map<String, Object?>> _apps = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.controller.bridge.getInstalledApps();
      _apps = (result['apps'] as List? ?? const [])
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _apps.where((app) {
      final name = (app['name'] as String? ?? '').toLowerCase();
      final package = (app['packageName'] as String? ?? '').toLowerCase();
      return query.isEmpty || name.contains(query) || package.contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择白名单'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: _search,
              hintText: '搜索应用名称或包名',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('加载失败：$_error'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final app = filtered[index];
                final packageName = app['packageName']! as String;
                return CheckboxListTile(
                  value: _selected.contains(packageName),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(packageName);
                    } else {
                      _selected.remove(packageName);
                    }
                  }),
                  secondary: _AppIcon(
                    bridge: widget.controller,
                    packageName: packageName,
                  ),
                  title: Text(app['name'] as String? ?? packageName),
                  subtitle: Text(packageName),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.bridge, required this.packageName});

  final FocusController bridge;
  final String packageName;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  static final Map<String, Uint8List> _memoryCache = {};
  Uint8List? bytes;

  @override
  void initState() {
    super.initState();
    bytes = _memoryCache[widget.packageName];
    if (bytes != null) return;
    widget.bridge.bridge
        .getAppIcon(widget.packageName)
        .then((value) {
          if (value != null && mounted) {
            final decoded = base64Decode(value);
            _memoryCache[widget.packageName] = decoded;
            setState(() => bytes = decoded);
          }
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 42,
    child: bytes == null
        ? const Icon(Icons.android)
        : Image.memory(
            bytes!,
            gaplessPlayback: true,
            cacheWidth: 64,
            cacheHeight: 64,
            filterQuality: FilterQuality.medium,
          ),
  );
}
