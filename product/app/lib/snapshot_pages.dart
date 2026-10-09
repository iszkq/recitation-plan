import 'package:flutter/cupertino.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app_model.dart';
import 'design.dart';

class LocalSnapshotsPage extends StatefulWidget {
  const LocalSnapshotsPage({super.key, required this.model});
  final AppModel model;
  @override
  State<LocalSnapshotsPage> createState() => _LocalSnapshotsPageState();
}

class _LocalSnapshotsPageState extends State<LocalSnapshotsPage> {
  List<LocalSnapshot> items = [];
  bool busy = false;
  String? error;
  AppModel get model => widget.model;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = await model.snapshots?.list() ?? <LocalSnapshot>[];
      if (mounted) setState(() => items = values);
    } catch (_) {
      if (mounted) setState(() => error = '读取快照失败，请检查文件权限和存储空间。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkpoint() async {
    if (busy || model.snapshots == null) return;
    setState(() => busy = true);
    try {
      await model.snapshots!.save(
        BackupService(
          model.store,
          profileId: 'local-profile',
        ).export(at: model.clock()),
      );
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        await showError(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore(LocalSnapshot item) async {
    if (busy || !item.valid || model.snapshots == null) return;
    setState(() => busy = true);
    try {
      final text = await model.snapshots!.read(item.id);
      final backup = BackupService(model.store, profileId: 'local-profile');
      final target = backup.snapshotState(text);
      final expected = model.store.snapshot();
      if (mounted) setState(() => busy = false);
      if (!mounted ||
          !await confirm(
            context,
            '恢复到这个时间点？',
            '恢复后保留快照中的 ${(target['articles'] as Map).values.where((a) => a['deleted'] != true).length} 篇文章、${(target['attempts'] as Map).length} 条考核。该时间点之后的变化将从当前档案移除；恢复前会保存当前完整档案，之后可再次恢复回来。',
            action: '恢复快照',
          ) ||
          !mounted) {
        return;
      }
      setState(() => busy = true);
      await backup.restoreSnapshot(
        text,
        expected: expected,
        saveCurrentArchive: (old) =>
            model.snapshots!.save(old, kind: LocalSnapshotKind.restore),
      );
      await model.reload();
      await load();
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (c) => CupertinoAlertDialog(
            title: const Text('快照已恢复'),
            content: const Text('学习档案和提醒已更新。恢复前的档案在列表中保留。'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(c),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        await showError(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('本机快照')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          const Text('找回之前的档案', style: Design.heading),
          const Text(
            '每次学习档案变化前自动留存，最多保留最近12份与14份每日快照；手动保存和恢复前档案各保留5份。快照仅在本机，卸载或换机仍需导出到文件或云盘。',
            style: Design.caption,
          ),
          if (model.snapshots == null)
            const Text('当前设备未启用本机快照。', style: Design.caption),
          if (model.snapshotError != null)
            Text(model.snapshotError!, style: Design.caption),
          if (error != null) Text(error!, style: Design.caption),
          PrimaryAction(
            '保存当前快照',
            onPressed: model.snapshots == null ? null : checkpoint,
            busy: busy,
          ),
          CupertinoButton(
            onPressed: busy ? null : load,
            child: const Text('刷新列表'),
          ),
          if (busy) const CupertinoActivityIndicator(),
          if (!busy && items.isEmpty)
            const EmptyContent('还没有本机快照', '后续保存学习记录时会自动留存，也可以现在保存。'),
          for (final item in items)
            DetailRow(
              inset: false,
              subtitleMaxLines: null,
              title:
                  '${dateLabel(localTime(item.createdAt, 'Asia/Shanghai'))} ${localTime(item.createdAt, 'Asia/Shanghai').hour.toString().padLeft(2, '0')}:${localTime(item.createdAt, 'Asia/Shanghai').minute.toString().padLeft(2, '0')}',
              subtitle: item.valid
                  ? '${switch (item.kind) {
                      LocalSnapshotKind.recent => '自动留存',
                      LocalSnapshotKind.daily => '每日留存',
                      LocalSnapshotKind.checkpoint => '手动保存',
                      LocalSnapshotKind.restore => '恢复前档案',
                    }} · ${item.counts['articles'] ?? 0} 篇文章 · ${item.counts['attempts'] ?? 0} 条考核\n点击预览并恢复'
                  : '文件损坏或格式不支持，原文件已保留，不能恢复',
              onTap: !busy && item.valid ? () => restore(item) : null,
            ),
        ],
      ),
    ),
  );
}
