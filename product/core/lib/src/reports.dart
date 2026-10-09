import 'events.dart';
import 'models.dart';

enum ReportPeriod { week, month, year }

class LearningReport {
  const LearningReport({
    required this.period,
    required this.start,
    required this.end,
    required this.dueTasks,
    required this.completedTasks,
    required this.newMasteredSegments,
    required this.reviewAttempts,
    required this.reviewPasses,
    required this.assistedPractices,
    required this.manualConfirmations,
    required this.technicalFailures,
    required this.learningDays,
    required this.checkInDays,
    required this.focusMinutes,
  });

  final ReportPeriod period;
  final DateTime start;
  final DateTime end;
  final int dueTasks;
  final int completedTasks;
  final int newMasteredSegments;
  final int reviewAttempts;
  final int reviewPasses;
  final int assistedPractices;
  final int manualConfirmations;
  final int technicalFailures;
  final int learningDays;
  final int checkInDays;
  final int focusMinutes;

  double? get completionRate =>
      dueTasks == 0 ? null : completedTasks / dueTasks * 100;
  double? get reviewRetention =>
      reviewAttempts == 0 ? null : reviewPasses / reviewAttempts * 100;
}

/// Aggregates immutable events. The caller supplies already-filtered events for
/// the selected account and time zone; no report value comes from cached UI data.
LearningReport buildReport({
  required ReportPeriod period,
  required DateTime anchor,
  required Iterable<LearningEvent> events,
  required DateTime Function(LearningEvent) localDate,
  DateTime? asOf,
}) {
  final range = _range(period, anchor);
  final unique = <String, LearningEvent>{};
  for (final e in events) {
    unique.putIfAbsent(e.id, () => e);
  }
  final all = unique.values.toList();
  final cutoff = asOf == null ? range.end : _dayOnly(asOf);
  final schedules = <String, LearningEvent>{};
  final rescheduled = <String, LearningEvent>{};
  final completedDates = <String, DateTime>{};
  for (final event in all) {
    final id = event.taskId;
    if (id == null) continue;
    final day = _dayOnly(localDate(event));
    if (event.type == LearningEventType.taskDue) schedules[id] = event;
    if (day.isAfter(cutoff)) continue;
    if (event.type == LearningEventType.taskRescheduled &&
        event.dueDate != null) {
      final old = rescheduled[id];
      if (old == null || !event.occurredAt.isBefore(old.occurredAt))
        rescheduled[id] = event;
    }
    if (event.type == LearningEventType.taskCompleted) {
      final old = completedDates[id];
      if (old == null || day.isBefore(old)) completedDates[id] = day;
    }
  }
  final selected = all.where((event) {
    final day = _dayOnly(localDate(event));
    return !day.isBefore(range.start) &&
        !day.isAfter(range.end) &&
        !day.isAfter(cutoff);
  }).toList();
  final completedTaskIds = <String>{};
  final dueTaskIds = <String>{};
  final dueByDay = <DateTime, Set<String>>{};
  final completedByDay = <DateTime, Set<String>>{};
  final newSegments = <String>{};
  final reviewAttempts = <String>{};
  final reviewPasses = <String>{};
  final learningDays = <DateTime>{};
  var assisted = 0;
  var manual = 0;
  var technical = 0;
  var focusSeconds = 0;

  final firstMastery = <String, DateTime>{};
  for (final e in all) {
    if (e.type == LearningEventType.attempt &&
        e.isAutomaticPass &&
        e.taskKind == TaskKind.newLearning &&
        e.segmentId != null) {
      final date = _dayOnly(localDate(e));
      final old = firstMastery[e.segmentId!];
      if (old == null || date.isBefore(old)) firstMastery[e.segmentId!] = date;
    }
  }
  for (final event in selected) {
    final day = _dayOnly(localDate(event));
    if ((event.type == LearningEventType.practice ||
            event.type == LearningEventType.attempt) &&
        event.isValidDuration &&
        event.status != AttemptStatus.technicalFailure) {
      learningDays.add(day);
      focusSeconds += event.durationSeconds;
    }
    if (event.type == LearningEventType.taskCompleted && event.taskId != null) {
      completedTaskIds.add(event.taskId!);
    }
    if (event.type == LearningEventType.taskSkipped && event.taskId != null) {
      dueTaskIds.add(event.taskId!);
      dueByDay.putIfAbsent(day, () => <String>{}).add(event.taskId!);
    }
    if (event.type == LearningEventType.taskCompleted && event.taskId != null) {
      completedByDay.putIfAbsent(day, () => <String>{}).add(event.taskId!);
    }
    if (event.type == LearningEventType.attempt &&
        event.isAutomaticPass &&
        event.segmentId != null &&
        event.taskKind == TaskKind.newLearning &&
        firstMastery[event.segmentId] == day) {
      newSegments.add(event.segmentId!);
    }
    if (event.type == LearningEventType.attempt &&
        event.taskKind == TaskKind.review &&
        event.source == AttemptSource.automatic &&
        (event.status == AttemptStatus.passed ||
            event.status == AttemptStatus.failed) &&
        event.attemptId != null) {
      reviewAttempts.add(event.attemptId!);
      if (event.status == AttemptStatus.passed)
        reviewPasses.add(event.attemptId!);
    }
    if (event.type == LearningEventType.attempt && event.isAssisted) assisted++;
    if (event.type == LearningEventType.attempt && event.isManual) manual++;
    if (event.type == LearningEventType.technicalFailure ||
        event.status == AttemptStatus.technicalFailure) technical++;
  }
  for (final entry in schedules.entries) {
    final date =
        rescheduled[entry.key]?.dueDate ?? _dayOnly(localDate(entry.value));
    if (date.isBefore(range.start) ||
        date.isAfter(range.end) ||
        date.isAfter(cutoff)) continue;
    dueTaskIds.add(entry.key);
    dueByDay.putIfAbsent(date, () => <String>{}).add(entry.key);
    final completed = completedDates[entry.key];
    if (completed != null) {
      completedTaskIds.add(entry.key);
    }
  }
  return LearningReport(
    period: period,
    start: range.start,
    end: range.end,
    dueTasks: dueTaskIds.length,
    completedTasks: completedTaskIds.intersection(dueTaskIds).length,
    newMasteredSegments: newSegments.length,
    reviewAttempts: reviewAttempts.length,
    reviewPasses: reviewPasses.length,
    assistedPractices: assisted,
    manualConfirmations: manual,
    technicalFailures: technical,
    learningDays: learningDays.length,
    checkInDays: _checkInDays(dueByDay, completedByDay, completedDates),
    focusMinutes: focusSeconds ~/ 60,
  );
}

int _checkInDays(
    Map<DateTime, Set<String>> dueByDay,
    Map<DateTime, Set<String>> completedByDay,
    Map<String, DateTime> completedDates) {
  return dueByDay.entries.where((entry) {
    final completed = completedByDay[entry.key] ?? const <String>{};
    return entry.value.isNotEmpty &&
        completed.isNotEmpty &&
        entry.value.every((id) {
          final date = completedDates[id];
          return date != null && !date.isAfter(entry.key);
        });
  }).length;
}

({DateTime start, DateTime end}) _range(ReportPeriod period, DateTime anchor) {
  final day = _dayOnly(anchor);
  switch (period) {
    case ReportPeriod.week:
      final start = day.subtract(Duration(days: day.weekday - 1));
      return (start: start, end: start.add(const Duration(days: 6)));
    case ReportPeriod.month:
      final start = DateTime(day.year, day.month);
      return (start: start, end: DateTime(day.year, day.month + 1, 0));
    case ReportPeriod.year:
      final start = DateTime(day.year);
      return (start: start, end: DateTime(day.year, 12, 31));
  }
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
