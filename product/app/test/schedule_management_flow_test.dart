import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_app/reminders.dart';
import 'package:recitation_app/schedule_pages.dart';
import 'package:recitation_app/snapshot_pages.dart';
import 'package:recitation_core/recitation_core.dart';

import 'product_surface_test.dart' show host;
import 'local_flow_test.dart' show revealAction;
import 'reminders_test.dart' show FakeReminders;

class MemorySnapshots extends LocalSnapshotRepository {
  MemorySnapshots() : super('unused');
  final values = <String, String>{};
  final kinds = <String, LocalSnapshotKind>{};
  @override
  Future<void> save(
    String text, {
    LocalSnapshotKind kind = LocalSnapshotKind.checkpoint,
  }) async {
    final id = 'snapshot-${values.length}';
    values[id] = text;
    kinds[id] = kind;
  }

  @override
  Future<String> read(String id) async => values[id]!;
  @override
  Future<List<LocalSnapshot>> list() async => [
    for (final entry in values.entries)
      LocalSnapshot(
        id: entry.key,
        kind: kinds[entry.key]!,
        createdAt: ArchiveBundle.decode(entry.value).manifest.exportedAt,
        counts: ArchiveBundle.decode(entry.value).manifest.counts,
        valid: true,
      ),
  ];
}

Future<AppModel> arrange({
  int count = 4,
  LocalSnapshotRepository? snapshots,
  ReminderProvider? provider,
}) async {
  final model = AppModel(
    MemoryRecitationStore(),
    clock: () => DateTime.utc(2026, 10, 9, 4),
    snapshots: snapshots,
    reminderProvider: provider,
  );
  final article = await model.service.importPreparedArticle(
    ImportedText(
      title: '课文',
      segments: List.generate(count, (i) => '第${i + 1}段学不可以已。'),
    ),
  );
  await model.service.createPlan(
    name: '十月计划',
    versionIds: [article.currentVersionId],
    start: model.today,
    end: DateTime(2026, 10, 31),
    quota: 1,
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );
  await model.reload();
  return model;
}

Future<void> withBacklog(AppModel model) async {
  final task = model.tasks.first;
  final segment = model.segments[task.segmentId]!;
  // Test fixture writes valid past review tasks without manufacturing passes.
  final plan = model.plans.single;
  final reviews = createReviewTasks(
    plan: plan,
    segmentId: segment.id,
    passedAt: DateTime(2026, 10, 1),
  );
  await model.store.writeBatch(RecitationBatch(tasks: reviews));
  await model.reload();
}

void main() {
  testWidgets('月历切换月份和选择日期，任务数按实际排期显示', (tester) async {
    final model = await arrange();
    final task = model.tasks.first;
    await model.service.submitFinalTranscript(
      taskId: task.id,
      attemptId: 'passed',
      transcript: model.segments[task.segmentId]!.text,
      isFinal: true,
    );
    await model.reload();
    await tester.pumpWidget(host(ScheduleCalendarPage(model: model)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('新背 1 · 复习 0 · 已完成 1'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('新背 1 · 复习 1 · 已完成 0'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(CupertinoButton, '回到今天'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.widgetWithText(CupertinoButton, '回到今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
  });
  testWidgets('修改配额先预览再保存，确认取消不改档案，保存更新提醒', (tester) async {
    final provider = FakeReminders();
    final model = await arrange(provider: provider);
    await model.savePreferences(studyEnabled: true);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => ScheduleReplanPage(
                  model: model,
                  planId: model.plans.single.id,
                ),
              ),
            ),
            child: const Text('打开排期'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开排期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('增加'));
    await tester.pumpAndSettle();
    await revealAction(tester, '预览安排');
    await tester.tap(find.text('预览安排'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共有 4 个待完成任务'), findsOneWidget);
    expect(find.textContaining('预计2026年10月10日完成'), findsOneWidget);
    final before = model.store.snapshot();
    await revealAction(tester, '保存安排');
    await tester.tap(find.text('保存安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(model.store.snapshot(), before);
    await tester.tap(find.text('保存安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '保存安排'));
    await tester.pumpAndSettle();
    expect(model.plans.single.dailyNewQuota, 2);
    expect(model.pendingOn(DateTime(2026, 10, 10)), 2);
    expect(find.text('打开排期'), findsOneWidget);
    expect(provider.scheduled, isNotEmpty);
    expect(model.tasks.where((t) => t.status == TaskStatus.completed), isEmpty);
  });
  testWidgets('今日积压入口可预览分日处理，批量调整不伪装延期撤销', (tester) async {
    final model = await arrange();
    await withBacklog(model);
    await tester.pumpWidget(host(TodayPage(model: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('整理积压复习'));
    await tester.pumpAndSettle();
    await revealAction(tester, '预览安排');
    await tester.tap(find.text('预览安排'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共有 3 个待完成任务'), findsOneWidget);
    await revealAction(tester, '保存安排');
    await tester.tap(find.text('保存安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '保存安排'));
    await tester.pumpAndSettle();
    expect(model.overdueReviews, isEmpty);
    final reviews = model.tasks
        .where(
          (t) =>
              t.kind == TaskKind.review &&
              !t.dueDate.isAfter(DateTime(2026, 10, 11)),
        )
        .toList();
    expect(reviews.map((t) => t.dueDate).toSet(), hasLength(3));
    expect(reviews.every((t) => t.status == TaskStatus.pending), isTrue);
    expect(model.canUndoPostponement(model.events.last), isFalse);
    expect(model.postponedToday, 0);
  });
  testWidgets('预览期间完成任务使保存失效，不覆盖成绩', (tester) async {
    final model = await arrange();
    await tester.pumpWidget(
      host(ScheduleReplanPage(model: model, planId: model.plans.single.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('增加'));
    await revealAction(tester, '预览安排');
    await tester.tap(find.text('预览安排'));
    await tester.pumpAndSettle();
    final task = model.tasks.first;
    await model.service.submitFinalTranscript(
      taskId: task.id,
      attemptId: 'concurrent',
      transcript: model.segments[task.segmentId]!.text,
      isFinal: true,
    );
    await model.reload();
    await revealAction(tester, '保存安排');
    await tester.tap(find.text('保存安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '保存安排'));
    await tester.pumpAndSettle();
    expect(find.textContaining('重新预览'), findsOneWidget);
    expect(model.tasks.first.status, TaskStatus.completed);
    expect(model.plans.single.dailyNewQuota, 1);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('保存安排'), findsNothing);
  });

  testWidgets('快照恢复需确认，保留恢复前档案并能恢复回来，取消不改数据', (tester) async {
    final snapshots = MemorySnapshots();
    final model = await arrange(count: 1, snapshots: snapshots);
    await snapshots.save(
      BackupService(model.store, profileId: 'local').export(),
    );
    await model.service.importArticle(title: '新文章', text: '青取之于蓝。');
    await model.reload();
    await tester.pumpWidget(host(LocalSnapshotsPage(model: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('手动保存 ·'));
    await tester.pumpAndSettle();
    expect(find.text('恢复到这个时间点？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(model.articles, hasLength(2));
    await tester.tap(find.textContaining('手动保存 ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复快照'));
    await tester.pumpAndSettle();
    expect(find.text('快照已恢复'), findsOneWidget);
    expect(model.articles, hasLength(1));
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('恢复前档案 ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复快照'));
    await tester.pumpAndSettle();
    expect(model.articles, hasLength(2));
  });
  testWidgets('月历排期快照页面支持320窄屏大字体，截图及触控范围可检查', (tester) async {
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
    final snapshots = MemorySnapshots();
    final model = await arrange(snapshots: snapshots);
    await withBacklog(model);
    await snapshots.save(
      BackupService(model.store, profileId: 'local').export(at: model.clock()),
    );
    for (final width in [390.0, 320.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.5
          : 1;
      final pages = <String, Widget>{
        'schedule-calendar': ScheduleCalendarPage(model: model),
        'schedule-replan': ScheduleReplanPage(
          model: model,
          planId: model.plans.single.id,
        ),
        'review-backlog': ScheduleReplanPage(model: model),
        'local-snapshots': LocalSnapshotsPage(model: model),
      };
      for (final entry in pages.entries) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: host(entry.value)),
        );
        await tester.pumpAndSettle();
        if (entry.key.contains('replan') || entry.key == 'review-backlog') {
          await revealAction(tester, '预览安排');
          await tester.tap(find.text('预览安排'));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 1000),
          );
          await tester.pumpAndSettle();
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} at $width',
        );
        if (entry.key == 'schedule-calendar') {
          final cell = find
              .ancestor(
                of: find.text('9').first,
                matching: find.byType(CupertinoButton),
              )
              .first;
          expect(tester.getSize(cell).width, greaterThanOrEqualTo(44));
        }
        if (capture) {
          await tester.runAsync(() async {
            final rendered =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await rendered.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../output/native-ui/${entry.key}-${width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${entry.key} bottom');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
