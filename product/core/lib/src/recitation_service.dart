import 'dart:math';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'assessment.dart';
import 'content.dart';
import 'events.dart';
import 'models.dart';
import 'ports.dart';
import 'review_scheduler.dart';
import 'scheduler.dart';
import 'normalization.dart';
import 'schedule_management.dart';

bool _zonesInitialized = false;
DateTime eventLocalTime(LearningEvent event) =>
    localTime(event.occurredAt, event.timeZone);
DateTime localTime(DateTime instant, String zone) {
  if (!_zonesInitialized) {
    tzdata.initializeTimeZones();
    _zonesInitialized = true;
  }
  return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(zone));
}

String createLocalId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The same application service can be consumed by Flutter pages or CLI tests.
class RecitationService {
  RecitationService(this.store,
      {String Function()? id, DateTime Function()? clock})
      : _id = id ?? createLocalId,
        _clock = clock ?? (() => DateTime.now().toUtc());
  final RecitationStore store;
  final String Function() _id;
  final DateTime Function() _clock;

  Future<Article> importArticle(
      {required String title, required String text, String? author}) async {
    final draft = previewImportedText(title: title, text: text, author: author);
    return importPreparedArticle(draft);
  }

  Future<Article> importPreparedArticle(ImportedText draft) async {
    if (draft.title.trim().isEmpty) {
      throw const FormatException('文章标题不能为空');
    }
    final articleId = _id();
    final versionId = _id();
    final now = _clock().toUtc();
    final article = Article(
        id: articleId,
        title: draft.title.trim(),
        author:
            draft.author?.trim().isEmpty == true ? null : draft.author?.trim(),
        currentVersionId: versionId,
        createdAt: now,
        updatedAt: now);
    final version = ArticleVersion(
        id: versionId,
        articleId: articleId,
        version: 1,
        segments: buildSegments(versionId: versionId, texts: draft.segments),
        createdAt: now);
    await store
        .writeBatch(RecitationBatch(articles: [article], versions: [version]));
    return article;
  }

  Future<Plan> createPlan(
      {required String name,
      required List<String> versionIds,
      required DateTime start,
      required DateTime end,
      required int quota,
      required Set<int> weekdays,
      String timeZone = 'Asia/Shanghai',
      AssessmentRule rule = const AssessmentRule()}) async {
    if (name.trim().isEmpty || versionIds.isEmpty)
      throw ArgumentError('请填写计划名称并选择文章');
    localTime(_clock(), timeZone); // Fail early for an unsupported time zone.
    final segments = <String>[];
    for (final id in versionIds.toSet()) {
      final v = await store.getArticleVersion(id);
      if (v == null) throw StateError('文章版本不存在');
      segments.addAll(v.segments.map((s) => s.id));
    }
    final plan = Plan(
        id: _id(),
        name: name.trim(),
        segmentIds: segments,
        startDate: start,
        endDate: end,
        dailyNewQuota: quota,
        weekdays: weekdays,
        rule: rule,
        timeZone: timeZone);
    if (!previewPlan(plan).fits) throw ArgumentError('当前日期、学习日和配额无法完成目标');
    final tasks = createNewLearningTasks(plan);
    final due = tasks.map((t) => _dueEvent(t, plan.timeZone)).toList();
    await store
        .writeBatch(RecitationBatch(plans: [plan], tasks: tasks, events: due));
    return plan;
  }

  Future<void> setPlanPaused(String planId, bool paused) async {
    final plan = await store.getPlan(planId);
    if (plan == null) throw StateError('计划不存在');
    await store.savePlan(Plan(
      id: plan.id,
      name: plan.name,
      segmentIds: plan.segmentIds,
      startDate: plan.startDate,
      endDate: plan.endDate,
      dailyNewQuota: plan.dailyNewQuota,
      weekdays: plan.weekdays,
      rule: plan.rule,
      timeZone: plan.timeZone,
      paused: paused,
    ));
  }

  Future<void> updatePlan(Plan plan) async {
    final current = await store.getPlan(plan.id);
    if (current == null) throw StateError('计划不存在');
    if (plan.name.trim().isEmpty) throw ArgumentError('计划名称不能为空');
    if (plan.rule.accuracyThreshold < 0 ||
        plan.rule.accuracyThreshold > 100 ||
        plan.rule.coverageThreshold < 0 ||
        plan.rule.coverageThreshold > 100) {
      throw ArgumentError('考核阈值必须在0至100之间');
    }
    // Settings edits must not silently detach existing tasks from their schedule.
    await store.savePlan(Plan(
      id: current.id,
      name: plan.name.trim(),
      segmentIds: current.segmentIds,
      startDate: current.startDate,
      endDate: current.endDate,
      dailyNewQuota: current.dailyNewQuota,
      weekdays: current.weekdays,
      rule: plan.rule,
      timeZone: current.timeZone,
      paused: current.paused,
    ));
  }

  Future<void> deletePlan(String planId) async {
    if (await store.getPlan(planId) == null) throw StateError('计划不存在');
    await store.deletePlan(planId);
  }

  Future<int> postponeTasksUntilTomorrow(List<String> taskIds) async {
    final tasks = <Task>[];
    final events = <LearningEvent>[];
    final expected = <String, DateTime>{};
    final now = _clock().toUtc();
    for (final id in taskIds.toSet()) {
      final task = await store.getTask(id);
      if (task == null || task.status != TaskStatus.pending) {
        throw StateError('只能延后未完成的任务，请刷新后重试');
      }
      final plan = await store.getPlan(task.planId);
      if (plan == null || plan.paused) throw StateError('计划不存在或已暂停');
      final local = localTime(now, plan.timeZone);
      final today = DateTime(local.year, local.month, local.day);
      if (task.dueDate.isAfter(today)) throw StateError('只能延后今日队列中的任务');
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      expected[id] = task.dueDate;
      tasks.add(task.copyWith(dueDate: tomorrow));
      events.add(LearningEvent(
          id: _id(),
          type: LearningEventType.taskRescheduled,
          occurredAt: now,
          timeZone: plan.timeZone,
          durationSeconds: 0,
          taskId: id,
          segmentId: task.segmentId,
          taskKind: task.kind,
          previousDueDate: task.dueDate,
          dueDate: tomorrow));
    }
    if (tasks.isEmpty) return 0;
    await store.writeBatch(RecitationBatch(
        tasks: tasks,
        events: events,
        expectedTaskDueDates: expected,
        reschedulesPendingTasks: true));
    return tasks.length;
  }

  Future<int> postponeTasks(List<String> taskIds, DateTime target) async {
    final date = DateTime(target.year, target.month, target.day);
    final now = _clock().toUtc();
    final updates = <Task>[];
    final changes = <LearningEvent>[];
    final expected = <String, DateTime>{};
    for (final id in taskIds.toSet()) {
      final task = await store.getTask(id);
      if (task == null || task.status != TaskStatus.pending)
        throw StateError('只能延后未完成任务');
      final plan = await store.getPlan(task.planId);
      if (plan == null || plan.paused) throw StateError('计划不存在或已暂停');
      final local = localTime(now, plan.timeZone);
      final today = DateTime(local.year, local.month, local.day);
      if (!date.isAfter(today) || !date.isAfter(task.dueDate)) {
        throw ArgumentError('延期日期必须晚于今天和当前任务日期');
      }
      expected[id] = task.dueDate;
      updates.add(task.copyWith(dueDate: date));
      changes.add(LearningEvent(
          id: _id(),
          type: LearningEventType.taskRescheduled,
          occurredAt: now,
          timeZone: plan.timeZone,
          durationSeconds: 0,
          taskId: id,
          segmentId: task.segmentId,
          taskKind: task.kind,
          dueDate: date,
          previousDueDate: task.dueDate));
    }
    if (updates.isEmpty) return 0;
    await store.writeBatch(RecitationBatch(
        tasks: updates,
        events: changes,
        expectedTaskDueDates: expected,
        reschedulesPendingTasks: true));
    return updates.length;
  }

  Future<void> undoPostponement(String eventId) async {
    final events = await store.events();
    LearningEvent? original;
    for (final event in events) {
      if (event.id == eventId) original = event;
    }
    if (original == null ||
        original.type != LearningEventType.taskRescheduled ||
        original.previousDueDate == null ||
        original.taskId == null ||
        original.undoOf != null ||
        original.adjustment != null) {
      throw StateError('这条延期记录不能撤销');
    }
    LearningEvent? latest;
    for (final event in events) {
      if (event.taskId == original.taskId &&
          event.type == LearningEventType.taskRescheduled &&
          (latest == null || !event.occurredAt.isBefore(latest.occurredAt)))
        latest = event;
    }
    if (latest?.id != original.id) throw StateError('任务已经再次调整，不能撤销旧记录');
    final task = await store.getTask(original.taskId!);
    if (task == null ||
        task.status != TaskStatus.pending ||
        task.dueDate != original.dueDate) {
      throw StateError('任务已完成或排期已变化，不能撤销');
    }
    final plan = await store.getPlan(task.planId);
    if (plan == null || plan.paused) throw StateError('计划不存在或已暂停');
    final restored = task.copyWith(dueDate: original.previousDueDate);
    await store.writeBatch(RecitationBatch(tasks: [
      restored
    ], events: [
      LearningEvent(
          id: _id(),
          type: LearningEventType.taskRescheduled,
          occurredAt: _clock().toUtc(),
          timeZone: plan.timeZone,
          durationSeconds: 0,
          taskId: task.id,
          segmentId: task.segmentId,
          taskKind: task.kind,
          dueDate: restored.dueDate,
          previousDueDate: task.dueDate,
          undoOf: original.id)
    ], expectedTaskDueDates: {
      task.id: task.dueDate
    }, expectedRescheduleIds: {
      task.id: original.id
    }, reschedulesPendingTasks: true));
  }

  Future<ScheduleChangePreview> previewRemainingSchedule(
      {required String planId,
      required DateTime start,
      required int quota,
      required Set<int> weekdays}) async {
    final plan = await store.getPlan(planId);
    if (plan == null) throw StateError('计划不存在');
    final today = localTime(_clock(), plan.timeZone);
    return planRemainingSchedule(
            plan: plan,
            tasks: await store.tasks(),
            today: today,
            start: start,
            quota: quota,
            weekdays: weekdays)
        .withEvents(await store.events());
  }

  Future<ScheduleChangePreview> previewReviewBacklog(
      {required DateTime start,
      required int quota,
      required Set<int> weekdays}) async {
    final plans = await store.plans();
    if (plans.any((p) => !p.paused && p.timeZone != 'Asia/Shanghai'))
      throw StateError('请分别处理不同时区的计划');
    return planReviewBacklog(
            plans: plans,
            tasks: await store.tasks(),
            today: localTime(_clock(), 'Asia/Shanghai'),
            start: start,
            quota: quota,
            weekdays: weekdays)
        .withEvents(await store.events());
  }

  Future<int> applySchedulePreview(ScheduleChangePreview preview) async {
    if (!preview.fits) throw StateError('当前配额和学习日无法在原截止日前完成，请重新预览');
    final now = _clock().toUtc();
    for (final p in preview.plans.values) {
      if (scheduleDay(localTime(now, p.timeZone)) != preview.day)
        throw StateError('日期已变化，请重新预览');
    }
    await store.writeBatch(RecitationBatch(
      plans: preview.updatedPlan == null ? [] : [preview.updatedPlan!],
      tasks: preview.changes.map((c) => c.after).toList(),
      events: preview.changes
          .map((c) => LearningEvent(
              id: _id(),
              type: LearningEventType.taskRescheduled,
              occurredAt: now,
              timeZone: preview.plans[c.before.planId]!.timeZone,
              durationSeconds: 0,
              taskId: c.before.id,
              segmentId: c.before.segmentId,
              taskKind: c.before.kind,
              previousDueDate: c.before.dueDate,
              dueDate: c.date,
              adjustment: preview.adjustment))
          .toList(),
      expectedTaskDueDates: {
        for (final c in preview.changes) c.before.id: c.before.dueDate
      },
      expectedPlans: preview.plans,
      expectedPlanTasks: preview.tasks,
      expectedActivePlanIds:
          preview.adjustment == ScheduleAdjustment.reviewBacklog
              ? preview.plans.keys.toSet()
              : null,
      expectedRescheduleIds: preview.latestEvents,
      reschedulesPendingTasks: true,
    ));
    return preview.changes.length;
  }

  Future<Article> updateArticle({
    required Article article,
    required String title,
    String? author,
    required List<String> segments,
  }) async {
    if (title.trim().isEmpty) throw const FormatException('文章标题不能为空');
    if (segments.any((s) => normalizeForAssessment(s).isEmpty)) {
      throw const FormatException('每节都需要有效正文');
    }
    final now = _clock().toUtc();
    final versionId = _id();
    final current = await store.getArticle(article.id);
    if (current == null) throw StateError('文章不存在');
    final version = ArticleVersion(
      id: versionId,
      articleId: article.id,
      version:
          ((await store.getArticleVersion(current.currentVersionId))?.version ??
                  0) +
              1,
      segments: buildSegments(versionId: versionId, texts: segments),
      createdAt: now,
      changeNote: '编辑文章',
    );
    final updated = Article(
      id: article.id,
      title: title.trim(),
      author: author?.trim().isEmpty == true ? null : author?.trim(),
      currentVersionId: versionId,
      createdAt: current.createdAt,
      updatedAt: now,
    );
    await store
        .writeBatch(RecitationBatch(articles: [updated], versions: [version]));
    return updated;
  }

  Future<void> deleteArticle(String articleId) async {
    final article = await store.getArticle(articleId);
    if (article == null) throw StateError('文章不存在');
    final plans = await store.plans();
    for (final plan in plans) {
      for (final id in plan.segmentIds) {
        final segment = await store.getSegment(id);
        final version = segment == null
            ? null
            : await store.getArticleVersion(segment.versionId);
        if (version?.articleId == articleId) {
          throw StateError('这篇文章已加入学习计划，请先删除相关计划');
        }
      }
    }
    await store.deleteArticle(articleId);
  }

  Future<Attempt> submitFinalTranscript(
      {required String taskId,
      required String attemptId,
      required String transcript,
      required bool isFinal,
      bool assisted = false,
      bool hasUnresolvedDoubt = false,
      bool technicalFailure = false,
      bool allowEarly = false,
      int activeSeconds = 0}) async {
    if (!isFinal) throw StateError('临时识别结果不能提交考核');
    if (attemptId.trim().isEmpty || activeSeconds < 0)
      throw ArgumentError('会话ID与学习时长无效');
    final previous = await store.getAttempt(attemptId);
    if (previous != null) {
      if (previous.taskId != taskId) throw StateError('会话ID已用于其他任务');
      if (previous.status != AttemptStatus.processing) return previous;
    }
    final task = await store.getTask(taskId);
    if (task == null || task.status == TaskStatus.skipped)
      throw StateError('任务不存在或已取消');
    final plan = await store.getPlan(task.planId);
    if (plan == null || plan.paused) throw StateError('计划不存在或已暂停');
    final day = localTime(_clock(), plan.timeZone);
    final today = DateTime(day.year, day.month, day.day);
    if (task.dueDate.isAfter(today)) {
      if (!allowEarly ||
          task.kind != TaskKind.newLearning ||
          task.dueDate
              .isAfter(DateTime(today.year, today.month, today.day + 2))) {
        throw StateError('仅支持提前完成明天或后天的新背任务，复习请在到期后进行');
      }
      final activePlans = {
        for (final p in await store.plans())
          if (!p.paused) p.id: p
      };
      for (final pending in await store.tasks()) {
        final active = activePlans[pending.planId];
        if (active == null || pending.status != TaskStatus.pending) continue;
        final local = localTime(_clock(), active.timeZone);
        if (!pending.dueDate
            .isAfter(DateTime(local.year, local.month, local.day))) {
          throw StateError('请先完成今日队列，再提前学习');
        }
      }
    }
    // Lookup by identity, never infer identity from displayed paragraph order.
    final segment = await store.getSegment(task.segmentId);
    if (segment == null) throw StateError('任务对应的原文版本不存在');
    final decision = assessTranscript(
        segment: segment,
        transcript: transcript,
        rule: plan.rule,
        wasAssisted: assisted,
        hasUnresolvedDoubt: hasUnresolvedDoubt,
        technicalFailure: technicalFailure);
    final now = _clock().toUtc();
    final attempt = Attempt(
        id: attemptId,
        taskId: task.id,
        segmentId: task.segmentId,
        source: decision.source,
        status: decision.status,
        createdAt: now,
        transcript: transcript,
        score: decision.score,
        rule: plan.rule);
    final events = <LearningEvent>[
      LearningEvent(
          id: 'attempt:$attemptId',
          type: LearningEventType.attempt,
          occurredAt: now,
          timeZone: plan.timeZone,
          durationSeconds: activeSeconds,
          taskId: task.id,
          segmentId: task.segmentId,
          attemptId: attemptId,
          taskKind: task.kind,
          source: attempt.source,
          status: attempt.status),
    ];
    final tasks = <Task>[];
    if (decision.countsAsAutomaticCompletion &&
        task.status != TaskStatus.completed) {
      tasks.add(task.copyWith(status: TaskStatus.completed));
      events.add(LearningEvent(
          id: 'completed:${task.id}',
          type: LearningEventType.taskCompleted,
          occurredAt: now,
          timeZone: plan.timeZone,
          durationSeconds: 0,
          taskId: task.id,
          segmentId: task.segmentId));
      if (task.kind == TaskKind.newLearning) {
        final reviews = createReviewTasks(
            plan: plan,
            segmentId: task.segmentId,
            passedAt: localTime(now, plan.timeZone));
        tasks.addAll(reviews);
        events.addAll(reviews.map((t) => _dueEvent(t, plan.timeZone)));
      }
    }
    await store.writeBatch(RecitationBatch(
        attempts: [attempt],
        tasks: tasks,
        events: events,
        expectedTaskDueDates: {task.id: task.dueDate},
        expectedPlans: {plan.id: plan},
        finalizesAttemptId: attemptId));
    return (await store.getAttempt(attemptId))!;
  }

  LearningEvent _dueEvent(Task task, String zone) {
    localTime(_clock(), zone);
    final d = task.dueDate;
    final midnight =
        tz.TZDateTime(tz.getLocation(zone), d.year, d.month, d.day);
    return LearningEvent(
        id: 'due:${task.id}',
        type: LearningEventType.taskDue,
        occurredAt: midnight.toUtc(),
        timeZone: zone,
        durationSeconds: 0,
        taskId: task.id,
        segmentId: task.segmentId,
        taskKind: task.kind);
  }
}
