import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:recitation_app/app_model.dart';
import 'package:recitation_app/app.dart';
import 'package:recitation_app/reminders.dart';
import 'package:recitation_app/reminder_settings.dart';
import 'package:recitation_core/recitation_core.dart';

import 'product_surface_test.dart' show host;

class FakeReminders implements ReminderProvider {
  ReminderPermission status = ReminderPermission.allowed;
  List<LocalReminder> scheduled = [];
  int requests = 0;
  bool fail = false;
  @override
  Future<ReminderPermission> permission() async => status;
  @override
  Future<ReminderPermission> requestPermission() async {
    requests++;
    return status;
  }

  @override
  Future<void> replace(List<LocalReminder> values) async {
    if (fail) throw StateError('unavailable');
    scheduled = values;
  }
}

class FailingPreferences extends MemoryPreferencesStore {
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<ReminderPreferences> read() async {
    if (failRead) throw const FormatException('corrupt');
    return super.read();
  }

  @override
  Future<void> write(ReminderPreferences next) async {
    if (failWrite) throw const FileSystemException('full');
    await super.write(next);
  }
}

Future<AppModel> fixture(
  FakeReminders provider, {
  PreferencesStore? settings,
  DateTime Function()? clock,
}) async {
  final model = AppModel(
    MemoryRecitationStore(),
    reminderProvider: provider,
    preferencesStore: settings,
    clock: clock ?? () => DateTime.utc(2026, 10, 8, 4),
  );
  final article = await model.service.importArticle(
    title: '课文',
    text: '学不可以已。',
  );
  await model.service.createPlan(
    name: '计划',
    versionIds: [article.currentVersionId],
    start: model.today,
    end: DateTime(2026, 11, 10),
    quota: 1,
    weekdays: {1, 2, 3, 4, 5, 6, 7},
  );
  await model.reload();
  return model;
}

void main() {
  test('默认关闭且不自动申请权限；开启后延期撤销暂停完成均更新通知', () async {
    final provider = FakeReminders();
    final model = await fixture(provider);
    expect(provider.requests, 0);
    expect(provider.scheduled, isEmpty);
    await model.savePreferences(studyEnabled: true, backupEnabled: true);
    expect(provider.scheduled, hasLength(31));
    expect(provider.scheduled.first.at, DateTime.utc(2026, 10, 8, 12));
    final task = model.tasks.single;
    await model.service.postponeTasks([task.id], DateTime(2026, 10, 12));
    await model.reload();
    expect(provider.scheduled.first.at, DateTime.utc(2026, 10, 12, 12));
    await model.service.undoPostponement(model.events.last.id);
    await model.reload();
    expect(provider.scheduled.first.at, DateTime.utc(2026, 10, 8, 12));
    await model.service.setPlanPaused(task.planId, true);
    await model.reload();
    expect(provider.scheduled.map((r) => r.id), ['recitation.backup']);
    await model.service.setPlanPaused(task.planId, false);
    await model.service.submitFinalTranscript(
      taskId: task.id,
      attemptId: 'pass',
      transcript: '学不可以已',
      isFinal: true,
    );
    await model.reload();
    // First review is tomorrow; today's completed task no longer triggers reminders.
    expect(provider.scheduled.first.at, DateTime.utc(2026, 10, 9, 12));
    await model.savePreferences(studyEnabled: false, backupEnabled: false);
    expect(provider.scheduled, isEmpty);
  });
  test('通知权限撤回会取消排期，调度失败不会丢学习数据并可重试', () async {
    final provider = FakeReminders();
    final model = await fixture(provider);
    await model.savePreferences(studyEnabled: true);
    provider.status = ReminderPermission.denied;
    await model.reload();
    expect(provider.scheduled, isEmpty);
    expect(model.preferences.studyEnabled, isTrue);
    provider.status = ReminderPermission.allowed;
    provider.fail = true;
    await model.reload();
    expect(model.reminderError, isNotNull);
    expect(model.articles, hasLength(1));
    provider.fail = false;
    await model.reload();
    expect(model.reminderError, isNull);
    expect(provider.scheduled, isNotEmpty);
  });
  test('周备份按北京时间七个日历日计时，导出后重排且不安排过去时间', () async {
    var now = DateTime.utc(2026, 10, 8, 15);
    final provider = FakeReminders();
    final model = await fixture(provider, clock: () => now);
    await model.savePreferences(studyEnabled: true, backupEnabled: true);
    expect(provider.scheduled.every((r) => r.at.isAfter(now)), isTrue);
    expect(provider.scheduled.last.at, DateTime.utc(2026, 10, 15, 12));
    now = DateTime.utc(2026, 10, 15, 13);
    await model.reload();
    expect(model.backupDue, isTrue);
    expect(provider.scheduled.last.at, DateTime.utc(2026, 10, 16, 12));
    await model.savePreferences(exported: true);
    expect(model.backupDue, isFalse);
    expect(model.preferences.lastExportAt, now);
    expect(provider.scheduled.last.at, DateTime.utc(2026, 10, 22, 12));
    await model.savePreferences(hour: 9, minute: 30);
    expect(provider.scheduled.last.at, DateTime.utc(2026, 10, 22, 1, 30));
  });
  test('提醒设置读写失败独立于学习档案，失败写入不发布新值', () async {
    final settings = FailingPreferences()..failRead = true;
    final provider = FakeReminders();
    final model = await fixture(provider, settings: settings);
    expect(model.preferencesError, isNotNull);
    expect(model.articles, hasLength(1));
    settings.failWrite = true;
    await expectLater(
      model.savePreferences(studyEnabled: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(model.preferences.studyEnabled, isFalse);
    settings.failWrite = false;
    await model.savePreferences(studyEnabled: true);
    expect(model.preferencesError, isNull);
    expect(model.preferences.firstOpenedAt, isNotNull);
    expect(provider.scheduled, isNotEmpty);
  });
  test('提醒配置文件更新可重新打开，损坏文件不会静默重置', () async {
    final dir = await Directory.systemTemp.createTemp('recitation-prefs-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    final store = FilePreferencesStore(file);
    await store.write(
      ReminderPreferences(
        studyEnabled: true,
        firstOpenedAt: DateTime.utc(2026, 10, 8),
      ),
    );
    await store.write((await store.read()).copyWith(hour: 9, minute: 30));
    final reopened = await FilePreferencesStore(file).read();
    expect(reopened.hour, 9);
    expect(reopened.studyEnabled, isTrue);
    await file.writeAsString('{broken');
    await expectLater(store.read(), throwsFormatException);
    expect(await file.readAsString(), '{broken');
    expect(
      () => ReminderPreferences.fromJson({'hour': 24}),
      throwsFormatException,
    );
  });
  test('没有内容不提醒备份', () {
    final now = DateTime.utc(2026, 10, 8, 4);
    expect(
      buildReminders(
        preferences: ReminderPreferences(
          backupEnabled: true,
          firstOpenedAt: now,
        ),
        now: now,
        tasks: [],
        plans: [],
        hasContent: false,
      ),
      isEmpty,
    );
    expect(nextBackupAt(const ReminderPreferences(), now), isNull);
  });

  test('三十天外任务不提前安排提醒，旧延期记录保留今日状态', () async {
    final provider = FakeReminders();
    final model = await fixture(provider);
    final task = model.tasks.single;
    await model.service.postponeTasks([task.id], DateTime(2026, 11, 10));
    await model.reload();
    await model.savePreferences(studyEnabled: true);
    expect(provider.scheduled, isEmpty);
    final event = model.events.last;
    model.events[model.events.length - 1] = LearningEvent(
      id: event.id,
      type: event.type,
      occurredAt: event.occurredAt,
      timeZone: event.timeZone,
      durationSeconds: 0,
      taskId: event.taskId,
      dueDate: event.dueDate,
    );
    expect(model.postponedToday, 1);
    expect(model.canUndoPostponement(model.events.last), isFalse);
  });
  test('iOS 通道传递 UTC 时间并识别系统权限', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IosReminderProvider.channel, (call) async {
          calls.add(call);
          return call.method == 'status'
              ? 'denied'
              : call.method == 'requestPermission'
              ? 'allowed'
              : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(IosReminderProvider.channel, null),
    );
    final provider = IosReminderProvider();
    expect(await provider.permission(), ReminderPermission.denied);
    expect(await provider.requestPermission(), ReminderPermission.allowed);
    final at = DateTime.utc(2026, 10, 8, 12);
    await provider.replace([
      LocalReminder(id: 'recitation.study', at: at, title: '学习', body: '待完成'),
    ]);
    expect(
      (calls.last.arguments as List).single['at'],
      at.millisecondsSinceEpoch,
    );
  });
  testWidgets('用户开启时申请权限，拒绝后显示说明且不开启', (tester) async {
    final provider = FakeReminders()..status = ReminderPermission.denied;
    final model = await fixture(provider);
    await tester.pumpWidget(host(ReminderSettingsPage(model: model)));
    await tester.pumpAndSettle();
    expect(provider.requests, 0);
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(provider.requests, 1);
    expect(model.preferences.studyEnabled, isFalse);
    expect(find.textContaining('系统通知未允许'), findsOneWidget);
    provider.status = ReminderPermission.allowed;
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(model.preferences.studyEnabled, isTrue);
    expect(provider.scheduled, isNotEmpty);
  });

  testWidgets('分享取消或不可用不记录导出时间，成功导出重置七日提醒', (tester) async {
    final provider = FakeReminders();
    final model = await fixture(provider);
    var status = ShareResultStatus.dismissed;
    var exports = 0;
    await tester.pumpWidget(
      host(
        BackupPage(
          model: model,
          exportArchive: (text, origin) async {
            expect(
              BackupService(
                model.store,
                profileId: 'local-profile',
              ).preview(text).canMerge,
              isTrue,
            );
            expect(origin, isNotNull);
            exports++;
            return ShareResult('', status);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final result in [
      ShareResultStatus.dismissed,
      ShareResultStatus.unavailable,
      ShareResultStatus.success,
    ]) {
      status = result;
      await tester.ensureVisible(find.text('导出完整档案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出完整档案'));
      await tester.pumpAndSettle();
      expect(
        model.preferences.lastExportAt,
        result == ShareResultStatus.success ? model.clock().toUtc() : isNull,
      );
    }
    expect(exports, 3);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.textContaining('上次导出'), findsOneWidget);
  });
}
