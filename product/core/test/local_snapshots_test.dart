import 'dart:io';
import 'dart:convert';
import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

class BrokenStore extends MemoryRecitationStore {
  bool fail = false;
  @override
  Future<void> persist(Map<String, dynamic> state) async {
    if (fail) throw const FileSystemException('full');
  }
}

void main() {
  late Directory dir;
  late DateTime now;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recitation-snapshots-');
    now = DateTime.utc(2026, 10, 8, 4);
  });
  tearDown(() => dir.delete(recursive: true));
  Future<void> add(MemoryRecitationStore store, String title) =>
      RecitationService(store, clock: () => now)
          .importArticle(title: title, text: '学不可以已。');
  test('Hive每次变化前留存，准确回滚并保留恢复前档案，重新打开不丢', () async {
    var store = await HiveRecitationStore.open(dir.path, clock: () => now);
    await add(store, '第一篇');
    final first = store.snapshot();
    await add(store, '第二篇');
    final snapshots = await store.snapshots.list();
    expect(snapshots, hasLength(2));
    final recent =
        snapshots.firstWhere((s) => s.kind == LocalSnapshotKind.recent);
    expect(recent.counts['articles'], 1);
    final backup = BackupService(store, profileId: 'local-profile');
    await backup.restoreSnapshot(await store.snapshots.read(recent.id),
        expected: store.snapshot(),
        saveCurrentArchive: (old) =>
            store.snapshots.save(old, kind: LocalSnapshotKind.restore));
    expect(store.snapshot(), first);
    final saved = (await store.snapshots.list())
        .singleWhere((s) => s.kind == LocalSnapshotKind.restore);
    expect(saved.counts['articles'], 2);
    await backup.restoreSnapshot(await store.snapshots.read(saved.id),
        expected: store.snapshot(),
        saveCurrentArchive: (old) =>
            store.snapshots.save(old, kind: LocalSnapshotKind.restore));
    expect(await store.articles(), hasLength(2));
    await store.close();
    store = await HiveRecitationStore.open(dir.path, clock: () => now);
    expect(await store.articles(), hasLength(2));
    expect(await store.snapshots.list(), isNotEmpty);
    await store.close();
  });
  test('留存限制按类别，坏文件保留并且禁止恢复，临时文件不展示', () async {
    final repository =
        LocalSnapshotRepository('${dir.path}/snapshots', clock: () => now);
    final store = MemoryRecitationStore();
    await add(store, '文章');
    for (var i = 0; i < 18; i++) {
      now = DateTime.utc(2026, 10, 8 + i, 4);
      await repository.captureBeforeWrite(store.snapshot());
    }
    var values = await repository.list();
    expect(
        values.where((s) => s.kind == LocalSnapshotKind.recent), hasLength(12));
    expect(
        values.where((s) => s.kind == LocalSnapshotKind.daily), hasLength(14));
    for (var i = 0; i < 7; i++) {
      now = now.add(const Duration(seconds: 1));
      await repository
          .save(BackupService(store, profileId: 'local').export(at: now));
    }
    final valid = (await repository.list()).first;
    await File('${repository.directory.path}/${valid.id}')
        .writeAsString('{bad');
    await File('${repository.directory.path}/recent-123.json.tmp')
        .writeAsString('interrupted');
    await repository
        .save(BackupService(store, profileId: 'local').export(at: now));
    values = await repository.list();
    expect(values.where((s) => !s.valid), hasLength(1));
    expect(
        values.where((s) => s.kind == LocalSnapshotKind.checkpoint && s.valid),
        hasLength(5));
    await expectLater(repository.read(valid.id), throwsFormatException);
    await expectLater(repository.read('../file.json'), throwsFormatException);
    expect(
        await File('${repository.directory.path}/${valid.id}').readAsString(),
        '{bad');
  });
  test('校验失败、来源不完整、引用错误和恢复前保存失败不改当前档案', () async {
    final store = MemoryRecitationStore();
    await add(store, '旧');
    final backup = BackupService(store, profileId: 'local');
    final text = backup.export();
    final expected = store.snapshot();
    final decoded = jsonDecode(text) as Map;
    decoded['entities']['articles'][0]['title'] = 'bad';
    await expectLater(
        backup.restoreSnapshot(jsonEncode(decoded),
            expected: expected, saveCurrentArchive: (_) async {}),
        throwsFormatException);
    final bundle = ArchiveBundle.decode(text);
    final partial = ArchiveBundle(
        manifest: ArchiveManifest(
            formatVersion: 1,
            profileId: 'local',
            exportedAt: now,
            timeZone: 'Asia/Shanghai',
            includesAudio: false,
            counts: const {'articles': 0}),
        entities: const {'articles': []}).encode();
    expect(() => backup.snapshotState(partial), throwsFormatException);
    bundle.entities['articles']!.first['currentVersionId'] = 'missing';
    expect(() => backup.snapshotState(bundle.encode()), throwsFormatException);
    await expectLater(
        backup.restoreSnapshot(text, expected: expected,
            saveCurrentArchive: (_) async {
          throw const FileSystemException('full');
        }),
        throwsA(isA<FileSystemException>()));
    expect(store.snapshot(), expected);
  });
  test('快照中的无效事件关联被拒绝，不能制造历史或撤销记录', () async {
    final store = MemoryRecitationStore();
    await add(store, '文章');
    final backup = BackupService(store, profileId: 'local');
    final original = store.snapshot();
    for (final reference in ['taskId', 'segmentId', 'attemptId', 'undoOf']) {
      final bundle = ArchiveBundle.decode(backup.export());
      bundle.entities['events']!.add({
        'id': 'bad-event',
        'type': 'taskRescheduled',
        'occurredAt': now.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
        'durationSeconds': 0,
        reference: 'missing',
      });
      final counts = {
        for (final entry in bundle.entities.entries)
          entry.key: entry.value.length
      };
      final invalid = ArchiveBundle(
              manifest: ArchiveManifest(
                  formatVersion: 1,
                  profileId: 'local',
                  exportedAt: now,
                  timeZone: 'Asia/Shanghai',
                  includesAudio: false,
                  counts: counts),
              entities: bundle.entities)
          .encode();
      expect(() => backup.snapshotState(invalid), throwsFormatException);
      expect(store.snapshot(), original);
    }
  });
  test('预览后并发写入不被恢复覆盖，失败持久化不发布状态，后续可重试', () async {
    final store = BrokenStore();
    await add(store, '旧');
    final backup = BackupService(store, profileId: 'local');
    final text = backup.export();
    final expected = store.snapshot();
    await add(store, '新');
    final current = store.snapshot();
    var captured = false;
    await expectLater(
        backup.restoreSnapshot(text, expected: expected,
            saveCurrentArchive: (_) async {
          captured = true;
        }),
        throwsStateError);
    expect(captured, isFalse);
    expect(store.snapshot(), current);
    store.fail = true;
    await expectLater(
        backup.restoreSnapshot(text, expected: current,
            saveCurrentArchive: (_) async {
          captured = true;
        }),
        throwsA(isA<FileSystemException>()));
    expect(captured, isTrue);
    expect(store.snapshot(), current);
    store.fail = false;
    await backup.restoreSnapshot(text,
        expected: current, saveCurrentArchive: (_) async {});
    expect(store.snapshot(), expected);
  });
  test('自动快照失败仍保存主档案并显示错误，存储恢复后继续留存', () async {
    final store = await HiveRecitationStore.open(dir.path, clock: () => now);
    await add(store, '第一篇');
    final blocking = File('${dir.path}/snapshots');
    await blocking.writeAsString('blocked');
    await add(store, '第二篇');
    expect(await store.articles(), hasLength(2));
    expect(store.snapshotError, isNotNull);
    await blocking.delete();
    await add(store, '第三篇');
    expect(store.snapshotError, isNull);
    expect(await store.snapshots.list(), hasLength(2));
    await store.close();
  });
}
