import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  LearningEvent event(String id, int day,
          {int seconds = 30,
          AttemptSource source = AttemptSource.automatic,
          AttemptStatus status = AttemptStatus.failed,
          TaskKind kind = TaskKind.newLearning,
          String segment = 'segment',
          LearningEventType type = LearningEventType.attempt}) =>
      LearningEvent(
          id: id,
          type: type,
          occurredAt: DateTime.utc(2026, 10, day, 4),
          timeZone: 'Asia/Shanghai',
          durationSeconds: seconds,
          source: source,
          status: status,
          taskKind: kind,
          segmentId: segment,
          attemptId: id);
  LearningGrowth growth(List<LearningEvent> events, int day) =>
      buildLearningGrowth(
          events: events,
          today: DateTime(2026, 10, day),
          localDate: eventLocalTime);
  test('连续学习跨周按真实日期，今天未学保留昨天链，漏一天重新开始', () {
    final events = [for (var d = 3; d <= 8; d++) event('day$d', d)];
    expect(growth(events, 9).currentStreak, 6);
    expect(growth(events, 9).weekDays, 4);
    expect(growth(events, 9).totalDays, 6);
    expect(growth(events, 10).currentStreak, 0);
    final next = growth([...events, event('day10', 10)], 10);
    expect(next.currentStreak, 1);
    expect(next.longestStreak, 6);
    expect(next.stage, 3);
  });
  test('练习可浇水，辅助/人工不能给掌握徽章，技术失败/未来/改期不成长', () {
    final value = growth([
      event('pass', 8, seconds: 0, status: AttemptStatus.passed),
      event('pass', 8, seconds: 0, status: AttemptStatus.passed),
      event('retry', 8, status: AttemptStatus.passed),
      event('assisted', 9,
          source: AttemptSource.assisted, status: AttemptStatus.passed),
      event('manual', 7,
          source: AttemptSource.manual, status: AttemptStatus.passed),
      event('failure', 6, status: AttemptStatus.technicalFailure),
      event('processing', 5, status: AttemptStatus.processing),
      event('future', 10, status: AttemptStatus.passed),
      event('moved', 4, type: LearningEventType.taskRescheduled),
      event('review', 9, status: AttemptStatus.passed, kind: TaskKind.review),
    ], 9);
    expect(value.totalDays, 2);
    expect(value.currentStreak, 2);
    expect(value.masteredSegments, 1);
    expect(value.reviewPasses, 1);
    expect(growth([], 9).stage, 0);
  });
}
