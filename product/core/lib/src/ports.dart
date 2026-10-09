import 'models.dart';
import 'events.dart';

class RecitationBatch {
  const RecitationBatch(
      {this.articles = const [],
      this.versions = const [],
      this.plans = const [],
      this.tasks = const [],
      this.attempts = const [],
      this.events = const [],
      this.finalizesAttemptId,
      this.expectedTaskDueDates = const {},
      this.reschedulesPendingTasks = false});
  final List<Article> articles;
  final List<ArticleVersion> versions;
  final List<Plan> plans;
  final List<Task> tasks;
  final List<Attempt> attempts;
  final List<LearningEvent> events;

  /// A final result already persisted under this ID makes the whole batch a no-op.
  final String? finalizesAttemptId;

  /// Checked inside the serialized write, before publishing any changes.
  final Map<String, DateTime> expectedTaskDueDates;
  final bool reschedulesPendingTasks;
}

/// 领域层不依赖 Hive、SQLite 或云服务，方便本机存储和测试替换。
abstract interface class RecitationStore {
  Future<bool> writeBatch(RecitationBatch batch);
  Future<List<Article>> articles();
  Future<List<Plan>> plans();
  Future<Plan?> getPlan(String id);
  Future<Segment?> getSegment(String id);
  Future<Task?> getTask(String id);
  Future<List<Task>> tasks();
  Future<Attempt?> getAttempt(String id);
  Future<List<LearningEvent>> events();
  Future<void> saveArticle(Article article);
  Future<void> saveArticleVersion(ArticleVersion version);
  Future<void> deleteArticle(String id);
  Future<Article?> getArticle(String id);
  Future<ArticleVersion?> getArticleVersion(String id);
  Future<void> savePlan(Plan plan);
  Future<void> deletePlan(String id);
  Future<void> saveTask(Task task);
  Future<List<Task>> tasksForDay(DateTime localDay);
  Future<void> saveAttempt(Attempt attempt);
  Future<bool> hasAttempt(String id);
  Future<List<Attempt>> attemptsForSegment(String segmentId);
}

enum SpeechState { idle, recording, finalizing, ready, unavailable, failed }

class SpeechUpdate {
  const SpeechUpdate(
      {required this.state,
      this.interimText = '',
      this.finalText,
      this.confidence,
      this.error});

  final SpeechState state;
  final String interimText;
  final String? finalText;
  final double? confidence;
  final String? error;
}

/// `record` 只负责音频；真正转录由平台 Provider 实现。
abstract interface class SpeechProvider {
  Stream<SpeechUpdate> get updates;
  Future<bool> requestPermission();
  Future<void> start({required String locale});
  Future<SpeechUpdate> stopAndFinalize();
  Future<void> cancel();
}
