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
  test('自选日期单项延期和撤销保留原排期，成绩与报告不虚增', () async {
    final tasks = await arrange();
    await service.postponeTasks([tasks.first.id], DateTime(2026, 11, 2, 20));
    expect(
        (await store.getTask(tasks.first.id))!.dueDate, DateTime(2026, 11, 2));
    expect((await store.getTask(tasks[1].id))!.dueDate, tasks[1].dueDate);
    final event = (await store.events()).last;
    expect(event.previousDueDate, tasks.first.dueDate);
    final moved = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 8),
        asOf: DateTime(2026, 10, 8),
        events: await store.events(),
        localDate: eventLocalTime);
    expect(moved.dueTasks, 0);
    await service.undoPostponement(event.id);
    final current = (await store.getTask(tasks.first.id))!;
    expect(current.dueDate, tasks.first.dueDate);
    expect(current.scheduledDate, tasks.first.dueDate);
    expect(current.status, TaskStatus.pending);
    final history = await store.events();
    expect(history.last.undoOf, event.id);
    final report = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 8),
        asOf: DateTime(2026, 10, 8),
        events: history,
        localDate: eventLocalTime);
    expect(report.dueTasks, 1);
    expect(report.completedTasks, 0);
    expect(report.newMasteredSegments, 0);
    expect(report.focusMinutes, 0);
    await expectLater(service.undoPostponement(event.id), throwsStateError);
    await expectLater(
        service.undoPostponement(history.last.id), throwsStateError);
  });

  test('整批自选延期失败不部分保存；未来任务必须延到更晚日期', () async {
    final tasks = await arrange();
    final before = store.snapshot();
    await expectLater(
        service.postponeTasks(
            [tasks.first.id, tasks[2].id], DateTime(2026, 10, 10)),
        throwsArgumentError);
    expect(store.snapshot(), before);
    await expectLater(
        service
            .postponeTasks([tasks.first.id, 'missing'], DateTime(2026, 11, 1)),
        throwsStateError);
    expect(store.snapshot(), before);
    await expectLater(
        service.postponeTasks([tasks.first.id], DateTime(2026, 10, 8)),
        throwsArgumentError);
    await service
        .postponeTasks([tasks[2].id, tasks[2].id], DateTime(2026, 11, 1));
    expect((await store.getTask(tasks[2].id))!.scheduledDate, tasks[2].dueDate);
    final event = (await store.events()).last;
    await service.setPlanPaused(tasks.first.planId, true);
    await expectLater(service.undoPostponement(event.id), throwsStateError);
    await expectLater(
        service.postponeTasks([tasks.first.id], DateTime(2026, 11, 1)),
        throwsStateError);
    await service.setPlanPaused(tasks.first.planId, false);
    await pass(tasks.first, 'completed');
    await expectLater(
        service.postponeTasks([tasks.first.id], DateTime(2026, 11, 1)),
        throwsStateError);
  });

  test('相同时间连续延期只允许撤销最近一次，撤销不复活更早记录', () async {
    final tasks = await arrange();
    await service.postponeTasks([tasks.first.id], DateTime(2026, 10, 9));
    final first = (await store.events()).last;
    await service.postponeTasks([tasks.first.id], DateTime(2026, 10, 12));
    final latest = (await store.events()).last;
    await expectLater(service.undoPostponement(first.id), throwsStateError);
    await service.undoPostponement(latest.id);
    expect(
        (await store.getTask(tasks.first.id))!.dueDate, DateTime(2026, 10, 9));
    await expectLater(service.undoPostponement(first.id), throwsStateError);
    await expectLater(
        store.writeBatch(RecitationBatch(
            tasks: [tasks.first],
            expectedTaskDueDates: {tasks.first.id: DateTime(2026, 10, 9)},
            expectedRescheduleIds: {tasks.first.id: first.id},
            reschedulesPendingTasks: true)),
        throwsStateError);
  });

  test('并发撤销只有一次成功，备份恢复保存撤销关系且不伪造通过', () async {
    final tasks = await arrange();
    await service.postponeTasks([tasks.first.id], DateTime(2026, 11, 1));
    final event = (await store.events()).last;
    final results = await Future.wait(List.generate(2, (_) async {
      try {
        await service.undoPostponement(event.id);
        return true;
      } on StateError {
        return false;
      }
    }));
    expect(results.where((v) => v), hasLength(1));
    final restored = MemoryRecitationStore();
    await BackupService(restored, profileId: 'restored').restore(
        BackupService(store, profileId: 'local').export(),
        saveCurrentArchive: (_) async {});
    expect((await restored.events()).where((e) => e.undoOf == event.id),
        hasLength(1));
    expect(
        (await restored.getTask(tasks.first.id))!.dueDate, tasks.first.dueDate);
    expect(await restored.attemptsForSegment(tasks.first.segmentId), isEmpty);
    await expectLater(
        RecitationService(restored, clock: () => now)
            .undoPostponement(event.id),
        throwsStateError);
  });

  test('旧版无来源日期的记录无法撤销，完成后的延期记录无法撤销', () async {
    final tasks = await arrange();
    await store.writeBatch(RecitationBatch(events: [
      LearningEvent(
          id: 'legacy',
          type: LearningEventType.taskRescheduled,
          occurredAt: now,
          timeZone: 'Asia/Shanghai',
          durationSeconds: 0,
          taskId: tasks.first.id,
          dueDate: DateTime(2026, 10, 9))
    ]));
    await expectLater(service.undoPostponement('legacy'), throwsStateError);
    await service.postponeTasks([tasks.first.id], DateTime(2026, 10, 9));
    final event = (await store.events()).last;
    now = DateTime.utc(2026, 10, 9, 4);
    await pass(tasks.first, 'passed-later');
    await expectLater(service.undoPostponement(event.id), throwsStateError);
    expect((await store.getTask(tasks.first.id))!.status, TaskStatus.completed);
  });
}
