import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_core/recitation_core.dart';

import 'product_surface_test.dart' show host;
import 'local_flow_test.dart' show revealAction;
import 'speech_flow_test.dart' show ControlledSpeech;

Future<AppModel> arrange() async {
  final model = AppModel(MemoryRecitationStore());
  final article = await model.service.importPreparedArticle(
    const ImportedText(title: '课文', segments: ['学不可以已。', '青取之于蓝。', '冰水为之。']),
  );
  final today = model.today;
  await model.service.createPlan(
    name: '计划',
    versionIds: [article.currentVersionId],
    start: today,
    end: DateTime(today.year, today.month, today.day + 10),
    quota: 1,
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );
  await model.reload();
  return model;
}

void main() {
  testWidgets('灵活排期页面支持窄屏大字体并可导出实际截图', (tester) async {
    final capture = Platform.environment['CAPTURE_NATIVE_UI'] == '1';
    if (capture) {
      await tester.runAsync(() async {
        final font = ByteData.sublistView(
          await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
        );
        for (final family in [
          'Ahem',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(Future.value(font))).load();
        }
        final icons = ByteData.sublistView(
          await File(
            '../../.tools/pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
          ).readAsBytes(),
        );
        await (FontLoader(
          'packages/cupertino_icons/CupertinoIcons',
        )..addFont(Future.value(icons))).load();
      });
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final model = await arrange();
    for (final width in [390.0, 320.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.5
          : 1;
      final pages = {
        'today-flexible': TodayPage(model: model),
        'upcoming-flexible': UpcomingTasksPage(model: model),
      };
      for (final entry in pages.entries) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: host(entry.value)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} at $width',
        );
        if (capture) {
          final rendered =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await rendered.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = await Directory('../../output/native-ui')
                .create(recursive: true);
            await File('${directory.path}/${entry.key}-${width.toInt()}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1000),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} bottom at $width',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
  testWidgets('明天语音提前考核只用最终转录完成任务', (tester) async {
    final model = await arrange();
    await model.service.submitFinalTranscript(
      taskId: model.dueTasks.single.id,
      attemptId: 'today',
      transcript: '学不可以已',
      isFinal: true,
    );
    await model.reload();
    final task = model
        .upcomingTasks(1)
        .firstWhere((t) => t.kind == TaskKind.newLearning);
    final speech = ControlledSpeech();
    await tester.pumpWidget(
      host(
        SpeechAssessmentPage(
          model: model,
          task: task,
          allowEarly: true,
          speechProvider: speech,
        ),
      ),
    );
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    speech.controller.add(
      const SpeechUpdate(state: SpeechState.recording, interimText: '青取之于蓝'),
    );
    await tester.pump();
    expect((await model.store.getTask(task.id))!.status, TaskStatus.pending);
    speech.controller.add(
      const SpeechUpdate(state: SpeechState.ready, finalText: '青取之于蓝'),
    );
    await tester.pumpAndSettle();
    expect(find.text('考核通过'), findsOneWidget);
    expect((await model.store.getTask(task.id))!.status, TaskStatus.completed);
    await tester.pumpWidget(const SizedBox.shrink());
    await speech.controller.close();
  });
  testWidgets('延期取消不改计划，确认后今日清空且明天合并任务', (tester) async {
    final model = await arrange();
    final original = model.dueTasks.single;
    await tester.pumpWidget(host(TodayPage(model: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('将剩余任务延至明天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(model.dueTasks, hasLength(1));
    await tester.tap(find.text('将剩余任务延至明天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延至明天'));
    await tester.pumpAndSettle();
    expect(model.dueTasks, isEmpty);
    expect(model.upcomingTasks(1), hasLength(2));
    expect(model.postponedToday, 1);
    expect(
      (await model.store.getTask(original.id))!.status,
      TaskStatus.pending,
    );
    expect(find.text('剩余任务已延至明天'), findsOneWidget);
    expect(find.text('今天的任务全部完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('提前页先锁定，今日完成后可进入后天文字考核且完成只记一次', (tester) async {
    final model = await arrange();
    await tester.pumpWidget(host(UpcomingTasksPage(model: model)));
    await tester.pumpAndSettle();
    expect(find.text('今日队列尚未完成'), findsOneWidget);
    final firstTile = tester.widget<CupertinoListTile>(
      find.byType(CupertinoListTile).first,
    );
    expect(firstTile.onTap, isNull);
    final todayTask = model.dueTasks.single;
    await model.service.submitFinalTranscript(
      taskId: todayTask.id,
      attemptId: 'today-pass',
      transcript: '学不可以已',
      isFinal: true,
    );
    await model.reload();
    await tester.pumpAndSettle();
    await tester.tap(find.text('后天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课文 · 第3节'));
    await tester.pumpAndSettle();
    expect(find.text('冰水为之。'), findsOneWidget);
    await revealAction(tester, '开始无提示考核');
    await tester.tap(find.text('开始无提示考核'));
    await tester.pumpAndSettle();
    expect(find.text('冰水为之。'), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField), '冰水为之');
    await revealAction(tester, '提交并校对');
    await tester.tap(find.text('提交并校对'));
    await tester.pumpAndSettle();
    expect(find.text('考核通过'), findsOneWidget);
    expect(model.upcomingTasks(2).single.status, TaskStatus.completed);
    expect(
      model.taskScheduleLabel(model.upcomingTasks(2).single),
      contains('提前完成'),
    );
    expect(
      model.events.where((e) => e.type == LearningEventType.taskCompleted),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
