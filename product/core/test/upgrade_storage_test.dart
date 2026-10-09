import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory('.dart_tool/test-data').create(recursive: true);
    root = await root.createTemp('upgrade-');
  });
  tearDown(() async => root.delete(recursive: true));

  String oldName(Directory directory) =>
      'recitation_snapshot_${sha256.convert(utf8.encode(directory.absolute.path.toLowerCase())).toString().substring(0, 16)}';

  test('旧版本档案移至新iOS容器路径后读取原文件并继续保存', () async {
    final original = await Directory('${root.path}/old-container/recitation')
        .create(recursive: true);
    final legacy =
        await Hive.openBox<String>(oldName(original), path: original.path);
    final state = MemoryRecitationStore.emptyState();
    await legacy.put('state', jsonEncode(state));
    await legacy.close();
    var store = await HiveRecitationStore.open(original.path);
    final service =
        RecitationService(store, clock: () => DateTime.utc(2026, 10, 9, 4));
    final article = await service.importArticle(title: '原有文章', text: '学不可以已。');
    await service.createPlan(
        name: '原有计划',
        versionIds: [article.currentVersionId],
        start: DateTime(2026, 10, 9),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final task = (await store.tasks()).single;
    await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'passed',
        transcript: '学不可以已',
        isFinal: true);
    final before = store.snapshot();
    await store.close();
    final moved = Directory('${root.path}/new-container/recitation');
    await moved.parent.create(recursive: true);
    await original.rename(moved.path);
    store = await HiveRecitationStore.open(moved.path);
    try {
      expect(store.snapshot(), before);
      expect((await store.getAttempt('passed'))!.status, AttemptStatus.passed);
      await RecitationService(store)
          .importArticle(title: '升级后文章', text: '新内容。');
    } finally {
      await store.close();
    }
    store = await HiveRecitationStore.open(moved.path);
    try {
      expect(await store.articles(), hasLength(2));
      expect(
          moved
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.hive')),
          hasLength(1));
    } finally {
      await store.close();
    }
  });

  test('移动后的未知格式档案拒绝打开，保留原数据且不创建空档案', () async {
    final moved = await Directory('${root.path}/new-container').create();
    const name = 'recitation_snapshot_0123456789abcdef';
    var box = await Hive.openBox<String>(name, path: moved.path);
    final text = jsonEncode({'schemaVersion': 99, 'marker': '旧数据'});
    await box.put('state', text);
    await box.close();
    await expectLater(
        HiveRecitationStore.open(moved.path), throwsFormatException);
    box = await Hive.openBox<String>(name, path: moved.path);
    expect(box.get('state'), text);
    await box.close();
    expect(
        moved
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.hive')),
        hasLength(1));
  });

  test('多个候选档案拒绝自动选择，所有文件和内容保持原样', () async {
    for (final name in [
      'recitation_snapshot_0123456789abcdef',
      'recitation_snapshot_fedcba9876543210'
    ]) {
      final box = await Hive.openBox<String>(name, path: root.path);
      await box.put('state', jsonEncode(MemoryRecitationStore.emptyState()));
      await box.close();
    }
    final before = {
      for (final f in root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hive')))
        f.path: await f.readAsBytes()
    };
    await expectLater(
        HiveRecitationStore.open(root.path), throwsFormatException);
    for (final entry in before.entries) {
      expect(await File(entry.key).readAsBytes(), entry.value);
    }
    expect(
        root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.hive')),
        hasLength(2));
  });
}
