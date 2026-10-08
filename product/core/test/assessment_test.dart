import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  const segment = Segment(
      id: 's1', versionId: 'v1', order: 0, text: '学不可以已。', keywords: {'学'});
  const rule = AssessmentRule();

  test('满足阈值且无辅助时自动通过', () {
    final decision = assessTranscript(
        segment: segment,
        transcript: '学不可以已',
        rule: rule,
        wasAssisted: false,
        hasUnresolvedDoubt: false);
    expect(decision.status, AttemptStatus.passed);
    expect(decision.countsAsAutomaticCompletion, isTrue);
  });

  test('辅助练习不能自动完成任务', () {
    final decision = assessTranscript(
        segment: segment,
        transcript: '学不可以已',
        rule: rule,
        wasAssisted: true,
        hasUnresolvedDoubt: false);
    expect(decision.status, AttemptStatus.failed);
    expect(decision.source, AttemptSource.assisted);
    expect(decision.countsAsAutomaticCompletion, isFalse);
  });

  test('疑点必须先复核', () {
    final decision = assessTranscript(
        segment: segment,
        transcript: '学不可以已',
        rule: rule,
        wasAssisted: false,
        hasUnresolvedDoubt: true);
    expect(decision.status, AttemptStatus.needsReview);
  });

  test('识别技术失败不判定为背错', () {
    final decision = assessTranscript(
        segment: segment,
        transcript: '',
        rule: rule,
        wasAssisted: false,
        hasUnresolvedDoubt: false,
        technicalFailure: true);
    expect(decision.status, AttemptStatus.technicalFailure);
  });
  test('关闭标点容错时规则确实生效', () {
    final r = assessTranscript(
        segment: segment,
        transcript: '学不可以已',
        rule: const AssessmentRule(ignorePunctuation: false),
        wasAssisted: false,
        hasUnresolvedDoubt: false);
    expect(r.status, AttemptStatus.failed);
  });
}
