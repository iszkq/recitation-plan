import 'package:flutter/cupertino.dart';

import 'app_model.dart';
import 'design.dart';
import 'reminders.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key, required this.model});
  final AppModel model;
  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  bool busy = false;
  AppModel get model => widget.model;
  Future<void> change({
    bool? study,
    bool? backup,
    int? hour,
    int? minute,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if ((study == true || backup == true) &&
          model.reminderPermission != ReminderPermission.allowed) {
        model.reminderPermission = await model.reminderProvider
            .requestPermission();
        if (model.reminderPermission != ReminderPermission.allowed) {
          await model.syncReminders();
          if (mounted) setState(() {});
          return;
        }
      }
      await model.savePreferences(
        studyEnabled: study,
        backupEnabled: backup,
        hour: hour,
        minute: minute,
      );
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseTime() async {
    var selected = DateTime(
      2026,
      1,
      1,
      model.preferences.hour,
      model.preferences.minute,
    );
    final value = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => PickerSheet(
        onConfirm: () => Navigator.pop(c, selected),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          initialDateTime: selected,
          onDateTimeChanged: (date) => selected = date,
        ),
      ),
    );
    if (value != null && mounted) {
      await change(hour: value.hour, minute: value.minute);
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final p = model.preferences;
      final unavailable =
          model.reminderPermission == ReminderPermission.unavailable;
      final description = switch (model.reminderPermission) {
        ReminderPermission.allowed => '系统通知已允许',
        ReminderPermission.denied => '系统通知未允许，请到 iPhone 设置中允许通知，然后返回刷新。',
        ReminderPermission.notRequested => '开启提醒时会申请通知权限',
        ReminderPermission.unavailable => '本设备暂不支持系统提醒，iPhone 上可开启。',
      };
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('提醒设置')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              const Text('按自己的时间学习', style: Design.heading),
              Text(description, style: Design.caption),
              const SizedBox(height: Design.gap),
              CardSection(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('学习提醒')),
                        Semantics(
                          label: '学习提醒',
                          child: CupertinoSwitch(
                            value: p.studyEnabled,
                            onChanged: busy || unavailable
                                ? null
                                : (value) => change(study: value),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '有待完成任务时提醒。调整计划或完成任务后会更新。',
                      style: Design.caption,
                    ),
                    const SizedBox(height: Design.gap),
                    Row(
                      children: [
                        const Expanded(child: Text('每周备份提醒')),
                        Semantics(
                          label: '每周备份提醒',
                          child: CupertinoSwitch(
                            value: p.backupEnabled,
                            onChanged: busy || unavailable
                                ? null
                                : (value) => change(backup: value),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '距上次成功导出七个日历日后提醒；未导出过时从首次使用开始计算。',
                      style: Design.caption,
                    ),
                  ],
                ),
              ),
              DetailRow(
                inset: false,
                title: '提醒时间',
                subtitle:
                    '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')} · 北京时间',
                icon: CupertinoIcons.clock,
                onTap: busy ? null : chooseTime,
              ),
              if (model.preferencesError != null)
                Text(model.preferencesError!, style: Design.caption),
              if (model.reminderError != null)
                Text(model.reminderError!, style: Design.caption),
              CupertinoButton(
                onPressed: busy ? null : refresh,
                child: const Text('刷新提醒状态'),
              ),
              if (busy) const CupertinoActivityIndicator(),
              const Text(
                '关闭提醒不会改变计划或学习记录。学习提醒提前安排未来三十天，打开应用后会续排。',
                style: Design.caption,
              ),
            ],
          ),
        ),
      );
    },
  );
}
