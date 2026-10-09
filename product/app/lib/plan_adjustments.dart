import 'package:flutter/cupertino.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app_model.dart';
import 'design.dart';

Future<bool?> openPostponement(
  BuildContext context,
  AppModel model,
  List<String> ids,
) async {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    CupertinoPageRoute<bool>(
      builder: (_) => PostponePage(model: model, taskIds: ids),
    ),
  );
}

class PostponePage extends StatefulWidget {
  const PostponePage({super.key, required this.model, required this.taskIds});
  final AppModel model;
  final List<String> taskIds;
  @override
  State<PostponePage> createState() => _PostponePageState();
}

class _PostponePageState extends State<PostponePage> {
  late DateTime selected;
  bool busy = false;
  AppModel get model => widget.model;
  List<Task> get selectedTasks =>
      model.tasks.where((t) => widget.taskIds.contains(t.id)).toList();
  DateTime get minimum {
    var latest = model.today;
    for (final task in selectedTasks) {
      if (task.dueDate.isAfter(latest)) latest = task.dueDate;
    }
    return DateTime(latest.year, latest.month, latest.day + 1);
  }

  @override
  void initState() {
    super.initState();
    selected = minimum;
  }

  Future<void> chooseDate() async {
    var draft = selected.isBefore(minimum) ? minimum : selected;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => PickerSheet(
        onConfirm: () => Navigator.pop(c, draft),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          minimumDate: minimum,
          initialDateTime: draft,
          onDateTimeChanged: (d) => draft = DateTime(d.year, d.month, d.day),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => selected = picked);
  }

  Future<void> save() async {
    if (busy) return;
    final tasks = selectedTasks;
    final before = model.pendingOn(selected, excluding: widget.taskIds.toSet());
    if (!await confirm(
          context,
          '确认延期？',
          '${dateLabel(selected)}原有 $before 个未完成任务，移入 ${tasks.length} 个后共 ${before + tasks.length} 个。',
          action: '保存延期',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await model.service.postponeTasks(widget.taskIds, selected);
      await model.reload();
      if (mounted) Navigator.pop(context, true);
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
      final tasks = selectedTasks;
      final valid =
          tasks.length == widget.taskIds.toSet().length &&
          tasks.isNotEmpty &&
          tasks.every(
            (t) =>
                t.status == TaskStatus.pending &&
                model.plans.any((p) => p.id == t.planId && !p.paused),
          ) &&
          !selected.isBefore(minimum);
      final before = model.pendingOn(
        selected,
        excluding: widget.taskIds.toSet(),
      );
      final crossesTarget = tasks.any(
        (t) => model.plans.any(
          (p) => p.id == t.planId && selected.isAfter(p.endDate),
        ),
      );
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('调整任务日期')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              Text('延后 ${tasks.length} 个任务', style: Design.heading),
              const SizedBox(height: Design.gap),
              DetailRow(
                inset: false,
                title: '延期日期',
                subtitle: dateLabel(selected),
                icon: CupertinoIcons.calendar,
                onTap: busy ? null : chooseDate,
              ),
              CardSection(
                child: Text(
                  '这天原有 $before 个未完成任务，移入 ${tasks.length} 个后共 ${before + tasks.length} 个。',
                  style: Design.caption,
                ),
              ),
              if (crossesTarget)
                const Padding(
                  padding: EdgeInsets.only(top: Design.gap),
                  child: Text('已超出原计划截止日，原定目标日期会保留。', style: Design.caption),
                ),
              const SizedBox(height: Design.gap),
              for (final task in tasks)
                Text(
                  '${model.taskTitle(task)} · 当前${dateLabel(task.dueDate)}',
                  style: Design.caption,
                ),
              if (!valid)
                const Text('任务或日期已变化，请返回刷新后重试。', style: Design.caption),
              PrimaryAction('保存延期', onPressed: valid ? save : null, busy: busy),
              const Text(
                '已有成绩保持不变。保存后可在“延期记录”中撤销未完成任务的最近一次延期。',
                style: Design.caption,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class PostponementHistoryPage extends StatefulWidget {
  const PostponementHistoryPage({super.key, required this.model});
  final AppModel model;
  @override
  State<PostponementHistoryPage> createState() =>
      _PostponementHistoryPageState();
}

class _PostponementHistoryPageState extends State<PostponementHistoryPage> {
  bool busy = false;
  Future<void> undo(LearningEvent event) async {
    if (busy || event.previousDueDate == null) return;
    final date = event.previousDueDate!;
    final count = widget.model.pendingOn(date, excluding: {event.taskId!}) + 1;
    if (!await confirm(
          context,
          '撤销这次延期？',
          '任务恢复到${dateLabel(date)}，这天共 $count 个未完成任务。${!date.isAfter(widget.model.today) ? '恢复后会回到今日队列。' : ''}',
          action: '撤销延期',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.model.service.undoPostponement(event.id);
      await widget.model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final history =
          model.events
              .where(
                (e) =>
                    e.type == LearningEventType.taskRescheduled &&
                    e.undoOf == null &&
                    e.adjustment == null,
              )
              .toList()
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('延期记录')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              const Text('保留每一次调整', style: Design.heading),
              const Text('可撤销未完成任务的最近一次延期；完成后保留记录。', style: Design.caption),
              if (history.isEmpty)
                const EmptyContent('还没有延期记录', '调整日期后会显示在这里。'),
              for (final event in history) ...[
                DetailRow(
                  inset: false,
                  subtitleMaxLines: null,
                  title: model.tasks.where((t) => t.id == event.taskId).isEmpty
                      ? '历史任务'
                      : model.taskTitle(
                          model.tasks.firstWhere((t) => t.id == event.taskId),
                        ),
                  subtitle:
                      '${event.previousDueDate == null ? '原排期' : dateLabel(event.previousDueDate!)} → ${dateLabel(event.dueDate!)}\n${model.events.any((e) => e.undoOf == event.id)
                          ? '已撤销'
                          : model.canUndoPostponement(event)
                          ? '可撤销'
                          : event.previousDueDate == null
                          ? '旧版延期记录'
                          : '已完成、已暂停或已再次调整'}',
                  onTap: !busy && model.canUndoPostponement(event)
                      ? () => undo(event)
                      : null,
                ),
              ],
              if (busy) const CupertinoActivityIndicator(),
            ],
          ),
        ),
      );
    },
  );
}

class CompletionFeedback extends StatelessWidget {
  const CompletionFeedback({
    super.key,
    required this.model,
    required this.task,
    required this.attempt,
  });
  final AppModel model;
  final Task task;
  final Attempt attempt;
  @override
  Widget build(BuildContext context) {
    if (attempt.status != AttemptStatus.passed ||
        attempt.source != AttemptSource.automatic) {
      return const SizedBox.shrink();
    }
    final completions = model.events.where(
      (e) => e.type == LearningEventType.taskCompleted && e.taskId == task.id,
    );
    if (completions.isEmpty) return const SizedBox.shrink();
    final at = eventLocalTime(completions.first);
    final day = DateTime(at.year, at.month, at.day);
    final current = model.tasks.firstWhere(
      (t) => t.id == task.id,
      orElse: () => task,
    );
    final reviews =
        model.tasks
            .where(
              (t) =>
                  t.planId == task.planId &&
                  t.segmentId == task.segmentId &&
                  t.kind == TaskKind.review &&
                  t.status == TaskStatus.pending &&
                  !t.dueDate.isBefore(model.today),
            )
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return Padding(
      padding: const EdgeInsets.only(top: Design.gap),
      child: CardSection(
        child: Text(
          '${day.isBefore(current.dueDate) ? '已提前完成${current.dueDate.month}月${current.dueDate.day}日的新背，到原定日期无需重做。' : '本次任务已完成。'}${task.kind == TaskKind.newLearning && reviews.isNotEmpty ? '\n下次复习：${dateLabel(reviews.first.dueDate)}。' : ''}',
          style: Design.caption,
        ),
      ),
    );
  }
}
