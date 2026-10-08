import 'models.dart';

const defaultReviewIntervals = <int>[1, 3, 7, 14, 30];

/// Generates future review tasks only after an automatic, unassisted pass.
/// The stable ID makes retries and repeated final callbacks idempotent.
List<Task> createReviewTasks({
  required Plan plan,
  required String segmentId,
  required DateTime passedAt,
  List<int> intervals = defaultReviewIntervals,
}) {
  if (plan.paused || !plan.segmentIds.contains(segmentId))
    return const <Task>[];
  final base = _dayOnly(passedAt);
  return [
    for (final days
        in intervals.where((days) => days > 0).toSet().toList()..sort())
      Task(
        id: '${plan.id}:review:$segmentId:$days',
        planId: plan.id,
        segmentId: segmentId,
        kind: TaskKind.review,
        dueDate: DateTime(base.year, base.month, base.day + days),
      ),
  ];
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
