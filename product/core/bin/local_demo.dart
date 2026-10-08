import 'dart:convert';
import 'dart:io';
import 'package:recitation_core/recitation_core.dart';

/// Exercises real storage and services; no fake microphone, login or UI data.
Future<void> main(List<String> args) async {
  final directory =
      Directory(args.isEmpty ? '.dart_tool/local-demo' : args.first);
  await directory.create(recursive: true);
  var store = await HiveRecitationStore.open(directory.path);
  try {
    final now = DateTime.now().toUtc();
    final local = localTime(now, 'Asia/Shanghai');
    final today = DateTime(local.year, local.month, local.day);
    final service = RecitationService(store);
    final article = await service.importArticle(
        title: '本机验证：劝学', text: '学不可以已。\n\n青，取之于蓝，而青于蓝。');
    final plan = await service.createPlan(
        name: '本机闭环验证',
        versionIds: [article.currentVersionId],
        start: today,
        end: DateTime(today.year, today.month, today.day + 30),
        quota: 1,
        weekdays: {1, 2, 3, 4, 5, 6, 7});
    final task = (await store.tasks()).firstWhere(
        (t) => t.planId == plan.id && t.kind == TaskKind.newLearning);
    final result = await service.submitFinalTranscript(
        taskId: task.id,
        attemptId: createLocalId(),
        transcript: '学不可以已',
        isFinal: true,
        activeSeconds: 90);
    final archive = BackupService(store, profileId: 'local-demo').export();
    await File('${directory.path}/backup.json')
        .writeAsString(archive, flush: true);
    await store.close();
    store = await HiveRecitationStore.open(directory.path);
    final report = buildReport(
        period: ReportPeriod.week,
        anchor: today,
        asOf: today,
        events: await store.events(),
        localDate: eventLocalTime);
    final resultJson = {
      '说明': '真实本机持久化验证，考核输入为文字；没有调用麦克风或语音服务',
      '文章标题': (await store.getArticle(article.id))!.title,
      '考核结果': result.status.name,
      '正确率': result.score!.accuracy,
      '关闭重开后任务状态': (await store.getTask(task.id))!.status.name,
      '本计划复习任务数': (await store.tasks())
          .where((t) => t.planId == plan.id && t.kind == TaskKind.review)
          .length,
      '周报': {
        '到期任务': report.dueTasks,
        '完成任务': report.completedTasks,
        '新掌握小节': report.newMasteredSegments,
        '打卡日': report.checkInDays,
        '有效分钟': report.focusMinutes
      },
      '档案校验成功': ArchiveBundle.decode(archive).manifest.formatVersion == 1,
    };
    final formatted = const JsonEncoder.withIndent('  ').convert(resultJson);
    await File('${directory.path}/verification.json')
        .writeAsString(formatted, flush: true);
    stdout.writeln(formatted);
  } finally {
    await store.close();
  }
}
