import 'models.dart';
import 'events.dart';
import 'scheduler.dart';

DateTime scheduleDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class TaskDateChange {
  const TaskDateChange(this.before, this.date);
  final Task before;
  final DateTime date;
  Task get after => before.copyWith(dueDate: date);
}

class ScheduleChangePreview {
  ScheduleChangePreview(
      {required this.day,
      required this.adjustment,
      required Map<String, Plan> plans,
      required Map<String, List<Task>> tasks,
      required List<TaskDateChange> changes,
      required this.affectedCount,
      this.updatedPlan,
      this.fits = true,
      this.finishDate,
      this.requiredDays = 0,
      this.availableDays = 0,
      Map<String, String?> latestEvents = const {}})
      : plans = Map.unmodifiable(plans),
        tasks = Map.unmodifiable(tasks.map(
            (id, values) => MapEntry(id, List<Task>.unmodifiable(values)))),
        changes = List.unmodifiable(changes),
        latestEvents = Map.unmodifiable(latestEvents);
  final DateTime day;
  final ScheduleAdjustment adjustment;
  final Map<String, Plan> plans;
  final Map<String, List<Task>> tasks;
  final List<TaskDateChange> changes;
  final Map<String, String?> latestEvents;
  final Plan? updatedPlan;
  final bool fits;
  final int affectedCount;
  final DateTime? finishDate;
  final int requiredDays;
  final int availableDays;
  ScheduleChangePreview withEvents(List<LearningEvent> events) {
    final latest = <String, LearningEvent>{};
    for (final e in events) {
      if (e.type != LearningEventType.taskRescheduled || e.taskId == null)
        continue;
      final previous = latest[e.taskId];
      if (previous == null || !e.occurredAt.isBefore(previous.occurredAt))
        latest[e.taskId!] = e;
    }
    return ScheduleChangePreview(
        day: day,
        adjustment: adjustment,
        plans: plans,
        tasks: tasks,
        changes: changes,
        affectedCount: affectedCount,
        updatedPlan: updatedPlan,
        fits: fits,
        finishDate: finishDate,
        requiredDays: requiredDays,
        availableDays: availableDays,
        latestEvents: {
          for (final values in tasks.values)
            for (final t in values) t.id: latest[t.id]?.id
        });
  }
}

ScheduleChangePreview planRemainingSchedule(
    {required Plan plan,
    required List<Task> tasks,
    required DateTime today,
    required DateTime start,
    required int quota,
    required Set<int> weekdays}) {
  final day = scheduleDay(today);
  final first = scheduleDay(start);
  if (plan.paused || plan.deleted) throw StateError('请先恢复计划，再重新排期');
  if (first.isBefore(day) ||
      quota < 1 ||
      quota > 50 ||
      weekdays.isEmpty ||
      weekdays.any((d) => d < 1 || d > 7))
    throw ArgumentError('请设置今天或之后的日期、有效配额及学习日');
  final own = tasks.where((t) => t.planId == plan.id).toList();
  final pending = own
      .where((t) =>
          t.kind == TaskKind.newLearning && t.status == TaskStatus.pending)
      .toList()
    ..sort((a, b) => plan.segmentIds
        .indexOf(a.segmentId)
        .compareTo(plan.segmentIds.indexOf(b.segmentId)));
  if (pending.isEmpty) throw StateError('没有需要重新安排的新背任务');
  final draft = Plan(
      id: plan.id,
      name: plan.name,
      segmentIds: pending.map((t) => t.segmentId).toList(),
      startDate: first,
      endDate: plan.endDate,
      dailyNewQuota: quota,
      weekdays: weekdays,
      rule: plan.rule,
      timeZone: plan.timeZone);
  final preview = previewPlan(draft);
  final dates = createNewLearningTasks(draft);
  return ScheduleChangePreview(
      day: day,
      adjustment: ScheduleAdjustment.remainingPlan,
      plans: {plan.id: plan},
      tasks: {plan.id: own},
      affectedCount: pending.length,
      updatedPlan:
          plan.copyWith(dailyNewQuota: quota, weekdays: Set.of(weekdays)),
      fits: preview.fits,
      finishDate: preview.finishDate,
      requiredDays: preview.requiredDays,
      availableDays: preview.availableDays,
      changes: preview.fits
          ? [
              for (var i = 0; i < pending.length; i++)
                if (pending[i].dueDate != dates[i].dueDate)
                  TaskDateChange(pending[i], dates[i].dueDate)
            ]
          : []);
}

ScheduleChangePreview planReviewBacklog(
    {required List<Plan> plans,
    required List<Task> tasks,
    required DateTime today,
    required DateTime start,
    required int quota,
    required Set<int> weekdays}) {
  final day = scheduleDay(today);
  final first = scheduleDay(start);
  if (first.isBefore(day) ||
      quota < 1 ||
      quota > 50 ||
      weekdays.isEmpty ||
      weekdays.any((d) => d < 1 || d > 7))
    throw ArgumentError('请设置今天或之后的日期、有效配额及学习日');
  final active = {
    for (final p in plans)
      if (!p.paused && !p.deleted) p.id: p
  };
  final own = tasks.where((t) => active.containsKey(t.planId)).toList();
  final overdue = own
      .where((t) =>
          t.kind == TaskKind.review &&
          t.status == TaskStatus.pending &&
          t.dueDate.isBefore(day))
      .toList()
    ..sort((a, b) {
      final date = a.dueDate.compareTo(b.dueDate);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
  if (overdue.isEmpty) throw StateError('没有积压的复习任务');
  final ids = overdue.map((t) => t.id).toSet();
  final occupied = <DateTime, Set<String>>{};
  final counts = <DateTime, int>{};
  for (final t in own.where((t) =>
      t.kind == TaskKind.review &&
      t.status == TaskStatus.pending &&
      !ids.contains(t.id))) {
    occupied.putIfAbsent(t.dueDate, () => {}).add(t.segmentId);
    counts.update(t.dueDate, (v) => v + 1, ifAbsent: () => 1);
  }
  final changes = <TaskDateChange>[];
  final lastForSegment = <String, DateTime>{};
  for (final task in overdue) {
    var date = first;
    final last = lastForSegment[task.segmentId];
    if (last != null && !date.isAfter(last))
      date = DateTime(last.year, last.month, last.day + 1);
    var searched = 0;
    while (!weekdays.contains(date.weekday) ||
        (counts[date] ?? 0) >= quota ||
        (occupied[date]?.contains(task.segmentId) ?? false)) {
      date = DateTime(date.year, date.month, date.day + 1);
      if (++searched > 3660) throw StateError('无法安排积压复习，请增加配额或学习日');
    }
    changes.add(TaskDateChange(task, date));
    counts.update(date, (v) => v + 1, ifAbsent: () => 1);
    occupied.putIfAbsent(date, () => {}).add(task.segmentId);
    lastForSegment[task.segmentId] = date;
  }
  final finish =
      changes.map((c) => c.date).reduce((a, b) => a.isAfter(b) ? a : b);
  return ScheduleChangePreview(
      day: day,
      adjustment: ScheduleAdjustment.reviewBacklog,
      plans: active,
      tasks: {
        for (final id in active.keys)
          id: own.where((t) => t.planId == id).toList()
      },
      changes: changes,
      affectedCount: overdue.length,
      finishDate: finish);
}
