import 'events.dart';
import 'models.dart';

class LearningGrowth {
  LearningGrowth(
      {required this.days,
      required this.currentStreak,
      required this.longestStreak,
      required this.weekDays,
      required this.masteredSegments,
      required this.reviewPasses});
  final Set<DateTime> days;
  final int currentStreak;
  final int longestStreak;
  final int weekDays;
  final int masteredSegments;
  final int reviewPasses;
  int get totalDays => days.length;
  static const stages = [
    (days: 0, name: '一颗种子'),
    (days: 1, name: '破土的小芽'),
    (days: 3, name: '舒展新叶'),
    (days: 7, name: '含苞待放'),
    (days: 14, name: '开出小花'),
    (days: 30, name: '繁花成荫'),
  ];
  int get stage => stages.lastIndexWhere((s) => totalDays >= s.days);
  int? get nextStageDays =>
      stage == stages.length - 1 ? null : stages[stage + 1].days;
}

/// Practice grows habits; only automatic passes earn mastery badges.
LearningGrowth buildLearningGrowth(
    {required Iterable<LearningEvent> events,
    required DateTime today,
    required DateTime Function(LearningEvent) localDate}) {
  DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
  final cutoff = day(today);
  final days = <DateTime>{};
  final segments = <String>{};
  final reviewAttempts = <String>{};
  final unique = {for (final e in events) e.id: e};
  for (final e in unique.values) {
    final date = day(localDate(e));
    if (date.isAfter(cutoff)) continue;
    if ((e.type == LearningEventType.practice ||
            e.type == LearningEventType.attempt) &&
        e.durationSeconds > 0 &&
        e.status != AttemptStatus.technicalFailure &&
        e.status != AttemptStatus.processing &&
        e.source != AttemptSource.manual) {
      days.add(date);
    }
    if (e.type == LearningEventType.attempt && e.isAutomaticPass) {
      // Fast genuine passes also count even if the stopwatch rounded to zero.
      days.add(date);
      if (e.taskKind == TaskKind.newLearning && e.segmentId != null)
        segments.add(e.segmentId!);
      if (e.taskKind == TaskKind.review && e.attemptId != null)
        reviewAttempts.add(e.attemptId!);
    }
  }
  final ordered = days.toList()..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final date in ordered) {
    run = previous != null &&
            date == DateTime(previous.year, previous.month, previous.day + 1)
        ? run + 1
        : 1;
    if (run > longest) longest = run;
    previous = date;
  }
  var cursor = days.contains(cutoff)
      ? cutoff
      : DateTime(cutoff.year, cutoff.month, cutoff.day - 1);
  var current = 0;
  while (days.contains(cursor)) {
    current++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  final monday =
      DateTime(cutoff.year, cutoff.month, cutoff.day - cutoff.weekday + 1);
  return LearningGrowth(
      days: Set.unmodifiable(days),
      currentStreak: current,
      longestStreak: longest,
      weekDays: days.where((d) => !d.isBefore(monday)).length,
      masteredSegments: segments.length,
      reviewPasses: reviewAttempts.length);
}
