import 'dart:convert';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late HiveRecitationStore store;
  late RecitationService service;
  late DateTime now;
  var sequence = 0;
  setUp(() async {
    directory = await Directory('.dart_tool/test-data').create(recursive: true);
    directory = await directory.createTemp('profile-');
    store = await HiveRecitationStore.open(directory.path);
    now = DateTime.utc(2026, 10, 8, 12);
    service = RecitationService(store,
        id: () => 'id-${sequence++}', clock: () => now);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<Task> arrange({String text = '学不可以已。'}) async {
    final article = await service.importArticle(title: '劝学', text: text);
    await service.createPlan(
        name: '十月计划',
        versionIds: [article.currentVersionId],
        start: DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    return (await store.tasks()).first;
  }

  test('导入、计划、最终考核、复习与报告闭环重启后保留', () async {
    final task = await arrange();
    final result = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'attempt-1',
        transcript: '学不可以已',
        isFinal: true,
        activeSeconds: 120);
    expect(result.status, AttemptStatus.passed);
    expect((await store.getTask(task.id))!.status, TaskStatus.completed);
    expect((await store.tasks()).where((t) => t.kind == TaskKind.review).length,
        5);
    await store.close();
    store = await HiveRecitationStore.open(directory.path);
    final report = buildReport(
        period: ReportPeriod.week,
        anchor: DateTime(2026, 10, 8),
        asOf: DateTime(2026, 10, 8),
        events: await store.events(),
        localDate: eventLocalTime);
    expect(report.dueTasks, 1);
    expect(report.completedTasks, 1);
    expect(report.newMasteredSegments, 1);
    expect(report.checkInDays, 1);
    expect(report.focusMinutes, 2);
    expect(report.reviewRetention, isNull);
  });

  test('同一最终回调并发重复提交不重复记录', () async {
    final task = await arrange();
    await Future.wait(List.generate(
        8,
        (_) => service.submitFinalTranscript(
            taskId: task.id,
            attemptId: 'repeated',
            transcript: '学不可以已',
            isFinal: true,
            activeSeconds: 60)));
    expect((await store.attemptsForSegment(task.segmentId)).length, 1);
    expect((await store.tasks()).length, 6);
    final events = await store.events();
    expect(
        events.where((e) => e.type == LearningEventType.taskCompleted).length,
        1);
    expect(events.where((e) => e.type == LearningEventType.attempt).length, 1);
  });

  test('临时识别、辅助练习与待复核结果不能完成任务', () async {
    final task = await arrange();
    await expectLater(
        service.submitFinalTranscript(
            taskId: task.id,
            attemptId: 'partial',
            transcript: '学不可以已',
            isFinal: false),
        throwsStateError);
    await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'assisted',
        transcript: '学不可以已',
        isFinal: true,
        assisted: true);
    await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'uncertain',
        transcript: '学不可以已',
        isFinal: true,
        hasUnresolvedDoubt: true);
    expect((await store.getTask(task.id))!.status, TaskStatus.pending);
    expect((await store.tasks()).length, 1);
    expect(await store.hasAttempt('partial'), isFalse);
  });

  test('导出恢复前保存旧档案，恢复后可继续学习', () async {
    final task = await arrange();
    await service.submitFinalTranscript(
        taskId: task.id, attemptId: 'a1', transcript: '学不可以已', isFinal: true);
    final backup = BackupService(store, profileId: 'source');
    final text = backup.export();
    final target = MemoryRecitationStore();
    final restore = BackupService(target, profileId: 'target');
    var saved = false;
    await restore.restore(text, saveCurrentArchive: (old) async {
      expect(ArchiveBundle.decode(old).manifest.profileId, 'target');
      saved = true;
    });
    expect(saved, isTrue);
    expect((await target.tasks()).length, 6);
    expect((await target.getTask(task.id))!.status, TaskStatus.completed);
    expect(restore.preview(text).added, 0);
    expect(restore.preview(text).canMerge, isTrue);
  });

  test('篡改档案、未备份成功或冲突不得写入', () async {
    await arrange();
    final text = BackupService(store, profileId: 'source').export();
    final altered = jsonDecode(text) as Map;
    altered['entities']['articles'][0]['title'] = 'changed';
    expect(
        () => ArchiveBundle.decode(jsonEncode(altered)), throwsFormatException);
    final target = MemoryRecitationStore();
    final restore = BackupService(target, profileId: 'target');
    await expectLater(
        restore.restore(text,
            saveCurrentArchive: (_) async => throw StateError('磁盘不可写')),
        throwsStateError);
    expect(await target.articles(), isEmpty);
    final a = (await store.articles()).first;
    await target.saveArticle(Article(
        id: a.id,
        title: '不同标题',
        currentVersionId: a.currentVersionId,
        createdAt: a.createdAt,
        updatedAt: a.updatedAt));
    expect(restore.preview(text).canMerge, isFalse);
  });

  test('只完成当天部分任务不能打卡', () async {
    await arrange(text: '学不可以已。\n\n青出于蓝。');
    final plan = (await store.plans()).first;
    final tasks = await store.tasks();
    // Exercise event accounting with two due tasks on the same date.
    final events = await store.events();
    final sameDayEvents = events
        .where((e) => e.type == LearningEventType.taskDue)
        .map((e) => LearningEvent(
            id: e.id,
            type: e.type,
            occurredAt: now,
            timeZone: plan.timeZone,
            durationSeconds: 0,
            taskId: e.taskId))
        .toList();
    sameDayEvents.add(LearningEvent(
        id: 'complete',
        type: LearningEventType.taskCompleted,
        occurredAt: now,
        timeZone: plan.timeZone,
        durationSeconds: 0,
        taskId: tasks.first.id));
    final r = buildReport(
        period: ReportPeriod.week,
        anchor: now,
        events: sameDayEvents,
        localDate: eventLocalTime);
    expect(r.completionRate, 50);
    expect(r.checkInDays, 0);
  });

  test('未知档案版本拒绝导入且关闭重开不丢数据', () async {
    await arrange();
    final before = (await store.articles()).single.id;
    await store.close();
    // Verify normal close/open remains lossless; malformed archive is independently rejected.
    store = await HiveRecitationStore.open(directory.path);
    expect((await store.articles()).single.id, before);
    final j =
        jsonDecode(BackupService(store, profileId: 'source').export()) as Map;
    j['manifest']['formatVersion'] = 999;
    expect(() => ArchiveBundle.decode(jsonEncode(j)), throwsFormatException);
  });

  test('Hive未知schema不能自动重置数据库', () async {
    await store.close();
    final file = directory
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.hive'));
    final name = file.uri.pathSegments.last.replaceAll('.hive', '');
    var box = await Hive.openBox<String>(name, path: directory.path);
    final old = box.get('state');
    await box.put('state', jsonEncode({'schemaVersion': 99}));
    await box.close();
    await expectLater(
        HiveRecitationStore.open(directory.path), throwsFormatException);
    box = await Hive.openBox<String>(name, path: directory.path);
    expect(jsonDecode(box.get('state')!)['schemaVersion'], 99);
    if (old == null) {
      await box.delete('state');
    } else {
      await box.put('state', old);
    }
    await box.close();
    store = await HiveRecitationStore.open(directory.path);
  });
}
