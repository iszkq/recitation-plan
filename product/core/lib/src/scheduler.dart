import 'models.dart';

class SchedulePreview {
  const SchedulePreview({
    required this.fits,
    required this.availableDays,
    required this.requiredDays,
    required this.finishDate,
  });

  final bool fits;
  final int availableDays;
  final int requiredDays;
  final DateTime? finishDate;
}

SchedulePreview previewPlan(Plan plan) {
  final segmentCount = plan.segmentIds.length;
  if (segmentCount == 0 ||
      segmentCount != plan.segmentIds.toSet().length ||
      plan.dailyNewQuota < 1 ||
      plan.weekdays.isEmpty ||
      plan.weekdays.any((d) => d < 1 || d > 7) ||
      plan.endDate.isBefore(plan.startDate)) {
    return const SchedulePreview(
        fits: false, availableDays: 0, requiredDays: 0, finishDate: null);
  }
  final available = <DateTime>[];
  for (var date = _dayOnly(plan.startDate);
      !date.isAfter(_dayOnly(plan.endDate));
      date = DateTime(date.year, date.month, date.day + 1)) {
    if (plan.weekdays.contains(date.weekday)) available.add(date);
  }
  final required =
      (segmentCount + plan.dailyNewQuota - 1) ~/ plan.dailyNewQuota;
  return SchedulePreview(
    fits: available.length >= required,
    availableDays: available.length,
    requiredDays: required,
    finishDate: available.length >= required ? available[required - 1] : null,
  );
}

List<Task> createNewLearningTasks(Plan plan) {
  final preview = previewPlan(plan);
  if (!preview.fits || plan.paused) return const <Task>[];
  final tasks = <Task>[];
  var segmentIndex = 0;
  for (var date = _dayOnly(plan.startDate);
      !date.isAfter(_dayOnly(plan.endDate)) &&
          segmentIndex < plan.segmentIds.length;
      date = DateTime(date.year, date.month, date.day + 1)) {
    if (!plan.weekdays.contains(date.weekday)) continue;
    for (var n = 0;
        n < plan.dailyNewQuota && segmentIndex < plan.segmentIds.length;
        n++) {
      final segmentId = plan.segmentIds[segmentIndex++];
      tasks.add(Task(
          id: '${plan.id}:new:$segmentId',
          planId: plan.id,
          segmentId: segmentId,
          kind: TaskKind.newLearning,
          dueDate: date));
    }
  }
  return tasks;
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
