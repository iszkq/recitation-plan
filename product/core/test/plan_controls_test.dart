import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  late MemoryRecitationStore store;
  late RecitationService service;
  setUp(() {
    store = MemoryRecitationStore();
    var id = 0;
    service = RecitationService(store,
        id: () => 'entity-${id++}', clock: () => DateTime.utc(2026, 10, 8, 4));
  });

  test('确认后的节内空行保留，空小节拒绝保存', () async {
    final article = await service.importPreparedArticle(
        const ImportedText(title: '分段课文', segments: ['第一句。\n\n第二句。', '第三句。']));
    final version = (await store.getArticleVersion(article.currentVersionId))!;
    expect(version.segments.length, 2);
    expect(version.segments.first.text, '第一句。\n\n第二句。');
    await expectLater(
        service.importPreparedArticle(
            const ImportedText(title: '无效课文', segments: ['有效内容', ''])),
        throwsFormatException);
    expect(await store.articles(), hasLength(1));
  });

  test('两篇文章按选择顺序进入同一计划，重复选择不重复排期', () async {
    final a = await service.importArticle(title: '甲篇', text: '甲段。');
    final b = await service.importArticle(title: '乙篇', text: '乙段。');
    final plan = await service.createPlan(
        name: '两篇月计划',
        versionIds: [
          b.currentVersionId,
          a.currentVersionId,
          b.currentVersionId
        ],
        start: DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(plan.segmentIds, hasLength(2));
    expect((await store.getSegment(plan.segmentIds.first))!.text, '乙段。');
    expect(await store.tasks(), hasLength(2));
  });

  test('暂停阻止完成任务，继续保留排期和历史', () async {
    final a = await service.importArticle(title: '课文', text: '学不可以已。');
    final plan = await service.createPlan(
        name: '月计划',
        versionIds: [a.currentVersionId],
        start: DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final task = (await store.tasks()).single;
    await service.setPlanPaused(plan.id, true);
    await expectLater(
        service.submitFinalTranscript(
            taskId: task.id,
            attemptId: 'paused',
            transcript: '学不可以已',
            isFinal: true),
        throwsStateError);
    expect(await store.attemptsForSegment(task.segmentId), isEmpty);
    await service.setPlanPaused(plan.id, false);
    final result = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'resumed',
        transcript: '学不可以已',
        isFinal: true);
    expect(result.status, AttemptStatus.passed);
    expect((await store.getTask(task.id))!.dueDate, task.dueDate);
  });

  test('未来任务不得提前考核通过', () async {
    final a = await service.importArticle(title: '课文', text: '学不可以已。');
    await service.createPlan(
        name: '未来计划',
        versionIds: [a.currentVersionId],
        start: DateTime(2026, 10, 9),
        end: DateTime(2026, 10, 31),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final task = (await store.tasks()).single;
    await expectLater(
        service.submitFinalTranscript(
            taskId: task.id,
            attemptId: 'early',
            transcript: '学不可以已',
            isFinal: true),
        throwsStateError);
    expect((await store.getTask(task.id))!.status, TaskStatus.pending);
  });

  test('编辑文章生成新版本并保留文章身份', () async {
    final article = await service.importArticle(title: '旧标题', text: '旧正文。');
    final updated = await service.updateArticle(
      article: article,
      title: '新标题',
      author: '作者',
      segments: const ['新正文。', '第二节。'],
    );
    expect(updated.id, article.id);
    expect(updated.title, '新标题');
    expect(updated.currentVersionId, isNot(article.currentVersionId));
    final version = await store.getArticleVersion(updated.currentVersionId);
    expect(version!.segments, hasLength(2));
    expect(version.segments.first.text, '新正文。');
  });

  test('计划中的文章不能直接删除', () async {
    final article = await service.importArticle(title: '课文', text: '正文。');
    await service.createPlan(
      name: '计划',
      versionIds: [article.currentVersionId],
      start: DateTime(2026, 10, 8),
      end: DateTime(2026, 10, 31),
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    await expectLater(service.deleteArticle(article.id), throwsStateError);
    expect(await store.getArticle(article.id), isNotNull);
  });

  test('删除计划保留已完成任务，编辑计划保留任务', () async {
    final article = await service.importArticle(title: '课文', text: '正文。');
    final plan = await service.createPlan(
      name: '旧计划',
      versionIds: [article.currentVersionId],
      start: DateTime(2026, 10, 8),
      end: DateTime(2026, 10, 31),
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final task = (await store.tasks()).single;
    await service.updatePlan(Plan(
      id: plan.id,
      name: '新计划',
      segmentIds: plan.segmentIds,
      startDate: plan.startDate,
      endDate: plan.endDate,
      dailyNewQuota: plan.dailyNewQuota,
      weekdays: plan.weekdays,
      rule: plan.rule,
      timeZone: plan.timeZone,
    ));
    expect((await store.getPlan(plan.id))!.name, '新计划');
    final result = await service.submitFinalTranscript(
      taskId: task.id,
      attemptId: 'completed',
      transcript: '正文',
      isFinal: true,
    );
    expect(result.status, AttemptStatus.passed);
    await service.deletePlan(plan.id);
    expect(await store.getPlan(plan.id), isNull);
    expect((await store.getTask(task.id))!.status, TaskStatus.completed);
  });
}
