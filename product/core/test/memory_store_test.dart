import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

class FailingStore extends MemoryRecitationStore {
  @override
  Future<void> persist(Map<String, dynamic> next) async =>
      throw StateError('磁盘写入失败');
}

void main() {
  test('持久化失败时不发布部分内存更新', () async {
    final store = FailingStore();
    final t = Task(
        id: 't',
        planId: 'p',
        segmentId: 's',
        kind: TaskKind.newLearning,
        dueDate: DateTime(2026, 10, 8));
    await expectLater(store.saveTask(t), throwsStateError);
    expect(await store.getTask('t'), isNull);
  });
  test('任务完成是幂等的', () async {
    final store = MemoryRecitationStore();
    final task = Task(
        id: 't1',
        planId: 'p1',
        segmentId: 's1',
        kind: TaskKind.newLearning,
        dueDate: DateTime(2026, 10, 8));
    await store.saveTask(task);
    await store.completeTaskOnce('t1');
    await store.completeTaskOnce('t1');
    expect((await store.task('t1'))!.status, TaskStatus.completed);
  });

  test('处理中考核可以被最终结果更新，最终结果不能被重复回调覆盖', () async {
    final store = MemoryRecitationStore();
    final pending = Attempt(
        id: 'a1',
        taskId: 't1',
        segmentId: 's1',
        source: AttemptSource.automatic,
        status: AttemptStatus.processing,
        createdAt: DateTime(2026, 10, 8));
    final finalAttempt = Attempt(
        id: 'a1',
        taskId: 't1',
        segmentId: 's1',
        source: AttemptSource.automatic,
        status: AttemptStatus.passed,
        createdAt: DateTime(2026, 10, 8));
    final duplicateFailure = Attempt(
        id: 'a1',
        taskId: 't1',
        segmentId: 's1',
        source: AttemptSource.automatic,
        status: AttemptStatus.failed,
        createdAt: DateTime(2026, 10, 8));
    await store.saveAttempt(pending);
    await store.saveAttempt(finalAttempt);
    await store.saveAttempt(duplicateFailure);
    expect((await store.attemptsForSegment('s1')).single.status,
        AttemptStatus.passed);
  });
}
