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

  Future<Attempt> submitFinalTranscript(
      {required String taskId,
      required String attemptId,
      required String transcript,
      required bool isFinal,
      bool assisted = false,
      bool hasUnresolvedDoubt = false,
      bool technicalFailure = false,
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
    if (task.dueDate.isAfter(DateTime(day.year, day.month, day.day))) {
      throw StateError('任务尚未到学习日期');
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
      tasks.add(Task(
          id: task.id,
          planId: task.planId,
          segmentId: task.segmentId,
          kind: task.kind,
          dueDate: task.dueDate,
          status: TaskStatus.completed));
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
