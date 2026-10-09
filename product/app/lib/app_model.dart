import 'package:flutter/foundation.dart';
import 'package:recitation_core/recitation_core.dart';

import 'reminders.dart';

class AppModel extends ChangeNotifier {
  AppModel(
    this.store, {
    PreferencesStore? preferencesStore,
    ReminderProvider? reminderProvider,
    DateTime Function()? clock,
    LocalSnapshotRepository? snapshots,
  }) : snapshots =
           snapshots ?? (store is HiveRecitationStore ? store.snapshots : null),
       clock = clock ?? DateTime.now,
       service = RecitationService(store, clock: clock),
       preferencesStore = preferencesStore ?? MemoryPreferencesStore(),
       reminderProvider = reminderProvider ?? UnavailableReminderProvider();
  final MemoryRecitationStore store;
  final RecitationService service;
  final DateTime Function() clock;
  final PreferencesStore preferencesStore;
  final LocalSnapshotRepository? snapshots;
  String? get snapshotError => store is HiveRecitationStore
      ? (store as HiveRecitationStore).snapshotError
      : null;
  final ReminderProvider reminderProvider;
  ReminderPreferences preferences = const ReminderPreferences();
  ReminderPermission reminderPermission = ReminderPermission.unavailable;
  String? reminderError;
  String? preferencesError;
  Future<void>? _preferencesLoaded;
  Future<void> _settingsTail = Future.value();
  Future<void> _reminderTail = Future.value();

  Future<void> initializePreferences() => _preferencesLoaded ??= () async {
    try {
      preferences = await preferencesStore.read();
      if (preferences.firstOpenedAt == null) {
        preferences = preferences.copyWith(firstOpenedAt: clock().toUtc());
        await preferencesStore.write(preferences);
      }
    } catch (_) {
      preferencesError = '提醒设置读取失败，原学习档案未修改。请重新保存提醒设置。';
    }
  }();

  Future<void> syncReminders() {
    final operation = _reminderTail.then((_) async {
      try {
        reminderPermission = await reminderProvider.permission();
        await reminderProvider.replace(
          reminderPermission == ReminderPermission.allowed
              ? buildReminders(
                  preferences: preferences,
                  now: clock().toUtc(),
                  tasks: tasks,
                  plans: plans,
                  hasContent: articles.isNotEmpty || attempts.isNotEmpty,
                )
              : [],
        );
        reminderError = null;
      } catch (_) {
        reminderError = '提醒更新失败，请在提醒设置中重试。学习记录已保存。';
      }
    });
    _reminderTail = operation;
    return operation;
  }

  Future<void> savePreferences({
    bool? studyEnabled,
    bool? backupEnabled,
    int? hour,
    int? minute,
    bool exported = false,
    int? weeklyGoalDays,
  }) {
    final operation = _settingsTail.then((_) async {
      await initializePreferences();
      if (weeklyGoalDays != null &&
          (weeklyGoalDays < 1 || weeklyGoalDays > 7)) {
        throw const FormatException('每周目标应为1至7天');
      }
      final next = preferences.copyWith(
        studyEnabled: studyEnabled,
        backupEnabled: backupEnabled,
        hour: hour,
        minute: minute,
        weeklyGoalDays: weeklyGoalDays,
        lastExportAt: exported ? clock().toUtc() : null,
        firstOpenedAt: preferences.firstOpenedAt ?? clock().toUtc(),
      );
      await preferencesStore.write(next);
      preferences = next;
      preferencesError = null;
      await syncReminders();
      notifyListeners();
    });
    _settingsTail = operation.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return operation;
  }

  bool get backupDue {
    final base = preferences.lastExportAt ?? preferences.firstOpenedAt;
    final localBase = base == null ? null : localTime(base, 'Asia/Shanghai');
    return (articles.isNotEmpty || attempts.isNotEmpty) &&
        base != null &&
        !today.isBefore(
          DateTime(localBase!.year, localBase.month, localBase.day + 7),
        );
  }

  List<Article> articles = [];
  List<Plan> plans = [];
  List<Task> tasks = [];
  List<LearningEvent> events = [];
  Map<String, Segment> segments = {};
  Map<String, String> articleNames = {};
  Map<String, String> segmentArticleIds = {};
  List<Attempt> attempts = [];
  DateTime get today {
    final local = localTime(clock().toUtc(), 'Asia/Shanghai');
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> reload() async {
    await initializePreferences();
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
    await syncReminders();
    notifyListeners();
  }

  List<Task> get overdueReviews => dueTasks
      .where((t) => t.kind == TaskKind.review && t.dueDate.isBefore(today))
      .toList();

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
      return '${latestReschedule(task.id)?.adjustment == null ? '已延期' : '已调整'} · 原定${task.scheduledDate.month}月${task.scheduledDate.day}日';
    }
    return '待完成';
  }

  int pendingOn(DateTime date, {Set<String> excluding = const {}}) => tasks
      .where(
        (t) =>
            t.dueDate == date &&
            t.status == TaskStatus.pending &&
            !excluding.contains(t.id) &&
            plans.any((p) => p.id == t.planId && !p.paused),
      )
      .length;

  bool canUndoPostponement(LearningEvent event) {
    if (event.previousDueDate == null ||
        event.undoOf != null ||
        event.adjustment != null) {
      return false;
    }
    final matches = tasks.where((t) => t.id == event.taskId);
    if (matches.isEmpty ||
        matches.first.status != TaskStatus.pending ||
        matches.first.dueDate != event.dueDate ||
        !plans.any((p) => p.id == matches.first.planId && !p.paused)) {
      return false;
    }
    return latestReschedule(event.taskId!)?.id == event.id;
  }

  LearningEvent? latestReschedule(String taskId) {
    LearningEvent? latest;
    for (final e in events) {
      if (e.taskId == taskId &&
          e.type == LearningEventType.taskRescheduled &&
          (latest == null || !e.occurredAt.isBefore(latest.occurredAt))) {
        latest = e;
      }
    }
    return latest;
  }

  int get postponedToday => tasks
      .where(
        (task) =>
            task.status == TaskStatus.pending &&
            task.dueDate.isAfter(today) &&
            !task.scheduledDate.isAfter(today) &&
            events.any((event) {
              final local = eventLocalTime(event);
              return event.type == LearningEventType.taskRescheduled &&
                  event.taskId == task.id &&
                  event.dueDate == task.dueDate &&
                  event.undoOf == null &&
                  event.adjustment == null &&
                  latestReschedule(task.id)?.id == event.id &&
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
  LearningGrowth get growth => buildLearningGrowth(
    events: events,
    today: today,
    localDate: eventLocalTime,
  );
}
