import 'package:flutter/cupertino.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app.dart' show TaskReadingPage;
import 'app_model.dart';
import 'design.dart';

class ScheduleCalendarPage extends StatefulWidget {
  const ScheduleCalendarPage({super.key, required this.model, this.planId});
  final AppModel model;
  final String? planId;
  @override
  State<ScheduleCalendarPage> createState() => _ScheduleCalendarPageState();
}

class _ScheduleCalendarPageState extends State<ScheduleCalendarPage> {
  late DateTime month = DateTime(
    widget.model.today.year,
    widget.model.today.month,
  );
  late DateTime selected = widget.model.today;
  AppModel get model => widget.model;
  List<Task> get tasks => model.tasks
      .where(
        (t) =>
            t.status != TaskStatus.skipped &&
            (widget.planId == null || t.planId == widget.planId) &&
            model.plans.any((p) => p.id == t.planId),
      )
      .toList();
  void move(int n) => setState(() {
    month = DateTime(month.year, month.month + n);
    selected = month;
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final days = DateTime(month.year, month.month + 1, 0).day;
      final offset = month.weekday - 1;
      final rows = (days + offset + 6) ~/ 7;
      final own = tasks;
      final chosen = own.where((t) => t.dueDate == selected).toList()
        ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('计划月历')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: Design.inset),
            children:
                [
                      const Text('每一天的安排', style: Design.heading),
                      const Text(
                        '数字表示当天任务总数；下方分别显示新背、复习和已完成。暂停计划仍可查看。',
                        style: Design.caption,
                      ),
                      Row(
                        children: [
                          CupertinoButton(
                            onPressed: () => move(-1),
                            child: Semantics(
                              label: '上个月',
                              child: const Icon(CupertinoIcons.chevron_left),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${month.year}年${month.month}月',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          CupertinoButton(
                            onPressed: () => move(1),
                            child: Semantics(
                              label: '下个月',
                              child: const Icon(CupertinoIcons.chevron_right),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        key: const ValueKey('month-grid'),
                        children: [
                          Row(
                            children: [
                              for (final day in [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ])
                                Expanded(
                                  child: Text(
                                    day,
                                    style: Design.caption,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                          for (var row = 0; row < rows; row++)
                            Row(
                              children: [
                                for (var col = 0; col < 7; col++)
                                  Expanded(
                                    child: _dayCell(
                                      row * 7 + col - offset + 1,
                                      days,
                                      own,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: Design.gap),
                      CupertinoButton(
                        onPressed: () => setState(() {
                          selected = model.today;
                          month = DateTime(selected.year, selected.month);
                        }),
                        child: const Text('回到今天'),
                      ),
                      Text(dateLabel(selected), style: Design.heading),
                      Text(
                        '新背 ${chosen.where((t) => t.kind == TaskKind.newLearning).length} · 复习 ${chosen.where((t) => t.kind == TaskKind.review).length} · 已完成 ${chosen.where((t) => t.status == TaskStatus.completed).length}',
                        style: Design.caption,
                      ),
                      if (chosen.isEmpty)
                        const EmptyContent('这天没有任务', '切换日期查看其他安排。'),
                      for (final task in chosen)
                        DetailRow(
                          inset: false,
                          title: model.taskTitle(task),
                          subtitleMaxLines: null,
                          subtitle:
                              '${task.kind == TaskKind.newLearning ? '新背' : '复习'} · ${model.taskScheduleLabel(task)}${model.plans.any((p) => p.id == task.planId && p.paused) ? ' · 已暂停' : ''}',
                          done: task.status == TaskStatus.completed,
                          onTap:
                              task.status == TaskStatus.pending &&
                                  (!task.dueDate.isAfter(model.today) ||
                                      model.canStartEarly(task)) &&
                                  model.plans.any(
                                    (p) => p.id == task.planId && !p.paused,
                                  )
                              ? () => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => TaskReadingPage(
                                      model: model,
                                      task: task,
                                      allowEarly: model.canStartEarly(task),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                    ]
                    .map(
                      (child) => child.key == const ValueKey('month-grid')
                          ? child
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Design.inset,
                              ),
                              child: child,
                            ),
                    )
                    .toList(),
          ),
        ),
      );
    },
  );
  Widget _dayCell(int day, int days, List<Task> tasks) {
    if (day < 1 || day > days) {
      return const SizedBox(height: Design.calendarCellHeight);
    }
    final date = DateTime(month.year, month.month, day);
    final own = tasks.where((t) => t.dueDate == date).toList();
    final done = own.where((t) => t.status == TaskStatus.completed).length;
    return Semantics(
      label: '${dateLabel(date)}，${own.length}个任务，已完成$done个',
      selected: selected == date,
      button: true,
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            Design.touchTarget,
            Design.calendarCellHeight,
          ),
          onPressed: () => setState(() => selected = date),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: Design.calendarCellHeight,
            ),
            decoration: BoxDecoration(
              color: selected == date ? Design.accentSoft : Design.panel,
              borderRadius: BorderRadius.circular(Design.controlRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    color: selected == date ? Design.accent : Design.ink,
                  ),
                ),
                Text(
                  own.isEmpty ? '—' : '${own.length}',
                  style: Design.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduleReplanPage extends StatefulWidget {
  const ScheduleReplanPage({super.key, required this.model, this.planId});
  final AppModel model;
  final String? planId;
  @override
  State<ScheduleReplanPage> createState() => _ScheduleReplanPageState();
}

class _ScheduleReplanPageState extends State<ScheduleReplanPage> {
  late DateTime start = widget.model.today;
  late int quota = widget.planId == null
      ? 3
      : widget.model.plans
            .firstWhere((p) => p.id == widget.planId)
            .dailyNewQuota;
  late Set<int> weekdays = widget.planId == null
      ? {1, 2, 3, 4, 5, 6, 7}
      : Set.of(
          widget.model.plans.firstWhere((p) => p.id == widget.planId).weekdays,
        );
  ScheduleChangePreview? preview;
  String? error;
  bool busy = false;
  AppModel get model => widget.model;
  bool get backlog => widget.planId == null;
  void changed(VoidCallback action) => setState(() {
    action();
    preview = null;
    error = null;
  });
  Future<void> chooseDate() async {
    var draft = start.isBefore(model.today) ? model.today : start;
    final value = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => PickerSheet(
        onConfirm: () => Navigator.pop(c, draft),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          minimumDate: model.today,
          initialDateTime: draft,
          onDateTimeChanged: (date) => draft = scheduleDay(date),
        ),
      ),
    );
    if (value != null && mounted) changed(() => start = value);
  }

  Future<void> calculate() async {
    if (busy) return;
    setState(() {
      busy = true;
      preview = null;
      error = null;
    });
    try {
      final value = backlog
          ? await model.service.previewReviewBacklog(
              start: start,
              quota: quota,
              weekdays: weekdays,
            )
          : await model.service.previewRemainingSchedule(
              planId: widget.planId!,
              start: start,
              quota: quota,
              weekdays: weekdays,
            );
      if (mounted) setState(() => preview = value);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : e is ArgumentError
              ? '${e.message}'
              : '暂时无法预览，请刷新后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final draft = preview;
    if (busy || draft == null || !draft.fits) return;
    if (!await confirm(
          context,
          '保存新的安排？',
          '调整 ${draft.changes.length} 个任务的日期。已有成绩和原定日期会保留；本次批量调整不提供逐项撤销，保存前可到备份页保存一份快照或导出档案。',
          action: '保存安排',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await model.service.applySchedulePreview(draft);
      await model.reload();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          preview = null;
          busy = false;
        });
        await showError(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final draft = preview;
      final projected = {
        for (final c in draft?.changes ?? <TaskDateChange>[])
          c.before.id: c.date,
      };
      final days = <DateTime>{
        if (draft != null && draft.fits)
          for (final values in draft.tasks.values)
            for (final task in values)
              if (task.status == TaskStatus.pending &&
                  ((!backlog && task.kind == TaskKind.newLearning) ||
                      (backlog && projected.containsKey(task.id))))
                projected[task.id] ?? task.dueDate,
      }.toList()..sort();
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(backlog ? '整理积压复习' : '重新安排新背'),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              Text(backlog ? '把积压分散到几天' : '按新的节奏继续', style: Design.heading),
              Text(
                backlog
                    ? '当前积压 ${model.overdueReviews.length} 个复习任务。保留每次复习，同一段每天最多安排一次；已有复习占用当天配额。'
                    : '按原文顺序安排未完成新背，已完成任务和复习保持原日期，原截止日不变。',
                style: Design.caption,
              ),
              DetailRow(
                inset: false,
                title: '开始日期',
                subtitle: dateLabel(start),
                icon: CupertinoIcons.calendar,
                onTap: busy ? null : chooseDate,
              ),
              Text(backlog ? '每天复习最多 $quota 项' : '每天新背 $quota 节'),
              Row(
                children: [
                  CupertinoButton(
                    onPressed: busy || quota <= 1
                        ? null
                        : () => changed(() => quota--),
                    child: const Text('减少'),
                  ),
                  Expanded(child: Text('$quota', textAlign: TextAlign.center)),
                  CupertinoButton(
                    onPressed: busy || quota >= 50
                        ? null
                        : () => changed(() => quota++),
                    child: const Text('增加'),
                  ),
                ],
              ),
              const Text('学习日', style: Design.caption),
              Wrap(
                spacing: Design.smallGap,
                runSpacing: Design.smallGap,
                children: [
                  for (var day = 1; day <= 7; day++)
                    Semantics(
                      selected: weekdays.contains(day),
                      child: CupertinoButton(
                        color: weekdays.contains(day)
                            ? Design.accentSoft
                            : Design.grouped,
                        onPressed: busy
                            ? null
                            : () => changed(() {
                                if (!weekdays.add(day)) weekdays.remove(day);
                              }),
                        child: Text(
                          '星期${['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                        ),
                      ),
                    ),
                ],
              ),
              PrimaryAction('预览安排', onPressed: calculate, busy: busy),
              if (error != null) Text(error!, style: Design.caption),
              if (draft != null) ...[
                CardSection(
                  child: Text(
                    draft.fits
                        ? '共有 ${draft.affectedCount} 个待完成任务，${draft.changes.length} 个需要改期。预计${dateLabel(draft.finishDate!)}完成。'
                        : '原截止日前只有 ${draft.availableDays} 个学习日，需要 ${draft.requiredDays} 天。请增加配额或学习日。',
                    style: Design.caption,
                  ),
                ),
                if (draft.fits) ...[
                  const SizedBox(height: Design.gap),
                  const Text('目标日工作量', style: Design.heading),
                  for (final day in days)
                    Text(
                      '${dateLabel(day)}：新背 ${model.tasks.where((t) => t.status == TaskStatus.pending && t.kind == TaskKind.newLearning && model.plans.any((p) => p.id == t.planId && !p.paused) && (projected[t.id] ?? t.dueDate) == day).length} · 复习 ${model.tasks.where((t) => t.status == TaskStatus.pending && t.kind == TaskKind.review && model.plans.any((p) => p.id == t.planId && !p.paused) && (projected[t.id] ?? t.dueDate) == day).length}',
                      style: Design.caption,
                    ),
                  const SizedBox(height: Design.gap),
                  for (final change in draft.changes)
                    DetailRow(
                      inset: false,
                      subtitleMaxLines: null,
                      title: model.taskTitle(change.before),
                      subtitle:
                          '${dateLabel(change.before.dueDate)} → ${dateLabel(change.date)}',
                    ),
                  PrimaryAction('保存安排', onPressed: save, busy: busy),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
