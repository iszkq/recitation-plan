import 'dart:convert';
import 'codec.dart';
import 'events.dart';
import 'models.dart';
import 'ports.dart';

/// Serialized snapshots isolate the store from mutable caller collections.
class MemoryRecitationStore implements RecitationStore {
  MemoryRecitationStore({Map<String, dynamic>? initial})
      : _state = initial == null ? emptyState() : _clone(initial);
  static const tables = [
    'articles',
    'versions',
    'plans',
    'tasks',
    'attempts',
    'events'
  ];
  static Map<String, dynamic> emptyState() =>
      {'schemaVersion': 1, for (final t in tables) t: <String, dynamic>{}};
  Map<String, dynamic> _state;
  Future<void> _tail = Future<void>.value();
  Future<void> persist(Map<String, dynamic> next) async {}
  Future<void> close() async {
    await _tail;
  }

  Map<String, dynamic> snapshot() => _clone(_state);
  @override
  Future<bool> writeBatch(RecitationBatch batch) {
    final operation = _tail.then((_) async {
      final next = _clone(_state);
      final finalId = batch.finalizesAttemptId;
      if (finalId != null) {
        final old = (next['attempts'] as Map)[finalId];
        if (old != null && old['status'] != AttemptStatus.processing.name)
          return false;
      }
      for (final entry in batch.expectedTaskDueDates.entries) {
        final old = (next['tasks'] as Map)[entry.key];
        if (old == null ||
            old['dueDate'] != EntityCodec.day(entry.value) ||
            (batch.reschedulesPendingTasks &&
                old['status'] != TaskStatus.pending.name)) {
          throw StateError('任务已更新，请刷新后重试');
        }
        final plan = (next['plans'] as Map)[old['planId']];
        if (plan == null || plan['deleted'] == true || plan['paused'] == true) {
          throw StateError('计划不存在或已暂停');
        }
      }
      void add(String table, JsonObject value, {bool immutable = false}) {
        final entries = next[table] as Map<String, dynamic>;
        final id = value['id'] as String;
        if (id.trim().isEmpty) throw ArgumentError('实体ID不能为空');
        final old = entries[id];
        if (immutable && old != null && jsonEncode(old) != jsonEncode(value))
          throw StateError('历史记录不可覆盖：$table/$id');
        entries[id] = value;
      }

      for (final entry in batch.expectedRescheduleIds.entries) {
        String? latest;
        DateTime? latestAt;
        for (final raw in (next['events'] as Map).values) {
          if (raw['taskId'] != entry.key ||
              raw['type'] != LearningEventType.taskRescheduled.name) continue;
          final at = DateTime.parse(raw['occurredAt'] as String);
          if (latestAt == null || !at.isBefore(latestAt)) {
            latest = raw['id'] as String;
            latestAt = at;
          }
        }
        if (latest != entry.value) throw StateError('排期已更新，请刷新后重试');
      }

      for (final a in batch.articles) {
        add('articles', EntityCodec.article(a));
      }
      for (final v in batch.versions) {
        add('versions', EntityCodec.version(v), immutable: true);
      }
      for (final p in batch.plans) {
        add('plans', EntityCodec.plan(p));
      }
      for (final t in batch.tasks) {
        final old = (next['tasks'] as Map)[t.id];
        if (old != null && old['status'] == TaskStatus.completed.name) continue;
        if (old != null &&
            t.status == TaskStatus.pending &&
            !(batch.reschedulesPendingTasks &&
                batch.expectedTaskDueDates.containsKey(t.id))) continue;
        add('tasks', EntityCodec.task(t));
      }
      for (final a in batch.attempts) {
        final old = (next['attempts'] as Map)[a.id];
        if (old != null && old['status'] != AttemptStatus.processing.name)
          continue;
        add('attempts', EntityCodec.attempt(a));
      }
      for (final e in batch.events) {
        if ((next['events'] as Map).containsKey(e.id)) continue;
        add('events', EntityCodec.event(e), immutable: true);
      }
      await persist(next);
      _state = _clone(next);
      return true;
    });
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }

  List<T> _all<T>(String table, T Function(JsonObject) read) =>
      (_state[table] as Map)
          .values
          .map((j) => read(Map<String, dynamic>.from(j as Map)))
          .toList();
  T? _get<T>(String table, String id, T Function(JsonObject) read) {
    final j = (_state[table] as Map)[id];
    return j == null ? null : read(_clone(j));
  }

  @override
  Future<List<Article>> articles() async =>
      _all('articles', EntityCodec.readArticle)
          .where((a) => !a.deleted)
          .toList();
  @override
  Future<List<Plan>> plans() async =>
      _all('plans', EntityCodec.readPlan).where((p) => !p.deleted).toList();
  @override
  Future<Plan?> getPlan(String id) async {
    final plan = _get('plans', id, EntityCodec.readPlan);
    return plan?.deleted == true ? null : plan;
  }

  @override
  Future<Segment?> getSegment(String id) async {
    for (final v in _all('versions', EntityCodec.readVersion)) {
      for (final s in v.segments) {
        if (s.id == id) return s;
      }
    }
    return null;
  }

  @override
  Future<Task?> getTask(String id) async =>
      _get('tasks', id, EntityCodec.readTask);
  @override
  Future<List<Task>> tasks() async => _all('tasks', EntityCodec.readTask);
  @override
  Future<Attempt?> getAttempt(String id) async =>
      _get('attempts', id, EntityCodec.readAttempt);
  @override
  Future<List<LearningEvent>> events() async =>
      _all('events', EntityCodec.readEvent);
  @override
  Future<Article?> getArticle(String id) async {
    final article = _get('articles', id, EntityCodec.readArticle);
    return article?.deleted == true ? null : article;
  }

  @override
  Future<ArticleVersion?> getArticleVersion(String id) async =>
      _get('versions', id, EntityCodec.readVersion);
  @override
  Future<void> saveArticle(Article value) async {
    await writeBatch(RecitationBatch(articles: [value]));
  }

  @override
  Future<void> saveArticleVersion(ArticleVersion value) async {
    await writeBatch(RecitationBatch(versions: [value]));
  }

  @override
  Future<void> deleteArticle(String id) async {
    final operation = _tail.then((_) async {
      final next = _clone(_state);
      final article = (next['articles'] as Map<String, dynamic>)[id];
      if (article == null) return;
      // Keep original versions and identity for historical attempts and backups.
      article['deleted'] = true;
      await persist(next);
      _state = _clone(next);
    });
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    await operation;
  }

  @override
  Future<void> savePlan(Plan value) async {
    await writeBatch(RecitationBatch(plans: [value]));
  }

  @override
  Future<void> deletePlan(String id) async {
    final operation = _tail.then((_) async {
      final next = _clone(_state);
      final plans = next['plans'] as Map<String, dynamic>;
      if (!plans.containsKey(id)) return;
      plans[id]['deleted'] = true;
      plans[id]['paused'] = true;
      final tasks = next['tasks'] as Map<String, dynamic>;
      for (final value in tasks.values) {
        if (value['planId'] == id &&
            value['status'] != TaskStatus.completed.name) {
          value['status'] = TaskStatus.skipped.name;
        }
      }
      await persist(next);
      _state = _clone(next);
    });
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    await operation;
  }

  @override
  Future<void> saveTask(Task value) async {
    await writeBatch(RecitationBatch(tasks: [value]));
  }

  @override
  Future<void> saveAttempt(Attempt value) async {
    await writeBatch(RecitationBatch(attempts: [value]));
  }

  @override
  Future<bool> hasAttempt(String id) async =>
      (_state['attempts'] as Map).containsKey(id);
  @override
  Future<List<Attempt>> attemptsForSegment(String id) async =>
      _all('attempts', EntityCodec.readAttempt)
          .where((a) => a.segmentId == id)
          .toList();
  @override
  Future<List<Task>> tasksForDay(DateTime day) async =>
      _all('tasks', EntityCodec.readTask)
          .where((t) => EntityCodec.day(t.dueDate) == EntityCodec.day(day))
          .toList();
  Future<Task?> task(String id) => getTask(id);

  /// Repository-level helper; product code submits assessed atomic batches.
  Future<void> completeTaskOnce(String id) async {
    final old = await getTask(id);
    if (old == null || old.status == TaskStatus.completed) return;
    await saveTask(old.copyWith(status: TaskStatus.completed));
  }

  static Map<String, dynamic> _clone(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}
