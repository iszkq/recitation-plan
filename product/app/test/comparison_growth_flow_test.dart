import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/design.dart';
import 'package:recitation_app/growth_page.dart';
import 'package:recitation_app/reminders.dart';
import 'package:recitation_app/text_comparison.dart';
import 'package:recitation_core/recitation_core.dart';

import 'local_flow_test.dart' show revealAction;
import 'product_surface_test.dart' show host;
import 'speech_flow_test.dart' show ControlledSpeech, fixture;

void main() {
  testWidgets('校对和花园窄屏渲染', (tester) async {
    final capture = Platform.environment['CAPTURE_NATIVE_UI'] == '1';
    if (capture) {
      await tester.runAsync(() async {
        final bytes = ByteData.sublistView(
          await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
        );
        for (final family in [
          'Ahem',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
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
    final model = await fixture();
    for (final width in [390.0, 320.0]) {
      if (capture &&
          Platform.environment['UI_CAPTURE_WIDTH'] != null &&
          width.toInt().toString() != Platform.environment['UI_CAPTURE_WIDTH']) {
        continue;
      }
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.5
          : 1;
      final pages = <String, Widget>{
        'voice-comparison': _comparisonPage(true),
        'text-comparison': _comparisonPage(false),
        'learning-garden': GrowthPage(model: model),
      };
      for (final page in pages.entries) {
        if (capture &&
            Platform.environment['UI_CAPTURE_PAGE'] != null &&
            page.key != Platform.environment['UI_CAPTURE_PAGE']) {
          continue;
        }
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: host(page.value)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${page.key} $width');
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../output/native-ui/${page.key}-${width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${page.key} bottom');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
  testWidgets('文字提交后高亮错漏多字，再考核隐藏原文和差异', (tester) async {
    final model = await fixture();
    final article = await model.service.importArticle(
      title: '校对课文',
      text: '甲乙丙丁戊己。',
    );
    final plan = await model.service.createPlan(
      name: '校对计划',
      versionIds: [article.currentVersionId],
      start: model.today,
      end: model.today,
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    await model.reload();
    final task = model.tasks.singleWhere((t) => t.planId == plan.id);
    await tester.pumpWidget(host(TextAssessmentPage(model: model, task: task)));
    await tester.enterText(find.byType(CupertinoTextField), '甲丙错戊己多');
    await tester.tap(find.text('提交并校对'));
    await tester.pumpAndSettle();
    final compare = find.byType(TextComparison);
    await tester.scrollUntilVisible(
      compare,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('逐字对比'), findsOneWidget);
    expect(find.textContaining('缺少「乙」'), findsOneWidget);
    expect(find.textContaining('应为「丁」'), findsOneWidget);
    expect(find.textContaining('多出「多」'), findsOneWidget);
    final rich = tester.widgetList<SelectableText>(find.byType(SelectableText));
    final spans = rich.map((w) => w.textSpan!).expand((s) => s.children!);
    expect(
      spans.whereType<TextSpan>().any(
        (s) => s.style?.backgroundColor == Design.errorSoft,
      ),
      isTrue,
    );
    expect(
      spans.whereType<TextSpan>().any(
        (s) => s.style?.decoration == TextDecoration.lineThrough,
      ),
      isTrue,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再次考核'));
    await tester.pumpAndSettle();
    expect(find.byType(TextComparison), findsNothing);
    expect(find.byType(CupertinoTextField), findsOneWidget);
  });
  testWidgets('语音同音自动校正，默认展示校正内容，原始转录可展开且保留', (tester) async {
    final model = await fixture();
    final speech = ControlledSpeech();
    await tester.pumpWidget(
      host(
        SpeechAssessmentPage(
          model: model,
          task: model.dueTasks.single,
          speechProvider: speech,
        ),
      ),
    );
    await revealAction(tester, '开始录音');
    await tester.tap(find.text('开始录音'));
    await tester.pumpAndSettle();
    speech.finalized.complete(
      const SpeechUpdate(state: SpeechState.ready, finalText: '学不可以蚁'),
    );
    await revealAction(tester, '结束并校对');
    await tester.tap(find.text('结束并校对'));
    await tester.pumpAndSettle();
    expect(model.attempts.single.status, AttemptStatus.passed);
    expect(model.attempts.single.transcript, '学不可以蚁');
    await tester.scrollUntilVisible(
      find.byType(TextComparison),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.textContaining('原始转录：'), findsNothing);
    expect(find.textContaining('「蚁」→「已」'), findsOneWidget);
    await tester.ensureVisible(find.text('查看原始转录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看原始转录'));
    await tester.pumpAndSettle();
    expect(find.text('原始转录：学不可以蚁'), findsOneWidget);
  });
  testWidgets('成长来自真实学习，修改周目标保存重开，花园支持窄屏大字体', (tester) async {
    final model = await fixture();
    await tester.pumpWidget(host(GrowthPage(model: model)));
    await tester.pumpAndSettle();
    expect(find.text('累计学习 0 天'), findsOneWidget);
    await tester.tap(find.text('增加'));
    await tester.pumpAndSettle();
    expect(model.preferences.weeklyGoalDays, 4);
    expect(
      ReminderPreferences.fromJson(model.preferences.toJson()).weeklyGoalDays,
      4,
    );
    expect(ReminderPreferences.fromJson({}).weeklyGoalDays, 3);
    await model.service.submitFinalTranscript(
      taskId: model.dueTasks.single.id,
      attemptId: 'growth',
      transcript: '学不可以已',
      isFinal: true,
    );
    await model.reload();
    await tester.pumpAndSettle();
    expect(find.text('累计学习 1 天'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('初次掌握 · 已获得'), findsOneWidget);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    await tester.pumpWidget(host(GrowthPage(model: model)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      host(
        TextComparison(
          original: '甲乙丙丁',
          attempt: Attempt(
            id: 'diff',
            taskId: 'task',
            segmentId: 'segment',
            source: AttemptSource.automatic,
            status: AttemptStatus.failed,
            createdAt: DateTime.utc(2026),
            transcript: '甲丙错多',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _comparisonPage(bool voice) => CupertinoPageScaffold(
  navigationBar: CupertinoNavigationBar(middle: Text(voice ? '背诵校对' : '默写校对')),
  child: SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(Design.inset),
      children: [
        TextComparison(
          original: voice ? '青，取之于蓝。' : '甲乙丙丁戊己。',
          attempt: Attempt(
            id: 'visual',
            taskId: 'task',
            segmentId: 'segment',
            source: AttemptSource.automatic,
            status: AttemptStatus.failed,
            createdAt: DateTime.utc(2026),
            transcript: voice ? '清，取于兰，啊。' : '甲丙错戊己多。',
            input: voice ? AssessmentInput.speech : AssessmentInput.text,
            acceptHomophones: voice,
          ),
        ),
      ],
    ),
  ),
);
