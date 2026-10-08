import 'models.dart';
import 'normalization.dart';

class AssessmentDecision {
  const AssessmentDecision({
    required this.status,
    required this.source,
    required this.score,
    required this.reason,
  });

  final AttemptStatus status;
  final AttemptSource source;
  final Score score;
  final String reason;

  bool get countsAsAutomaticCompletion =>
      status == AttemptStatus.passed && source == AttemptSource.automatic;
}

/// Produces the only decision allowed to complete a task.
///
/// The final transcript is the only text scored. Reference text may explain a
/// difference, but never fills an omitted span. Technical failures must be
/// routed here with [technicalFailure] rather than treated as failed memory.
AssessmentDecision assessTranscript({
  required Segment segment,
  required String transcript,
  required AssessmentRule rule,
  required bool wasAssisted,
  required bool hasUnresolvedDoubt,
  bool technicalFailure = false,
}) {
  if (rule.accuracyThreshold < 0 ||
      rule.accuracyThreshold > 100 ||
      rule.coverageThreshold < 0 ||
      rule.coverageThreshold > 100) {
    throw ArgumentError('考核阈值必须在0至100之间');
  }
  if (normalizeForAssessment(segment.text).isEmpty)
    throw ArgumentError('原文不能为空');
  final source = wasAssisted ? AttemptSource.assisted : AttemptSource.automatic;
  final score = _toScore(
      alignText(segment.text, transcript,
          ignorePunctuation: rule.ignorePunctuation),
      hasUnresolvedDoubt ? 1 : 0);
  if (technicalFailure) {
    return AssessmentDecision(
        status: AttemptStatus.technicalFailure,
        source: source,
        score: score,
        reason: '识别或录音技术失败，不计为背诵失败');
  }
  if (normalizeForAssessment(transcript).isEmpty) {
    return AssessmentDecision(
        status: AttemptStatus.failed,
        source: source,
        score: score,
        reason: '没有检测到有效背诵内容');
  }
  if (hasUnresolvedDoubt) {
    return AssessmentDecision(
        status: AttemptStatus.needsReview,
        source: source,
        score: score,
        reason: '存在未确认的识别疑点');
  }
  if (rule.requireKeywords &&
      segment.keywords.any((word) => !normalizeForAssessment(transcript)
          .contains(normalizeForAssessment(word)))) {
    return AssessmentDecision(
        status: AttemptStatus.failed,
        source: source,
        score: score,
        reason: '关键项未匹配');
  }
  if (wasAssisted) {
    return AssessmentDecision(
        status: AttemptStatus.failed,
        source: source,
        score: score,
        reason: '本次使用了辅助提示，只记录练习');
  }
  final passed = score.accuracy >= rule.accuracyThreshold &&
      score.coverage >= rule.coverageThreshold;
  return AssessmentDecision(
    status: passed ? AttemptStatus.passed : AttemptStatus.failed,
    source: source,
    score: score,
    reason: passed ? '达到一致率和覆盖率阈值' : '一致率或覆盖率未达到阈值',
  );
}

Score _toScore(AlignmentResult result, int unresolved) => Score(
      accuracy: result.accuracy,
      coverage: result.coverage,
      matched: result.matched,
      deleted: result.deleted,
      substituted: result.substituted,
      inserted: result.inserted,
      unresolved: unresolved,
    );
