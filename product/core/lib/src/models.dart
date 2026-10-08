import 'package:meta/meta.dart';

enum TaskKind { newLearning, review }

enum TaskStatus { pending, completed, skipped }

enum AttemptSource { automatic, manual, assisted }

enum AttemptStatus { processing, passed, failed, needsReview, technicalFailure }

@immutable
class Article {
  const Article({
    required this.id,
    required this.title,
    this.author,
    required this.currentVersionId,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String? author;
  final String currentVersionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
}

@immutable
class ArticleVersion {
  const ArticleVersion({
    required this.id,
    required this.articleId,
    required this.version,
    required this.segments,
    required this.createdAt,
    this.changeNote,
  });

  final String id;
  final String articleId;
  final int version;
  final List<Segment> segments;
  final DateTime createdAt;
  final String? changeNote;
}

@immutable
class Segment {
  const Segment({
    required this.id,
    required this.versionId,
    required this.order,
    required this.text,
    this.title,
    this.keywords = const <String>{},
  });

  final String id;
  final String versionId;
  final int order;
  final String text;
  final String? title;
  final Set<String> keywords;
}

@immutable
class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.segmentIds,
    required this.startDate,
    required this.endDate,
    required this.dailyNewQuota,
    required this.weekdays,
    required this.rule,
    required this.timeZone,
    this.paused = false,
    this.deleted = false,
  });

  final String id;
  final String name;
  final List<String> segmentIds;
  final DateTime startDate;
  final DateTime endDate;
  final int dailyNewQuota;

  /// DateTime.weekday values: Monday=1 ... Sunday=7.
  final Set<int> weekdays;
  final AssessmentRule rule;
  final String timeZone;
  final bool paused;
  final bool deleted;
}

@immutable
class AssessmentRule {
  const AssessmentRule({
    this.accuracyThreshold = 90,
    this.coverageThreshold = 95,
    this.requireKeywords = true,
    this.ignorePunctuation = true,
  });

  final int accuracyThreshold;
  final int coverageThreshold;
  final bool requireKeywords;
  final bool ignorePunctuation;
}

@immutable
class Task {
  const Task({
    required this.id,
    required this.planId,
    required this.segmentId,
    required this.kind,
    required this.dueDate,
    this.status = TaskStatus.pending,
  });

  final String id;
  final String planId;
  final String segmentId;
  final TaskKind kind;
  final DateTime dueDate;
  final TaskStatus status;
}

@immutable
class Score {
  const Score({
    required this.accuracy,
    required this.coverage,
    required this.matched,
    required this.deleted,
    required this.substituted,
    required this.inserted,
    required this.unresolved,
  });

  final double accuracy;
  final double coverage;
  final int matched;
  final int deleted;
  final int substituted;
  final int inserted;
  final int unresolved;
}

@immutable
class Attempt {
  const Attempt({
    required this.id,
    required this.taskId,
    required this.segmentId,
    required this.source,
    required this.status,
    required this.createdAt,
    this.transcript,
    this.score,
    this.audioPath,
    this.rule = const AssessmentRule(),
  });

  final String id;
  final String taskId;
  final String segmentId;
  final AttemptSource source;
  final AttemptStatus status;
  final DateTime createdAt;
  final String? transcript;
  final Score? score;
  final String? audioPath;
  final AssessmentRule rule;
}
