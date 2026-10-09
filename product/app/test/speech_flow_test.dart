import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_core/recitation_core.dart';

class ControlledSpeech implements SpeechProvider {
  final controller = StreamController<SpeechUpdate>.broadcast();
  final finalized = Completer<SpeechUpdate>();
  bool permitted = true;
  int cancels = 0;
  @override
  Stream<SpeechUpdate> get updates => controller.stream;
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<void> start({required String locale}) async {
    controller.add(const SpeechUpdate(state: SpeechState.recording));
  }

  @override
  Future<SpeechUpdate> stopAndFinalize() => finalized.future;
  @override
  Future<void> cancel() async {
    cancels++;
  }
}

Future<AppModel> fixture() async {
  final model = AppModel(MemoryRecitationStore());
  final a = await model.service.importArticle(title: '课文', text: '学不可以已。');
  await model.service.createPlan(
    name: '计划',
    versionIds: [a.currentVersionId],
    start: model.today,
    end: model.today.add(const Duration(days: 10)),
    quota: 1,
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );
  await model.reload();
  return model;
}

void main() {
  testWidgets('语音临时转录隐藏且不能打卡，结束后只用最终转录', (tester) async {
    final model = await fixture();
    final task = model.dueTasks.single;
    final speech = ControlledSpeech();
    await tester.pumpWidget(
      CupertinoApp(
        home: SpeechAssessmentPage(
          model: model,
          task: task,
          speechProvider: speech,
        ),
      ),
    );
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    speech.controller.add(
      const SpeechUpdate(state: SpeechState.recording, interimText: '学不可以已'),
    );
    await tester.pump();
    expect(find.text('学不可以已'), findsNothing);
    expect(await model.store.attemptsForSegment(task.segmentId), isEmpty);
    expect((await model.store.getTask(task.id))!.status, TaskStatus.pending);
    await tester.tap(find.text('结束并校对'));
    await tester.pump();
    expect((await model.store.getTask(task.id))!.status, TaskStatus.pending);
    speech.finalized.complete(
      const SpeechUpdate(state: SpeechState.ready, finalText: '学不可以已'),
    );
    await tester.pumpAndSettle();
    expect(find.text('考核通过'), findsOneWidget);
    expect((await model.store.getTask(task.id))!.status, TaskStatus.completed);
    expect(await model.store.attemptsForSegment(task.segmentId), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await speech.controller.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('语音自动结束能完成校对，重考时隐藏校对正文', (tester) async {
    final model = await fixture();
    final task = model.dueTasks.single;
    final speech = ControlledSpeech();
    await tester.pumpWidget(
      CupertinoApp(
        home: SpeechAssessmentPage(
          model: model,
          task: task,
          speechProvider: speech,
        ),
      ),
    );
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    speech.controller.add(
      const SpeechUpdate(state: SpeechState.ready, finalText: '学不可以已'),
    );
    await tester.pumpAndSettle();
    expect(find.text('考核通过'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('再次考核'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.widgetWithText(CupertinoButton, '再次考核'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoButton, '再次考核'));
    await tester.pump();
    expect(find.textContaining('原文：'), findsNothing);
    expect(find.textContaining('你的背诵：'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await speech.controller.close();
  });

  testWidgets('语音拒绝权限可重试，中断记录不完成任务', (tester) async {
    final model = await fixture();
    final task = model.dueTasks.single;
    final speech = ControlledSpeech()..permitted = false;
    await tester.pumpWidget(
      CupertinoApp(
        home: SpeechAssessmentPage(
          model: model,
          task: task,
          speechProvider: speech,
        ),
      ),
    );
    await tester.tap(find.text('开始录音'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要麦克风'), findsOneWidget);
    expect(await model.store.attemptsForSegment(task.segmentId), isEmpty);
    speech.permitted = true;
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    speech.controller.add(
      const SpeechUpdate(state: SpeechState.failed, error: '录音中断，请重试'),
    );
    await tester.pumpAndSettle();
    expect(find.text('录音中断，请重试'), findsOneWidget);
    expect((await model.store.getTask(task.id))!.status, TaskStatus.pending);
    expect(
      (await model.store.attemptsForSegment(task.segmentId)).single.status,
      AttemptStatus.technicalFailure,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await speech.controller.close();
  });
}
