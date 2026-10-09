import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:recitation_core/recitation_core.dart';

class ReminderPreferences {
  const ReminderPreferences({
    this.studyEnabled = false,
    this.backupEnabled = false,
    this.hour = 20,
    this.minute = 0,
    this.firstOpenedAt,
    this.lastExportAt,
    this.weeklyGoalDays = 3,
  });
  final bool studyEnabled;
  final bool backupEnabled;
  final int hour;
  final int minute;
  final DateTime? firstOpenedAt;
  final DateTime? lastExportAt;
  final int weeklyGoalDays;
  ReminderPreferences copyWith({
    bool? studyEnabled,
    bool? backupEnabled,
    int? hour,
    int? minute,
    DateTime? firstOpenedAt,
    DateTime? lastExportAt,
    int? weeklyGoalDays,
  }) => ReminderPreferences(
    studyEnabled: studyEnabled ?? this.studyEnabled,
    backupEnabled: backupEnabled ?? this.backupEnabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    firstOpenedAt: firstOpenedAt ?? this.firstOpenedAt,
    lastExportAt: lastExportAt ?? this.lastExportAt,
    weeklyGoalDays: weeklyGoalDays ?? this.weeklyGoalDays,
  );
  Map<String, Object?> toJson() => {
    'studyEnabled': studyEnabled,
    'backupEnabled': backupEnabled,
    'hour': hour,
    'minute': minute,
    'firstOpenedAt': firstOpenedAt?.toUtc().toIso8601String(),
    'lastExportAt': lastExportAt?.toUtc().toIso8601String(),
    'weeklyGoalDays': weeklyGoalDays,
  };
  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    final hour = json['hour'] as int? ?? 20;
    final minute = json['minute'] as int? ?? 0;
    final goal = json['weeklyGoalDays'] as int? ?? 3;
    if (goal < 1 || goal > 7) throw const FormatException('每周目标应为1至7天');
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('提醒时间无效');
    }
    return ReminderPreferences(
      studyEnabled: json['studyEnabled'] as bool? ?? false,
      backupEnabled: json['backupEnabled'] as bool? ?? false,
      hour: hour,
      minute: minute,
      weeklyGoalDays: goal,
      firstOpenedAt: json['firstOpenedAt'] == null
          ? null
          : DateTime.parse(json['firstOpenedAt']),
      lastExportAt: json['lastExportAt'] == null
          ? null
          : DateTime.parse(json['lastExportAt']),
    );
  }
}

abstract interface class PreferencesStore {
  Future<ReminderPreferences> read();
  Future<void> write(ReminderPreferences value);
}

class MemoryPreferencesStore implements PreferencesStore {
  ReminderPreferences value = const ReminderPreferences();
  @override
  Future<ReminderPreferences> read() async => value;
  @override
  Future<void> write(ReminderPreferences next) async {
    value = next;
  }
}

class FilePreferencesStore implements PreferencesStore {
  FilePreferencesStore(this.file);
  final File file;
  @override
  Future<ReminderPreferences> read() async => await file.exists()
      ? ReminderPreferences.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        )
      : const ReminderPreferences();
  @override
  Future<void> write(ReminderPreferences value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}

enum ReminderPermission { unavailable, notRequested, denied, allowed }

class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });
  final String id;
  final DateTime at;
  final String title;
  final String body;
  Map<String, Object> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
  };
}

abstract interface class ReminderProvider {
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<void> replace(List<LocalReminder> reminders);
}

class UnavailableReminderProvider implements ReminderProvider {
  @override
  Future<ReminderPermission> permission() async =>
      ReminderPermission.unavailable;
  @override
  Future<ReminderPermission> requestPermission() => permission();
  @override
  Future<void> replace(List<LocalReminder> reminders) async {}
}

class IosReminderProvider implements ReminderProvider {
  static const channel = MethodChannel('recitation/reminders');
  ReminderPermission decode(String? value) => switch (value) {
    'allowed' => ReminderPermission.allowed,
    'denied' => ReminderPermission.denied,
    _ => ReminderPermission.notRequested,
  };
  @override
  Future<ReminderPermission> permission() async =>
      decode(await channel.invokeMethod<String>('status'));
  @override
  Future<ReminderPermission> requestPermission() async =>
      decode(await channel.invokeMethod<String>('requestPermission'));
  @override
  Future<void> replace(List<LocalReminder> reminders) => channel
      .invokeMethod<void>('replace', reminders.map((r) => r.toJson()).toList());
}

DateTime? nextBackupAt(ReminderPreferences preferences, DateTime now) {
  final base = preferences.lastExportAt ?? preferences.firstOpenedAt;
  if (base == null) return null;
  final local = localTime(base, 'Asia/Shanghai');
  final next = localTime(
    DateTime.utc(
      local.year,
      local.month,
      local.day + 7,
      preferences.hour - 8,
      preferences.minute,
    ),
    'Asia/Shanghai',
  );
  // Overdue reminders are sent at the next selected time, never immediately.
  if (next.isAfter(now)) return next.toUtc();
  final current = localTime(now, 'Asia/Shanghai');
  var date = DateTime.utc(
    current.year,
    current.month,
    current.day,
    preferences.hour - 8,
    preferences.minute,
  );
  if (!date.isAfter(now)) {
    date = DateTime.utc(
      current.year,
      current.month,
      current.day + 1,
      preferences.hour - 8,
      preferences.minute,
    );
  }
  return date;
}

List<LocalReminder> buildReminders({
  required ReminderPreferences preferences,
  required DateTime now,
  required List<Task> tasks,
  required List<Plan> plans,
  required bool hasContent,
}) {
  final reminders = <LocalReminder>[];
  final local = localTime(now, 'Asia/Shanghai');
  final active = plans
      .where((p) => !p.paused && !p.deleted)
      .map((p) => p.id)
      .toSet();
  final pending = tasks
      .where((t) => t.status == TaskStatus.pending && active.contains(t.planId))
      .toList();
  if (preferences.studyEnabled) {
    for (var offset = 0; offset < 30; offset++) {
      final day = DateTime(local.year, local.month, local.day + offset);
      final at = DateTime.utc(
        day.year,
        day.month,
        day.day,
        preferences.hour - 8,
        preferences.minute,
      );
      if (!at.isAfter(now)) continue;
      if (pending.any((t) => !t.dueDate.isAfter(day))) {
        reminders.add(
          LocalReminder(
            id: 'recitation.study.${day.year}-${day.month}-${day.day}',
            at: at,
            title: '背诵计划',
            body: '今天有待完成的学习任务，打开查看最新安排。',
          ),
        );
      }
    }
  }
  final backup = nextBackupAt(preferences, now);
  if (preferences.backupEnabled && hasContent && backup != null) {
    reminders.add(
      LocalReminder(
        id: 'recitation.backup',
        at: backup,
        title: '保存学习档案',
        body: '定期导出文章、计划和成绩，保存到文件或云盘。',
      ),
    );
  }
  return reminders;
}
