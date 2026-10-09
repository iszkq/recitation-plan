import 'package:recitation_core/recitation_core.dart';
import 'package:recitation_core/src/codec.dart';
import 'package:test/test.dart';

void main() {
  test('对齐提供真实错漏多字和字符位置，保留标点原样', () {
    final result = alignText('甲，乙丙丁。', '甲 错丙丁多！');
    expect(result.substituted, 1);
    expect(result.inserted, 1);
    final wrong =
        result.edits.firstWhere((e) => e.kind == TextEditKind.substitution);
    expect(wrong.expected, '乙');
    expect(wrong.actual, '错');
    expect(wrong.originalPosition, 2);
    expect(wrong.originalOffset, 2);
    expect(wrong.transcriptOffset, 2);
    expect(correctedSpeechText('甲 错丙丁多！', result.edits), '甲 错丙丁多！');
    final missed = alignText('甲乙丙丁', '甲丙丁');
    expect(missed.deleted, 1);
    expect(missed.substituted, 0);
    expect(
        missed.edits
            .singleWhere((e) => e.kind == TextEditKind.deletion)
            .expected,
        '乙');
  });
  test('同音同调语音容错，默写严格；没有补全漏背或多背', () {
    final voice = alignText('青，取之于蓝。', '清，取之于兰。', allowHomophones: true);
    expect(voice.accuracy, 100);
    expect(voice.edits.where((e) => e.kind == TextEditKind.homophone),
        hasLength(2));
    expect(correctedSpeechText('清，取之于兰。', voice.edits), '青，取之于蓝。');
    expect(alignText('青，取之于蓝。', '清，取之于兰。').substituted, 2);
    final missing = alignText('青取之于蓝', '清取兰', allowHomophones: true);
    expect(missing.deleted, 2);
    expect(correctedSpeechText('清取兰', missing.edits), '青取蓝');
    final extra = alignText('青取之于蓝', '清取之于兰啊', allowHomophones: true);
    expect(extra.inserted, 1);
    expect(correctedSpeechText('清取之于兰啊', extra.edits), '青取之于蓝啊');
  });
  test('异调、近音、多音、未知字符不会自动算对；Unicode偏移有效', () {
    for (final pair in [('青', '请'), ('蓝', '南'), ('重', '种'), ('𠀀', '甲')]) {
      expect(alignText(pair.$1, pair.$2, allowHomophones: true).substituted, 1);
    }
    final result = alignText('𠀀青', '𠀀清', allowHomophones: true);
    expect(result.edits.last.transcriptOffset, 2);
    expect(correctedSpeechText('𠀀清', result.edits), '𠀀青');
    expect(
        alignText('青。', '清！', allowHomophones: true, ignorePunctuation: false)
            .substituted,
        1);
  });
  test('语音容错遵守门槛、关键项、临时转录和人工辅助边界，备份持久化', () async {
    final store = MemoryRecitationStore();
    final service =
        RecitationService(store, clock: () => DateTime.utc(2026, 10, 9, 4));
    final article = await service.importArticle(title: '劝学', text: '青取之于蓝。');
    await service.createPlan(
        name: '计划',
        versionIds: [article.currentVersionId],
        start: DateTime(2026, 10, 9),
        end: DateTime(2026, 10, 9),
        quota: 1,
        weekdays: {5},
        rule: const AssessmentRule(
            accuracyThreshold: 100, coverageThreshold: 100));
    final task = (await store.tasks()).single;
    await expectLater(
        service.submitFinalTranscript(
            taskId: task.id,
            attemptId: 'interim',
            transcript: '清取之于兰',
            isFinal: false,
            input: AssessmentInput.speech,
            acceptHomophones: true),
        throwsStateError);
    final typed = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'typed',
        transcript: '清取之于兰',
        isFinal: true,
        acceptHomophones: true);
    expect(typed.status, AttemptStatus.failed);
    expect(typed.acceptHomophones, isFalse);
    final omitted = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'omitted',
        transcript: '清取兰',
        isFinal: true,
        input: AssessmentInput.speech,
        acceptHomophones: true);
    expect(omitted.status, AttemptStatus.failed);
    expect(omitted.score!.deleted, 2);
    final assisted = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'assisted',
        transcript: '清取之于兰',
        isFinal: true,
        input: AssessmentInput.speech,
        acceptHomophones: true,
        assisted: true);
    expect(assisted.status, AttemptStatus.failed);
    final doubt = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'doubt',
        transcript: '清取之于兰',
        isFinal: true,
        input: AssessmentInput.speech,
        acceptHomophones: true,
        hasUnresolvedDoubt: true);
    expect(doubt.status, AttemptStatus.needsReview);
    final passed = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: 'voice',
        transcript: '清取之于兰',
        isFinal: true,
        input: AssessmentInput.speech,
        acceptHomophones: true);
    expect(passed.status, AttemptStatus.passed);
    expect(passed.transcript, '清取之于兰');
    expect((await store.getTask(task.id))!.status, TaskStatus.completed);
    final state = BackupService(store, profileId: 'local')
        .snapshotState(BackupService(store, profileId: 'local').export());
    final reopened = MemoryRecitationStore(initial: state);
    final restored = (await reopened.getAttempt('voice'))!;
    expect(restored.input, AssessmentInput.speech);
    expect(restored.acceptHomophones, isTrue);
    final old = EntityCodec.attempt(passed)
      ..remove('input')
      ..remove('acceptHomophones');
    expect(EntityCodec.readAttempt(old).acceptHomophones, isFalse);
  });
}
