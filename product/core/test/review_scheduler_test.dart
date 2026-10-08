import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  test('自动通过后生成稳定的间隔复习任务', () {
    final plan = Plan(
      id: 'p1',
      name: '计划',
      segmentIds: const ['s1'],
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
      dailyNewQuota: 1,
      weekdays: const {1, 2, 3, 4, 5, 6, 7},
      rule: const AssessmentRule(),
      timeZone: 'Asia/Shanghai',
    );
    final tasks = createReviewTasks(
        plan: plan, segmentId: 's1', passedAt: DateTime(2026, 10, 8));
    expect(tasks.map((task) => task.dueDate), [
      DateTime(2026, 10, 9),
      DateTime(2026, 10, 11),
      DateTime(2026, 10, 15),
      DateTime(2026, 10, 22),
      DateTime(2026, 11, 7)
    ]);
    expect(tasks.map((task) => task.id).toSet().length, 5);
  });

  test('不属于计划的段落不能生成复习任务', () {
    final plan = Plan(
      id: 'p1',
      name: '计划',
      segmentIds: const ['s1'],
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
      dailyNewQuota: 1,
      weekdays: const {1, 2, 3, 4, 5, 6, 7},
      rule: const AssessmentRule(),
      timeZone: 'Asia/Shanghai',
    );
    expect(
        createReviewTasks(
            plan: plan, segmentId: 's2', passedAt: DateTime(2026, 10, 8)),
        isEmpty);
  });
}
