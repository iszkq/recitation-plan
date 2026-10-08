import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  final rule = const AssessmentRule();

  test('截止日当天计入学习日', () {
    final plan = Plan(
      id: 'p1',
      name: '十月计划',
      segmentIds: List.generate(12, (i) => 's$i'),
      startDate: DateTime(2026, 10, 8),
      endDate: DateTime(2026, 10, 19),
      dailyNewQuota: 1,
      weekdays: const {1, 2, 3, 4, 5, 6, 7},
      rule: rule,
      timeZone: 'Asia/Shanghai',
    );
    final preview = previewPlan(plan);
    expect(preview.fits, isTrue);
    expect(preview.finishDate, DateTime(2026, 10, 19));
  });

  test('日期不足时不能创建任务', () {
    final plan = Plan(
      id: 'p1',
      name: '十月计划',
      segmentIds: List.generate(12, (i) => 's$i'),
      startDate: DateTime(2026, 10, 8),
      endDate: DateTime(2026, 10, 18),
      dailyNewQuota: 1,
      weekdays: const {1, 2, 3, 4, 5, 6, 7},
      rule: rule,
      timeZone: 'Asia/Shanghai',
    );
    expect(previewPlan(plan).fits, isFalse);
    expect(createNewLearningTasks(plan), isEmpty);
  });
}
