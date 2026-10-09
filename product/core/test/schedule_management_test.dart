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
        RecitationService(store, clock: () => now, id: () => 'id-${id++}');
  });
  Future<Plan> arrange({int count = 6, DateTime? end, int quota = 1}) async {
    final article = await service.importPreparedArticle(ImportedText(
        title: '课文',
        segments: List.generate(count, (i) => '第${i + 1}段学不可以已。')));
    return service.createPlan(
        name: '计划',
        versionIds: [article.currentVersionId],
        start: DateTime(2026, 10, 8),
        end: end ?? DateTime(2026, 10, 31),
        quota: quota,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
  }

  Future<void> pass(Task task, String id) async =>
      service.submitFinalTranscript(
          taskId: task.id,
          attemptId: id,
          transcript: (await store.getSegment(task.segmentId))!.text,
          isFinal: true);
  test('剩余新背按原文顺序排期，跨月截止与已完成成绩复习原日期保留', () async {
    final plan = await arrange(end: DateTime(2026, 11, 8));
    final original = await store.tasks();
    await pass(original.first, 'passed');
    await service.postponeTasks([original[1].id], DateTime(2026, 11, 2));
    final reviews =
        (await store.tasks()).where((t) => t.kind == TaskKind.review).toList();
    final attempt = (await store.getAttempt('passed'))!;
    final preview = await service.previewRemainingSchedule(
        planId: plan.id,
        start: DateTime(2026, 10, 30),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(preview.affectedCount, 5);
    expect(preview.finishDate, DateTime(2026, 11, 1));
    expect(preview.changes.map((c) => c.before.id).first, original[1].id);
    final before = store.snapshot();
    expect(store.snapshot(), before);
    await service.applySchedulePreview(preview);
    expect(
        (await store.getTask(original.first.id))!.status, TaskStatus.completed);
    expect(
        (await store.getTask(original[1].id))!.dueDate, DateTime(2026, 10, 30));
    expect((await store.getTask(original[1].id))!.scheduledDate,
        DateTime(2026, 10, 9));
    for (final review in reviews)
      expect((await store.getTask(review.id))!.dueDate, review.dueDate);
    expect((await store.getAttempt('passed'))!.createdAt, attempt.createdAt);
    expect((await store.getPlan(plan.id))!.dailyNewQuota, 2);
    expect((await store.getPlan(plan.id))!.endDate, plan.endDate);
    final event = (await store.events()).last;
    expect(event.adjustment, ScheduleAdjustment.remainingPlan);
    await expectLater(service.undoPostponement(event.id), throwsStateError);
    final restored = MemoryRecitationStore();
    await BackupService(restored, profileId: 'target').restore(
        BackupService(store, profileId: 'source').export(),
        saveCurrentArchive: (_) async {});
    expect((await restored.events()).last.adjustment,
        ScheduleAdjustment.remainingPlan);
  });
  test('不够学习日明确预览不可保存，不改截止日和其他档案', () async {
    final plan = await arrange();
    final before = store.snapshot();
    final preview = await service.previewRemainingSchedule(
        planId: plan.id,
        start: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(preview.fits, isFalse);
    expect(preview.requiredDays, 6);
    expect(preview.availableDays, 1);
    await expectLater(service.applySchedulePreview(preview), throwsStateError);
    expect(store.snapshot(), before);
    await expectLater(
        service.previewRemainingSchedule(
            planId: plan.id,
            start: DateTime(2026, 10, 7),
            quota: 1,
            weekdays: {1}),
        throwsArgumentError);
    await expectLater(
        service.previewRemainingSchedule(
            planId: plan.id,
            start: DateTime(2026, 10, 8),
            quota: 0,
            weekdays: {}),
        throwsArgumentError);
  });
  test('预览过期、完成、改名、暂停和再次预览保存均原子拒绝', () async {
    final plan = await arrange();
    Future<ScheduleChangePreview> preview() => service.previewRemainingSchedule(
        planId: plan.id,
        start: DateTime(2026, 10, 9),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    var draft = await preview();
    await service.updatePlan(plan.copyWith(name: '更新名称'));
    final before = store.snapshot();
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    expect(store.snapshot(), before);
    draft = await preview();
    await pass((await store.tasks()).first, 'pass');
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    draft = await preview();
    await service.setPlanPaused(plan.id, true);
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    await expectLater(preview(), throwsStateError);
    await service.setPlanPaused(plan.id, false);
    draft = await preview();
    now = DateTime.utc(2026, 10, 9, 4);
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    draft = await preview();
    await service.applySchedulePreview(draft);
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
  });
  test('相同日期 ABA 再次调整使旧预览失效；并发提交只成功一次', () async {
    final plan = await arrange();
    final task = (await store.tasks()).first;
    final draft = await service.previewRemainingSchedule(
        planId: plan.id,
        start: DateTime(2026, 10, 9),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    await service.postponeTasks([task.id], DateTime(2026, 10, 12));
    await service.undoPostponement((await store.events()).last.id);
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    final current = await service.previewRemainingSchedule(
        planId: plan.id,
        start: DateTime(2026, 10, 9),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final results = await Future.wait(List.generate(2, (_) async {
      try {
        await service.applySchedulePreview(current);
        return true;
      } on StateError {
        return false;
      }
    }));
    expect(results.where((v) => v), hasLength(1));
  });
  test('积压复习不合并不跳过，同段分天，已有复习占每日配额', () async {
    await arrange(count: 2, quota: 2);
    final tasks = await store.tasks();
    await pass(tasks[0], 'a');
    await pass(tasks[1], 'b');
    now = DateTime.utc(2026, 10, 16, 4);
    final before = store.snapshot();
    final due = (await store.tasks())
        .where((t) =>
            t.kind == TaskKind.review &&
            t.dueDate.isBefore(DateTime(2026, 10, 16)))
        .toList();
    expect(due, hasLength(6));
    final preview = await service.previewReviewBacklog(
        start: DateTime(2026, 10, 16),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(preview.changes, hasLength(6));
    final pairs =
        preview.changes.map((c) => '${c.date}:${c.before.segmentId}').toSet();
    expect(pairs, hasLength(6));
    expect(store.snapshot(), before);
    await service.applySchedulePreview(preview);
    final after = await store.tasks();
    expect(after, hasLength(12));
    expect(
        after.where((t) =>
            t.kind == TaskKind.review && t.status == TaskStatus.completed),
        isEmpty);
    expect(after.where((t) => t.status == TaskStatus.completed), hasLength(2));
    for (final day in preview.changes.map((c) => c.date).toSet())
      expect(
          after
              .where((t) =>
                  t.kind == TaskKind.review &&
                  t.status == TaskStatus.pending &&
                  t.dueDate == day)
              .length,
          lessThanOrEqualTo(2));
    final report = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 16),
        asOf: DateTime(2026, 10, 16),
        events: await store.events(),
        localDate: eventLocalTime);
    expect(report.completedTasks, 2);
    expect(report.newMasteredSegments, 2);
    expect(
        (await store.attemptsForSegment(tasks.first.segmentId)), hasLength(1));
  });
  test('积压排期避开未来同段复习及满配额日期，暂停计划不参与', () async {
    final plan = await arrange(count: 1);
    final task = (await store.tasks()).single;
    await pass(task, 'first');
    now = DateTime.utc(2026, 10, 15, 4);
    final draft = await service.previewReviewBacklog(
        start: DateTime(2026, 10, 15),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(draft.affectedCount, 2);
    expect(draft.changes.first.date,
        DateTime(2026, 10, 16)); // October 15 already has the 7-day review.
    expect(draft.changes.last.date, DateTime(2026, 10, 17));
    await service.setPlanPaused(plan.id, true);
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    await expectLater(
        service.previewReviewBacklog(
            start: DateTime(2026, 10, 15),
            quota: 1,
            weekdays: {1, 2, 3, 4, 5, 6, 7}),
        throwsStateError);
  });
  test('积压预览后新增或恢复其他计划使工作量过期，保存原子拒绝', () async {
    await arrange(count: 1);
    await pass((await store.tasks()).single, 'pass');
    now = DateTime.utc(2026, 10, 16, 4);
    Future<ScheduleChangePreview> preview() => service.previewReviewBacklog(
        start: DateTime(2026, 10, 16),
        quota: 2,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    var draft = await preview();
    final extra = await arrange(count: 1);
    var current = store.snapshot();
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    expect(store.snapshot(), current);
    await service.setPlanPaused(extra.id, true);
    draft = await preview();
    await service.setPlanPaused(extra.id, false);
    current = store.snapshot();
    await expectLater(service.applySchedulePreview(draft), throwsStateError);
    expect(store.snapshot(), current);
  });
}
