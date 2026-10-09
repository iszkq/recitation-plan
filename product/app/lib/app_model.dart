import 'package:flutter/foundation.dart';
import 'package:recitation_core/recitation_core.dart';

class AppModel extends ChangeNotifier {
  AppModel(this.store) : service = RecitationService(store);
  final MemoryRecitationStore store;
  final RecitationService service;
  List<Article> articles = [];
  List<Plan> plans = [];
  List<Task> tasks = [];
  List<LearningEvent> events = [];
  Map<String, Segment> segments = {};
  Map<String, String> articleNames = {};
  Map<String, String> segmentArticleIds = {};
  List<Attempt> attempts = [];
  DateTime get today {
    final local = localTime(DateTime.now().toUtc(), 'Asia/Shanghai');
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> reload() async {
    articles = await store.articles();
    plans = await store.plans();
    tasks = await store.tasks();
    events = await store.events();
    attempts = [];
    segments = {};
    articleNames = {};
    segmentArticleIds = {};
    final attemptSegments = <String>{};
    for (final task in tasks) {
      final s = await store.getSegment(task.segmentId);
      if (s != null) segments[s.id] = s;
      if (attemptSegments.add(task.segmentId)) {
        attempts.addAll(await store.attemptsForSegment(task.segmentId));
      }
    }
    for (final article in articles) {
      final v = await store.getArticleVersion(article.currentVersionId);
      if (v != null) {
        for (final s in v.segments) {
          segments[s.id] = s;
          articleNames[s.id] = article.title;
          segmentArticleIds[s.id] = article.id;
        }
      }
    }
    for (final s in segments.values.toList()) {
      if (articleNames.containsKey(s.id)) continue;
      final v = await store.getArticleVersion(s.versionId);
      if (v != null) segmentArticleIds[s.id] = v.articleId;
      for (final a in articles) {
        if (a.id == v?.articleId) articleNames[s.id] = a.title;
      }
    }
    notifyListeners();
  }

  List<Task> get dueTasks =>
      tasks
          .where(
            (t) =>
                !t.dueDate.isAfter(today) &&
                t.status == TaskStatus.pending &&
                plans.any((p) => p.id == t.planId && !p.paused),
          )
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// All tasks scheduled for today, including completed ones. The overview
  /// needs this separate from [dueTasks], which intentionally hides completed
  /// work from the action queue.
  List<Task> get todayTasks =>
      tasks
          .where(
            (t) =>
                t.dueDate.year == today.year &&
                t.dueDate.month == today.month &&
                t.dueDate.day == today.day &&
                plans.any((p) => p.id == t.planId && !p.paused),
          )
          .toList()
        ..sort((a, b) {
          final status = a.status.index.compareTo(b.status.index);
          return status != 0 ? status : a.dueDate.compareTo(b.dueDate);
        });
  String taskTitle(Task t) =>
      '${articleNames[t.segmentId] ?? '文章'} · 第${(segments[t.segmentId]?.order ?? 0) + 1}节';

  bool canStartEarly(Task task) =>
      dueTasks.isEmpty &&
      task.kind == TaskKind.newLearning &&
      task.status == TaskStatus.pending &&
      task.dueDate.isAfter(today) &&
      !task.dueDate.isAfter(DateTime(today.year, today.month, today.day + 2)) &&
      plans.any((p) => p.id == task.planId && !p.paused);

  List<Task> upcomingTasks(int days) {
    final date = DateTime(today.year, today.month, today.day + days);
    return tasks
        .where(
          (t) =>
              t.dueDate == date &&
              t.status != TaskStatus.skipped &&
              plans.any((p) => p.id == t.planId && !p.paused),
        )
        .toList();
  }

  String taskScheduleLabel(Task task) {
    final done = events.where(
      (e) => e.type == LearningEventType.taskCompleted && e.taskId == task.id,
    );
    if (done.isNotEmpty) {
      final local = eventLocalTime(done.first);
      final date = DateTime(local.year, local.month, local.day);
      return '${date.month}月${date.day}日${date.isBefore(task.dueDate) ? '提前完成' : '已完成'}';
    }
    if (task.scheduledDate != task.dueDate) {
      return '已延期 · 原定${task.scheduledDate.month}月${task.scheduledDate.day}日';
    }
    return '待完成';
  }

  int get postponedToday => tasks
      .where(
        (task) =>
            task.status == TaskStatus.pending &&
            task.dueDate == DateTime(today.year, today.month, today.day + 1) &&
            events.any((event) {
              final local = eventLocalTime(event);
              return event.type == LearningEventType.taskRescheduled &&
                  event.taskId == task.id &&
                  event.dueDate == task.dueDate &&
                  DateTime(local.year, local.month, local.day) == today;
            }) &&
            plans.any((p) => p.id == task.planId && !p.paused),
      )
      .length;

  ({int total, int mastered, bool active}) articleProgress(Article article) {
    final ids = segments.values
        .where((s) => s.versionId == article.currentVersionId)
        .map((s) => s.id)
        .toSet();
    final completed = tasks
        .where(
          (t) =>
              t.kind == TaskKind.newLearning &&
              t.status == TaskStatus.completed &&
              ids.contains(t.segmentId),
        )
        .map((t) => t.segmentId)
        .toSet();
    return (
      total: ids.length,
      mastered: completed.length,
      active: plans.any(
        (p) =>
            !p.paused &&
            p.segmentIds.any((id) => segmentArticleIds[id] == article.id),
      ),
    );
  }

  LearningReport report(ReportPeriod period, DateTime anchor) => buildReport(
    period: period,
    anchor: anchor,
    asOf: today,
    events: events,
    localDate: eventLocalTime,
  );
}
