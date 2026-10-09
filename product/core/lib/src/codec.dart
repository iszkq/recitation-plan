import 'models.dart';
import 'events.dart';

typedef JsonObject = Map<String, dynamic>;

/// Explicit format, independent of enum ordinals or Hive adapter IDs.
class EntityCodec {
  static JsonObject article(Article a) => {
        'id': a.id,
        'title': a.title,
        'author': a.author,
        'currentVersionId': a.currentVersionId,
        'createdAt': a.createdAt.toUtc().toIso8601String(),
        'updatedAt': a.updatedAt.toUtc().toIso8601String(),
        if (a.deleted) 'deleted': true,
      };
  static Article readArticle(JsonObject j) => Article(
        id: j['id'] as String,
        title: j['title'] as String,
        author: j['author'] as String?,
        currentVersionId: j['currentVersionId'] as String,
        createdAt: DateTime.parse(j['createdAt']),
        updatedAt: DateTime.parse(j['updatedAt']),
        deleted: j['deleted'] as bool? ?? false,
      );
  static JsonObject segment(Segment s) => {
        'id': s.id,
        'versionId': s.versionId,
        'order': s.order,
        'text': s.text,
        'title': s.title,
        'keywords': s.keywords.toList()..sort(),
      };
  static Segment readSegment(JsonObject j) => Segment(
        id: j['id'],
        versionId: j['versionId'],
        order: j['order'],
        text: j['text'],
        title: j['title'],
        keywords: Set<String>.from(j['keywords']),
      );
  static JsonObject version(ArticleVersion v) => {
        'id': v.id,
        'articleId': v.articleId,
        'version': v.version,
        'segments': v.segments.map(segment).toList(),
        'createdAt': v.createdAt.toUtc().toIso8601String(),
        'changeNote': v.changeNote,
      };
  static ArticleVersion readVersion(JsonObject j) => ArticleVersion(
        id: j['id'],
        articleId: j['articleId'],
        version: j['version'],
        segments: (j['segments'] as List)
            .map((s) => readSegment(Map<String, dynamic>.from(s)))
            .toList(),
        createdAt: DateTime.parse(j['createdAt']),
        changeNote: j['changeNote'],
      );
  static JsonObject rule(AssessmentRule r) => {
        'accuracyThreshold': r.accuracyThreshold,
        'coverageThreshold': r.coverageThreshold,
        'requireKeywords': r.requireKeywords,
        'ignorePunctuation': r.ignorePunctuation,
      };
  static AssessmentRule readRule(JsonObject j) => AssessmentRule(
        accuracyThreshold: j['accuracyThreshold'],
        coverageThreshold: j['coverageThreshold'],
        requireKeywords: j['requireKeywords'],
        ignorePunctuation: j['ignorePunctuation'],
      );
  // Calendar fields are deliberately not serialized as local timestamps.
  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime readDay(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s))
      throw const FormatException('日期格式无效');
    final d = DateTime.parse(s);
    if (day(d) != s) throw const FormatException('日期无效');
    return DateTime(d.year, d.month, d.day);
  }

  static JsonObject plan(Plan p) => {
        'id': p.id,
        'name': p.name,
        'segmentIds': p.segmentIds,
        'startDate': day(p.startDate),
        'endDate': day(p.endDate),
        'dailyNewQuota': p.dailyNewQuota,
        'weekdays': p.weekdays.toList()..sort(),
        'rule': rule(p.rule),
        'timeZone': p.timeZone,
        'paused': p.paused,
        if (p.deleted) 'deleted': true,
      };
  static Plan readPlan(JsonObject j) => Plan(
        id: j['id'],
        name: j['name'],
        segmentIds: List<String>.from(j['segmentIds']),
        startDate: readDay(j['startDate']),
        endDate: readDay(j['endDate']),
        dailyNewQuota: j['dailyNewQuota'],
        weekdays: Set<int>.from(j['weekdays']),
        rule: readRule(Map<String, dynamic>.from(j['rule'])),
        timeZone: j['timeZone'],
        paused: j['paused'],
        deleted: j['deleted'] as bool? ?? false,
      );
  static JsonObject task(Task t) => {
        'id': t.id,
        'planId': t.planId,
        'segmentId': t.segmentId,
        'kind': t.kind.name,
        'dueDate': day(t.dueDate),
        if (t.originalDueDate != null)
          'originalDueDate': day(t.originalDueDate!),
        'status': t.status.name,
      };
  static Task readTask(JsonObject j) => Task(
        id: j['id'],
        planId: j['planId'],
        segmentId: j['segmentId'],
        kind: TaskKind.values.byName(j['kind']),
        dueDate: readDay(j['dueDate']),
        originalDueDate:
            j['originalDueDate'] == null ? null : readDay(j['originalDueDate']),
        status: TaskStatus.values.byName(j['status']),
      );
  static JsonObject score(Score s) => {
        'accuracy': s.accuracy,
        'coverage': s.coverage,
        'matched': s.matched,
        'deleted': s.deleted,
        'substituted': s.substituted,
        'inserted': s.inserted,
        'unresolved': s.unresolved,
      };
  static Score readScore(JsonObject j) => Score(
        accuracy: (j['accuracy'] as num).toDouble(),
        coverage: (j['coverage'] as num).toDouble(),
        matched: j['matched'],
        deleted: j['deleted'],
        substituted: j['substituted'],
        inserted: j['inserted'],
        unresolved: j['unresolved'],
      );
  static JsonObject attempt(Attempt a) => {
        'id': a.id,
        'taskId': a.taskId,
        'segmentId': a.segmentId,
        'source': a.source.name,
        'status': a.status.name,
        'createdAt': a.createdAt.toUtc().toIso8601String(),
        'transcript': a.transcript,
        'score': a.score == null ? null : score(a.score!),
        'audioPath': a.audioPath,
        'rule': rule(a.rule),
      };
  static Attempt readAttempt(JsonObject j) => Attempt(
        id: j['id'],
        taskId: j['taskId'],
        segmentId: j['segmentId'],
        source: AttemptSource.values.byName(j['source']),
        status: AttemptStatus.values.byName(j['status']),
        createdAt: DateTime.parse(j['createdAt']),
        transcript: j['transcript'],
        score: j['score'] == null
            ? null
            : readScore(Map<String, dynamic>.from(j['score'])),
        audioPath: j['audioPath'],
        rule: readRule(Map<String, dynamic>.from(j['rule'])),
      );
  static JsonObject event(LearningEvent e) => {
        'id': e.id,
        'type': e.type.name,
        'occurredAt': e.occurredAt.toUtc().toIso8601String(),
        'timeZone': e.timeZone,
        'durationSeconds': e.durationSeconds,
        'taskId': e.taskId,
        'segmentId': e.segmentId,
        'attemptId': e.attemptId,
        'source': e.source?.name,
        'status': e.status?.name,
        'taskKind': e.taskKind?.name,
        if (e.dueDate != null) 'dueDate': day(e.dueDate!),
        if (e.previousDueDate != null)
          'previousDueDate': day(e.previousDueDate!),
        if (e.undoOf != null) 'undoOf': e.undoOf,
      };
  static LearningEvent readEvent(JsonObject j) => LearningEvent(
        id: j['id'],
        type: LearningEventType.values.byName(j['type']),
        occurredAt: DateTime.parse(j['occurredAt']),
        timeZone: j['timeZone'],
        durationSeconds: j['durationSeconds'],
        taskId: j['taskId'],
        segmentId: j['segmentId'],
        attemptId: j['attemptId'],
        source: j['source'] == null
            ? null
            : AttemptSource.values.byName(j['source']),
        status: j['status'] == null
            ? null
            : AttemptStatus.values.byName(j['status']),
        taskKind: j['taskKind'] == null
            ? null
            : TaskKind.values.byName(j['taskKind']),
        dueDate: j['dueDate'] == null ? null : readDay(j['dueDate']),
        previousDueDate:
            j['previousDueDate'] == null ? null : readDay(j['previousDueDate']),
        undoOf: j['undoOf'] as String?,
      );
}
