import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

LearningEvent event({
  required String id,
  required LearningEventType type,
  required DateTime date,
  String? taskId,
  String? segmentId,
  String? attemptId,
  AttemptSource? source,
  AttemptStatus? status,
  TaskKind? taskKind,
  int seconds = 60,
}) =>
    LearningEvent(
      id: id,
      type: type,
      occurredAt: date,
      timeZone: 'Asia/Shanghai',
      durationSeconds: seconds,
      taskId: taskId,
      segmentId: segmentId,
      attemptId: attemptId,
      source: source,
      status: status,
      taskKind: taskKind,
    );

void main() {
  test('周报按周一到周日统计，并区分辅助和技术失败', () {
    final events = [
      event(
          id: 'd1',
          type: LearningEventType.taskDue,
          date: DateTime(2026, 10, 5),
          taskId: 't1'),
      event(
          id: 'c1',
          type: LearningEventType.taskCompleted,
          date: DateTime(2026, 10, 5),
          taskId: 't1'),
      event(
          id: 'a1',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 6),
          segmentId: 's1',
          attemptId: 'a1',
          source: AttemptSource.automatic,
          status: AttemptStatus.passed,
          taskKind: TaskKind.review),
      event(
          id: 'a2',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 7),
          segmentId: 's2',
          attemptId: 'a2',
          source: AttemptSource.assisted,
          status: AttemptStatus.failed,
          taskKind: TaskKind.review),
      event(
          id: 'f1',
          type: LearningEventType.technicalFailure,
          date: DateTime(2026, 10, 7),
          seconds: 0),
    ];
    final report = buildReport(
        period: ReportPeriod.week,
        anchor: DateTime(2026, 10, 8),
        events: events,
        localDate: (e) => e.occurredAt);
    expect(report.start, DateTime(2026, 10, 5));
    expect(report.end, DateTime(2026, 10, 11));
    expect(report.completedTasks, 1);
    expect(report.newMasteredSegments, 0);
    expect(report.assistedPractices, 1);
    expect(report.technicalFailures, 1);
    expect(report.reviewRetention, 100);
  });

  test('没有复习样本时不显示百分比', () {
    final report = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 8),
        events: const [],
        localDate: (e) => e.occurredAt);
    expect(report.reviewRetention, isNull);
    expect(report.completionRate, isNull);
  });

  test('重复事件不重复计算时长且首次掌握不跨月重复', () {
    final old = event(
        id: 'old',
        type: LearningEventType.attempt,
        date: DateTime(2026, 9, 30),
        segmentId: 's1',
        attemptId: 'old',
        source: AttemptSource.automatic,
        status: AttemptStatus.passed,
        taskKind: TaskKind.newLearning);
    final repeat = event(
        id: 'repeat',
        type: LearningEventType.attempt,
        date: DateTime(2026, 10, 8),
        segmentId: 's1',
        attemptId: 'repeat',
        source: AttemptSource.automatic,
        status: AttemptStatus.passed,
        taskKind: TaskKind.newLearning);
    final report = buildReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 8),
        events: [old, repeat, repeat],
        localDate: (e) => e.occurredAt);
    expect(report.newMasteredSegments, 0);
    expect(report.focusMinutes, 1);
  });

  test('人工确认、待复核和技术失败不进入复习通过比例', () {
    final events = [
      event(
          id: 'p',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 8),
          attemptId: 'p',
          source: AttemptSource.automatic,
          status: AttemptStatus.passed,
          taskKind: TaskKind.review),
      event(
          id: 'f',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 8),
          attemptId: 'f',
          source: AttemptSource.automatic,
          status: AttemptStatus.failed,
          taskKind: TaskKind.review),
      event(
          id: 'm',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 8),
          attemptId: 'm',
          source: AttemptSource.manual,
          status: AttemptStatus.passed,
          taskKind: TaskKind.review),
      event(
          id: 'u',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 8),
          attemptId: 'u',
          source: AttemptSource.automatic,
          status: AttemptStatus.needsReview,
          taskKind: TaskKind.review),
      event(
          id: 't',
          type: LearningEventType.attempt,
          date: DateTime(2026, 10, 8),
          attemptId: 't',
          source: AttemptSource.automatic,
          status: AttemptStatus.technicalFailure,
          taskKind: TaskKind.review),
    ];
    final r = buildReport(
        period: ReportPeriod.week,
        anchor: DateTime(2026, 10, 8),
        events: events,
        localDate: (e) => e.occurredAt);
    expect(r.reviewAttempts, 2);
    expect(r.reviewRetention, 50);
    expect(r.manualConfirmations, 1);
    expect(r.technicalFailures, 1);
  });
}
