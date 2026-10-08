import 'package:flutter/foundation.dart';
import 'package:recitation_core/recitation_core.dart';

class AppModel extends ChangeNotifier {
  AppModel(this.store) : service = RecitationService(store);
  final MemoryRecitationStore store;
  final RecitationService service;
  List<Article> articles = [];
  List<Plan> plans = [];
  List<Task> tasks = [];
  List<LearningEvent> events = [];
  Map<String, Segment> segments = {};
  Map<String, String> articleNames = {};
  DateTime get today {
    final local = localTime(DateTime.now().toUtc(), 'Asia/Shanghai');
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> reload() async {
    articles = await store.articles();
    plans = await store.plans();
    tasks = await store.tasks();
    events = await store.events();
    segments = {};
    articleNames = {};
    for (final task in tasks) {
      final s = await store.getSegment(task.segmentId);
      if (s != null) segments[s.id] = s;
    }
    for (final article in articles) {
      final v = await store.getArticleVersion(article.currentVersionId);
      if (v != null) {
        for (final s in v.segments) {
          segments[s.id] = s;
          articleNames[s.id] = article.title;
        }
      }
    }
    for (final s in segments.values.toList()) {
      if (articleNames.containsKey(s.id)) continue;
      final v = await store.getArticleVersion(s.versionId);
      for (final a in articles) {
        if (a.id == v?.articleId) articleNames[s.id] = a.title;
      }
    }
    notifyListeners();
  }

  List<Task> get dueTasks =>
      tasks
          .where(
            (t) =>
                !t.dueDate.isAfter(today) &&
                t.status == TaskStatus.pending &&
                plans.any((p) => p.id == t.planId && !p.paused),
          )
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  String taskTitle(Task t) =>
      '${articleNames[t.segmentId] ?? '文章'} · 第${(segments[t.segmentId]?.order ?? 0) + 1}节';
  LearningReport report(ReportPeriod period, DateTime anchor) => buildReport(
    period: period,
    anchor: anchor,
    asOf: today,
    events: events,
    localDate: eventLocalTime,
  );
}
