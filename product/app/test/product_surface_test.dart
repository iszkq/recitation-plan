import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_app/design.dart';
import 'package:recitation_core/recitation_core.dart';

import 'speech_flow_test.dart' show ControlledSpeech, fixture;

Widget host(Widget child) => CupertinoApp(
  theme: Design.theme,
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalCupertinoLocalizations.delegates,
  home: child,
);

void main() {
  testWidgets('文章保存后详情更新，计划设置编辑和删除可操作', (tester) async {
    final model = await fixture();
    final article = model.articles.single;
    await tester.pumpWidget(host(ArticlePage(model: model, article: article)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑文章'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, '修改后的课文');
    await tester.enterText(find.byType(CupertinoTextField).last, '修改后的正文。');
    await tester.scrollUntilVisible(
      find.text('保存修改'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.text('修改后的课文'), findsOneWidget);
    expect(find.text('修改后的正文。'), findsOneWidget);
    final plan = model.plans.single;
    await tester.pumpWidget(host(PlanDetailPage(model: model, plan: plan)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑计划'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '修改后的计划');
    await tester.scrollUntilVisible(
      find.text('保存计划'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('保存计划'));
    await tester.pumpAndSettle();
    expect(model.plans.single.name, '修改后的计划');
    expect(find.text('修改后的计划'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除计划'));
    await tester.pumpAndSettle();
    expect(find.text('删除计划？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(model.plans, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('全部主要页面支持窄屏、大字体并生成实际界面截图', (tester) async {
    final capture = Platform.environment['CAPTURE_NATIVE_UI'] == '1';
    if (capture) {
      await tester.runAsync(() async {
        final font = File('C:/Windows/Fonts/msyh.ttc');
        if (await font.exists()) {
          final data = ByteData.sublistView(await font.readAsBytes());
          for (final family in [
            'Ahem',
            'CupertinoSystemText',
            'CupertinoSystemDisplay',
          ]) {
            await (FontLoader(family)..addFont(Future.value(data))).load();
          }
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
    final plan = await model.service.createPlan(
      name: '本月背诵计划',
      versionIds: [article.currentVersionId],
      start: model.today,
      end: model.today.add(const Duration(days: 30)),
      quota: 1,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    await model.reload();
    final task = model.dueTasks.single;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final width in (capture ? [390.0] : [390.0, 320.0])) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.5
          : 1;
      final speech = ControlledSpeech();
      final pages = <String, Widget>{
        'today': TodayPage(model: model),
        'library': LibraryPage(model: model),
        'article': ArticlePage(model: model, article: article),
        'import': ImportPage(model: model),
        'segments': SegmentPreviewPage(
          model: model,
          draft: const ImportedText(
            title: '劝学',
            segments: ['君子曰：学不可以已。', '青，取之于蓝，而青于蓝。'],
          ),
        ),
        'plans': PlansPage(model: model),
        'plan-create': PlanCreatePage(model: model, article: article),
        'plan-detail': PlanDetailPage(model: model, plan: plan),
        'plan-edit': PlanEditPage(model: model, plan: plan),
        'article-edit': ArticleEditPage(model: model, article: article),
        'reading': TaskReadingPage(model: model, task: task),
        'text': TextAssessmentPage(model: model, task: task),
        'speech': SpeechAssessmentPage(
          model: model,
          task: task,
          speechProvider: speech,
        ),
        'profile': ProfilePage(model: model),
        'reports': ReportsPage(model: model),
        'backup': BackupPage(model: model),
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
        if (capture && width == 390) {
          final rendered =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await rendered.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = await Directory('../../output/native-ui')
                .create(recursive: true);
            await File('${dir.path}/${entry.key}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1600),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} bottom at $width',
        );
        if (entry.key == 'reports') {
          for (final period in ['月报', '年报']) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 1600),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(period));
            await tester.pumpAndSettle();
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -1600),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$period at $width');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await speech.controller.close();
    }
  });
}
