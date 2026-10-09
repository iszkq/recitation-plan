import 'models.dart';

enum LearningEventType {
  practice,
  attempt,
  taskDue,
  taskCompleted,
  taskSkipped,
  taskRescheduled,
  technicalFailure
}

enum ScheduleAdjustment { remainingPlan, reviewBacklog }

class LearningEvent {
  const LearningEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.timeZone,
    required this.durationSeconds,
    this.taskId,
    this.segmentId,
    this.attemptId,
    this.source,
    this.status,
    this.taskKind,
    this.dueDate,
    this.previousDueDate,
    this.undoOf,
    this.adjustment,
  });

  final String id;
  final LearningEventType type;
  final DateTime occurredAt;
  final String timeZone;
  final int durationSeconds;
  final String? taskId;
  final String? segmentId;
  final String? attemptId;
  final AttemptSource? source;
  final AttemptStatus? status;
  final TaskKind? taskKind;
  final DateTime? dueDate;
  final DateTime? previousDueDate;
  final String? undoOf;
  final ScheduleAdjustment? adjustment;

  bool get isValidDuration => durationSeconds > 0;
  bool get isAutomaticPass =>
      source == AttemptSource.automatic && status == AttemptStatus.passed;
  bool get isAssisted => source == AttemptSource.assisted;
  bool get isManual => source == AttemptSource.manual;
}
