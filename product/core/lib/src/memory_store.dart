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
      void add(String table, JsonObject value, {bool immutable = false}) {
        final entries = next[table] as Map<String, dynamic>;
        final id = value['id'] as String;
        if (id.trim().isEmpty) throw ArgumentError('实体ID不能为空');
        final old = entries[id];
        if (immutable && old != null && jsonEncode(old) != jsonEncode(value))
          throw StateError('历史记录不可覆盖：$table/$id');
        entries[id] = value;
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
        if (old != null && t.status == TaskStatus.pending) continue;
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
      _all('articles', EntityCodec.readArticle);
  @override
  Future<List<Plan>> plans() async => _all('plans', EntityCodec.readPlan);
  @override
  Future<Plan?> getPlan(String id) async =>
      _get('plans', id, EntityCodec.readPlan);
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
  Future<Article?> getArticle(String id) async =>
      _get('articles', id, EntityCodec.readArticle);
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
  Future<void> savePlan(Plan value) async {
    await writeBatch(RecitationBatch(plans: [value]));
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
    await saveTask(Task(
        id: old.id,
        planId: old.planId,
        segmentId: old.segmentId,
        kind: old.kind,
        dueDate: old.dueDate,
        status: TaskStatus.completed));
  }

  static Map<String, dynamic> _clone(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}
