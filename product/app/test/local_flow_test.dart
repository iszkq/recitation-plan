import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_core/recitation_core.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_app/design.dart';

Future<void> revealAction(WidgetTester tester, String label) async {
  final target = find.widgetWithText(PrimaryAction, label);
  final scrollable = find
      .descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空文库、导入分段与真实保存', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final store = MemoryRecitationStore();
    final model = AppModel(store);
    await model.reload();
    await tester.pumpWidget(RecitationApp(model: model));
    await tester.pumpAndSettle();
    expect(find.text('先导入一篇文章'), findsOneWidget);
    await tester.tap(find.text('导入文章'));
    await tester.pumpAndSettle();
    final inputs = find.byType(CupertinoTextField);
    await tester.enterText(inputs.at(0), '我的课文');
    await tester.enterText(inputs.at(2), '第一段。\n\n第二段。');
    await revealAction(tester, '预览分段');
    await tester.tap(find.text('预览分段'));
    await tester.pumpAndSettle();
    expect(find.text('共 2 节 · 8 字'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField).first, '');
    await revealAction(tester, '保存文章');
    await tester.tap(find.text('保存文章'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法完成'), findsOneWidget);
    expect(await store.articles(), isEmpty);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, '第一段。');
    await revealAction(tester, '保存文章');
    await tester.tap(find.text('保存文章'));
    await tester.pumpAndSettle();
    expect((await store.articles()).single.title, '我的课文');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字考核完成任务且重考隐藏原文', (tester) async {
    final store = MemoryRecitationStore();
    final model = AppModel(store);
    final a = await model.service.importArticle(title: '劝学', text: '学不可以已。');
    final d = model.today;
    await model.service.createPlan(
      name: '今日计划',
      versionIds: [a.currentVersionId],
      start: d,
      end: DateTime(d.year, d.month, d.day + 10),
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    await model.reload();
    final task = model.dueTasks.single;
    await tester.pumpWidget(
      CupertinoApp(
        home: TextAssessmentPage(model: model, task: task),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('原文：'), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField), '学不可以已');
    await tester.tap(find.text('提交并校对'));
    await tester.pumpAndSettle();
    expect(find.text('考核通过'), findsOneWidget);
    expect((await store.getTask(task.id))!.status, TaskStatus.completed);
    await tester.tap(find.text('再次考核'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原文：'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多篇计划选择并暂停继续', (tester) async {
    final model = AppModel(MemoryRecitationStore());
    final first = await model.service.importArticle(title: '甲篇', text: '甲段。');
    await model.service.importArticle(title: '乙篇', text: '乙段。');
    await model.reload();
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => PlanCreatePage(model: model, article: first),
                ),
              ),
              child: const Text('进入计划表单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入计划表单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划文章 · 1篇'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙篇'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('计划文章 · 2篇'), findsOneWidget);
    await revealAction(tester, '创建计划');
    await tester.tap(find.text('创建计划'));
    await tester.pumpAndSettle();
    final plan = model.plans.single;
    expect(plan.segmentIds, hasLength(2));
    await tester.pumpWidget(
      CupertinoApp(
        home: PlanDetailPage(model: model, plan: plan),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(model.plans.single.paused, isTrue);
    expect(model.dueTasks, isEmpty);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(model.plans.single.paused, isFalse);
    expect(model.dueTasks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建计划后显示今日任务，阅读后无提示考核', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final model = AppModel(MemoryRecitationStore());
    await model.service.importArticle(title: '劝学', text: '学不可以已。');
    await model.reload();
    await tester.pumpWidget(RecitationApp(model: model));
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('劝学'));
    await tester.pumpAndSettle();
    await revealAction(tester, '创建计划');
    await tester.tap(find.text('创建计划'));
    await tester.pumpAndSettle();
    expect(model.plans.single.rule.accuracyThreshold, 90);
    await tester.tap(find.text('今日').last);
    await tester.pumpAndSettle();
    expect(find.text('今天还有 1 个任务'), findsOneWidget);
    await tester.tap(find.text('劝学 · 第1节'));
    await tester.pumpAndSettle();
    expect(find.text('学不可以已。'), findsOneWidget);
    await tester.tap(find.text('开始无提示考核'));
    await tester.pumpAndSettle();
    expect(find.text('学不可以已。'), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField), '学不可以已');
    await tester.tap(find.text('提交并校对'));
    await tester.pumpAndSettle();
    expect(model.dueTasks, isEmpty);
    expect(model.report(ReportPeriod.week, model.today).completedTasks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日和计划窄屏、大字体布局以及原生截图', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    if (Platform.environment['CAPTURE_NATIVE_UI'] == '1') {
      await tester.runAsync(() async {
        final font = File('C:/Windows/Fonts/msyh.ttc');
        if (!await font.exists()) return;
        final bytes = ByteData.sublistView(await font.readAsBytes());
        for (final family in [
          'Ahem',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
        final icons = File(
          '../../.tools/pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
        );
        if (await icons.exists()) {
          await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes())),
              ))
              .load();
        }
      });
    }
    final model = AppModel(MemoryRecitationStore());
    final article = await model.service.importArticle(
      title: '劝学',
      author: '荀子',
      text: '君子曰：学不可以已。\n\n青，取之于蓝，而青于蓝；冰，水为之，而寒于水。',
    );
    await model.service.createPlan(
      name: '本月背诵计划',
      versionIds: [article.currentVersionId],
      start: model.today,
      end: model.today.add(const Duration(days: 30)),
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    await model.reload();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final width in [390.0, 320.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.5
          : 1;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: RecitationApp(model: model),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 390 && Platform.environment['CAPTURE_NATIVE_UI'] == '1') {
        final rendered =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture = await rendered.toImage(pixelRatio: 2);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory(
            Platform.environment['NATIVE_UI_OUTPUT'] ??
                '../../output/native-ui',
          ).create(recursive: true);
          await File('${dir.path}/today.png')
              .writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.pumpWidget(
        CupertinoApp(
          home: PlanCreatePage(model: model, article: article),
        ),
      );
      await tester.pumpAndSettle();
      await revealAction(tester, '创建计划');
      expect(tester.takeException(), isNull);
    }
  });
}
