import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  late MemoryRecitationStore store;
  late RecitationService service;
  late DateTime now;
  setUp(() {
    store = MemoryRecitationStore();
    now = DateTime.utc(2026, 10, 8, 4);
    var id = 0;
    service =
        RecitationService(store, id: () => 'id-${id++}', clock: () => now);
  });

  Future<List<Task>> arrange({DateTime? start}) async {
    final article = await service.importPreparedArticle(const ImportedText(
        title: '课文', segments: ['学不可以已。', '青取之于蓝。', '冰水为之。', '而寒于水。']));
    await service.createPlan(
        name: '计划',
        versionIds: [article.currentVersionId],
        start: start ?? DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    return store.tasks();
  }

  Future<Attempt> pass(Task task, String id,
          {bool early = false,
          bool assisted = false,
          bool doubt = false}) async =>
      service.submitFinalTranscript(
          taskId: task.id,
          attemptId: id,
          transcript: (await store.getSegment(task.segmentId))!.text,
          isFinal: true,
          allowEarly: early,
          assisted: assisted,
          hasUnresolvedDoubt: doubt,
          activeSeconds: 60);

  test('今日未完成时不能提前，完成后明后天新背通过并从实际日期安排复习', () async {
    final tasks = await arrange();
    await expectLater(pass(tasks[1], 'blocked', early: true), throwsStateError);
    expect(await store.getAttempt('blocked'), isNull);
    await pass(tasks[0], 'today');
    await pass(tasks[1], 'tomorrow', early: true);
    await pass(tasks[2], 'after-tomorrow', early: true);
    expect((await store.getTask(tasks[1].id))!.dueDate, DateTime(2026, 10, 9));
    expect((await store.getTask(tasks[2].id))!.status, TaskStatus.completed);
    final reviews = (await store.tasks()).where(
        (t) => t.kind == TaskKind.review && t.segmentId == tasks[2].segmentId);
    expect(reviews.first.dueDate, DateTime(2026, 10, 9));
    await expectLater(
        pass(tasks[3], 'too-early', early: true), throwsStateError);
    await expectLater(
        pass(reviews.first, 'review-early', early: true), throwsStateError);
    await pass(tasks[2], 'after-tomorrow', early: true);
    expect(
        (await store.events())
            .where((e) => e.type == LearningEventType.taskCompleted),
        hasLength(3));
  });

  test('提前练习、待复核和临时转录不生成完成记录', () async {
    final tasks = await arrange(start: DateTime(2026, 10, 9));
    await pass(tasks[0], 'assisted', early: true, assisted: true);
    await pass(tasks[0], 'doubt', early: true, doubt: true);
    await expectLater(
        service.submitFinalTranscript(
            taskId: tasks[0].id,
            attemptId: 'interim',
            transcript: '学不可以已',
            isFinal: false,
            allowEarly: true),
        throwsStateError);
    expect((await store.getTask(tasks[0].id))!.status, TaskStatus.pending);
    expect(
        (await store.tasks()).where((t) => t.kind == TaskKind.review), isEmpty);
  });

  test('延期合并明天任务，反复延期保留原日期且旧考核不能覆盖新日期', () async {
    final tasks = await arrange();
    expect(
        await service
            .postponeTasksUntilTomorrow([tasks.first.id, tasks.first.id]),
        1);
    expect(await store.tasksForDay(DateTime(2026, 10, 8)), isEmpty);
    expect(await store.tasksForDay(DateTime(2026, 10, 9)), hasLength(2));
    expect((await store.getTask(tasks.first.id))!.scheduledDate,
        DateTime(2026, 10, 8));
    await expectLater(pass(tasks.first, 'not-due'), throwsStateError);
    await expectLater(
        service.postponeTasksUntilTomorrow([tasks.first.id]), throwsStateError);
    now = DateTime.utc(2026, 10, 9, 4);
    await service.postponeTasksUntilTomorrow([tasks.first.id]);
    expect((await store.getTask(tasks.first.id))!.scheduledDate,
        DateTime(2026, 10, 8));
    now = DateTime.utc(2026, 10, 10, 4);
    await pass(tasks.first, 'delayed-pass');
    final completed = (await store.getTask(tasks.first.id))!;
    expect(completed.dueDate, DateTime(2026, 10, 10));
    expect(completed.scheduledDate, DateTime(2026, 10, 8));
    await expectLater(
        service.postponeTasksUntilTomorrow([completed.id]), throwsStateError);
  });

  test('延期到非学习日或跨月，复习与新背同样保留；备份恢复所有日期及历史', () async {
    final tasks = await arrange();
    await pass(tasks.first, 'passed');
    final review =
        (await store.tasks()).firstWhere((t) => t.kind == TaskKind.review);
    now = DateTime.utc(2026, 10, 31, 16); // Shanghai November 1.
    await service.postponeTasksUntilTomorrow([review.id, tasks[1].id]);
    expect((await store.getTask(review.id))!.dueDate, DateTime(2026, 11, 2));
    final restored = MemoryRecitationStore();
    await BackupService(restored, profileId: 'restored').restore(
        BackupService(store, profileId: 'local').export(),
        saveCurrentArchive: (_) async {});
    expect((await restored.getTask(review.id))!.scheduledDate,
        DateTime(2026, 10, 9));
    expect((await restored.getTask(review.id))!.dueDate, DateTime(2026, 11, 2));
    expect(
        (await restored.events())
            .where((e) => e.type == LearningEventType.taskRescheduled),
        hasLength(2));
  });

  test('暂停、无效任务或已完成任务使整批延期无副作用', () async {
    final tasks = await arrange();
    final before = store.snapshot();
    await expectLater(
        service.postponeTasksUntilTomorrow([tasks.first.id, 'missing']),
        throwsStateError);
    expect(store.snapshot(), before);
    await service.setPlanPaused(tasks.first.planId, true);
    await expectLater(
        service.postponeTasksUntilTomorrow([tasks.first.id]), throwsStateError);
    await expectLater(pass(tasks[1], 'paused', early: true), throwsStateError);
  });

  test('并发重复延期只写一次，过期考核事务不能覆盖延期', () async {
    final tasks = await arrange();
    final results = await Future.wait(List.generate(2, (_) async {
      try {
        await service.postponeTasksUntilTomorrow([tasks.first.id]);
        return true;
      } on StateError {
        return false;
      }
    }));
    expect(results.where((v) => v), hasLength(1));
    final before = store.snapshot();
    await expectLater(
        store.writeBatch(RecitationBatch(
          tasks: [tasks.first.copyWith(status: TaskStatus.completed)],
          expectedTaskDueDates: {tasks.first.id: tasks.first.dueDate},
        )),
        throwsStateError);
    expect(store.snapshot(), before);
    expect(
        (await store.events())
            .where((e) => e.type == LearningEventType.taskRescheduled),
        hasLength(1));
  });

  test('跨月提前完成：掌握记在实际月份，到期月份仍算已完成', () async {
    now = DateTime.utc(2026, 10, 31, 4);
    final article = await service.importArticle(title: '课文', text: '学不可以已。');
    await service.createPlan(
        name: '十一月计划',
        versionIds: [article.currentVersionId],
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final task = (await store.tasks()).single;
    await pass(task, 'october', early: true);
    final events = await store.events();
    final october = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 31),
        asOf: DateTime(2026, 10, 31),
        events: events,
        localDate: eventLocalTime);
    expect(october.newMasteredSegments, 1);
    expect(october.dueTasks, 0);
    final november = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 11, 1),
        asOf: DateTime(2026, 11, 1),
        events: events,
        localDate: eventLocalTime);
    expect(november.dueTasks, 2);
    expect(november.completedTasks, 1);
    expect(november.newMasteredSegments, 0);
  });

  test('报告按新到期日记账，提前跨月完成不会丢失，实际掌握只记一次', () async {
    final tasks = await arrange(start: DateTime(2026, 10, 9));
    await pass(tasks.first, 'early', early: true);
    final events = await store.events();
    final today = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 8),
        asOf: DateTime(2026, 10, 8),
        events: events,
        localDate: eventLocalTime);
    expect(today.dueTasks, 0);
    expect(today.newMasteredSegments, 1);
    final tomorrow = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 9),
        asOf: DateTime(2026, 10, 9),
        events: events,
        localDate: eventLocalTime);
    expect(tomorrow.completedTasks, 1);
    expect(tomorrow.checkInDays, 0); // The review is also due on October 9.
    now = DateTime.utc(2026, 10, 10, 4);
    await service.postponeTasksUntilTomorrow([tasks[1].id]);
    final moved = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 10),
        asOf: DateTime(2026, 10, 10),
        events: await store.events(),
        localDate: eventLocalTime);
    expect(
        moved.dueTasks, 2); // October 9 new learning and its first review only.
  });
}
