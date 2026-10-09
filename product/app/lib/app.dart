import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:io';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app_model.dart';
import 'design.dart';
import 'speech.dart';
import 'plan_adjustments.dart';
import 'reminder_settings.dart';
import 'schedule_pages.dart';
import 'snapshot_pages.dart';

class RecitationApp extends StatelessWidget {
  const RecitationApp({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: Design.theme,
      title: '背诵计划',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalCupertinoLocalizations.delegates,
      home: RootShell(model: model),
    ),
  );
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.model});
  final AppModel model;
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  Timer? midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMidnight();
  }

  void scheduleMidnight() {
    midnight?.cancel();
    final now = localTime(DateTime.now().toUtc(), 'Asia/Shanghai');
    final remaining =
        const Duration(days: 1) -
        Duration(hours: now.hour, minutes: now.minute, seconds: now.second);
    midnight = Timer(remaining, () {
      refresh();
      scheduleMidnight();
    });
  }

  Future<void> refresh() async {
    try {
      await widget.model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      scheduleMidnight();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoTabScaffold(
    tabBar: CupertinoTabBar(
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.calendar),
          label: '今日',
        ),
        BottomNavigationBarItem(icon: Icon(CupertinoIcons.book), label: '文库'),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.calendar_today),
          label: '计划',
        ),
        BottomNavigationBarItem(icon: Icon(CupertinoIcons.person), label: '我的'),
      ],
    ),
    tabBuilder: (context, index) => CupertinoTabView(
      builder: (_) {
        switch (index) {
          case 1:
            return LibraryPage(model: widget.model);
          case 2:
            return PlansPage(model: widget.model);
          case 3:
            return ProfilePage(model: widget.model);
          default:
            return TodayPage(model: widget.model);
        }
      },
    ),
  );
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.model});
  final AppModel model;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool postponing = false;
  AppModel get model => widget.model;

  Future<void> postpone() async {
    final ids = model.dueTasks.map((t) => t.id).toList();
    if (postponing || ids.isEmpty) return;
    final accepted = await confirm(
      context,
      '将剩余任务延至明天？',
      '明天原有 ${model.pendingOn(DateTime(model.today.year, model.today.month, model.today.day + 1))} 个未完成任务，移入 ${ids.length} 个后共 ${model.pendingOn(DateTime(model.today.year, model.today.month, model.today.day + 1)) + ids.length} 个。',
      action: '延至明天',
    );
    if (!accepted || !mounted) return;
    setState(() => postponing = true);
    try {
      await model.service.postponeTasksUntilTomorrow(ids);
      await model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => postponing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => buildToday(context),
  );

  Widget buildToday(BuildContext context) {
    final tasks = model.dueTasks;
    final todayTasks = model.todayTasks;
    final postponed = model.postponedToday;
    final completed = todayTasks
        .where((task) => task.status == TaskStatus.completed)
        .length;
    final total = todayTasks.length;
    final completion = total == 0 ? 0.0 : completed / total;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('今日')),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: model.reload),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Design.inset,
                22,
                Design.inset,
                28,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(dateLabel(model.today), style: Design.caption),
                  if (model.overdueReviews.isNotEmpty)
                    DetailRow(
                      inset: false,
                      title: '整理积压复习',
                      subtitle: '${model.overdueReviews.length} 个逾期复习，可分散到不同日期',
                      icon: CupertinoIcons.clock,
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) => ScheduleReplanPage(model: model),
                            ),
                          ),
                    ),
                  DetailRow(
                    inset: false,
                    title: '计划月历',
                    subtitle: '查看每天的新背、复习和完成情况',
                    icon: CupertinoIcons.calendar,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) => ScheduleCalendarPage(model: model),
                          ),
                        ),
                  ),
                  if (model.snapshotError != null)
                    Text(model.snapshotError!, style: Design.caption),
                  const SizedBox(height: 6),
                  Text(
                    tasks.isEmpty
                        ? (postponed > 0
                              ? '剩余任务已延期'
                              : total == 0
                              ? '今天安排什么？'
                              : '今天的任务完成了')
                        : '今天还有 ${tasks.length} 个任务',
                    style: Design.display,
                  ),
                  const SizedBox(height: 20),
                  CardSection(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const IconBadge(CupertinoIcons.sun_max),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                total == 0
                                    ? (postponed > 0
                                          ? '$postponed 个任务已延期'
                                          : '安排一小节，今天就开始')
                                    : '保持学习节奏，完成今天的安排',
                                style: Design.caption,
                              ),
                            ),
                            Text(
                              '$completed/$total',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (total > 0) ...[
                          const SizedBox(height: 16),
                          ProgressBar(
                            value: completion,
                            color: completion == 1
                                ? Design.success
                                : Design.accent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            completion == 1
                                ? (postponed > 0
                                      ? '已完成 $completed 个，延期 $postponed 个'
                                      : '今天的任务全部完成')
                                : '完成 ${total - completed} 个任务后结束今天的学习',
                            style: Design.caption,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (tasks.isNotEmpty) ...[
                    CupertinoButton(
                      onPressed: postponing ? null : postpone,
                      child: postponing
                          ? const CupertinoActivityIndicator()
                          : const Text('将剩余任务延至明天'),
                    ),
                    CupertinoButton(
                      onPressed: postponing
                          ? null
                          : () => openPostponement(
                              context,
                              model,
                              tasks.map((t) => t.id).toList(),
                            ),
                      child: const Text('选择其他延期日期'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 20, bottom: 10),
                      child: Text(
                        '今日队列',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final task in tasks)
                      DetailRow(
                        inset: false,
                        title: model.taskTitle(task),
                        subtitle:
                            '${task.kind == TaskKind.newLearning ? '新背' : '复习'} · ${model.taskScheduleLabel(task)} · ${model.segments[task.segmentId]?.text ?? ''}',
                        icon: task.kind == TaskKind.review
                            ? CupertinoIcons.refresh
                            : CupertinoIcons.book,
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    TaskReadingPage(model: model, task: task),
                              ),
                            ),
                      ),
                  ],
                  if (tasks.isEmpty && model.articles.isEmpty)
                    EmptyContent(
                      '先导入一篇文章',
                      '把课文、古文或演讲稿分成每天的一小节。',
                      action: PrimaryAction(
                        '导入文章',
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              CupertinoPageRoute(
                                builder: (_) => ImportPage(model: model),
                              ),
                            ),
                      ),
                    ),
                  if (tasks.isEmpty && model.articles.isNotEmpty)
                    EmptyContent(
                      model.plans.isEmpty ? '为文章安排学习计划' : '今天没有待完成任务',
                      model.plans.isEmpty
                          ? '选择文章和日期，把背诵安排到每天。'
                          : '到期的新背和复习任务会显示在这里。',
                      action: model.plans.isEmpty
                          ? PrimaryAction(
                              '制定计划',
                              onPressed: () =>
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push(
                                    CupertinoPageRoute(
                                      builder: (_) => PlanCreatePage(
                                        model: model,
                                        article: model.articles.first,
                                      ),
                                    ),
                                  ),
                            )
                          : null,
                    ),
                  if (tasks.isEmpty && model.articles.isNotEmpty && total > 0)
                    CardSection(
                      child: Row(
                        children: [
                          const IconBadge(
                            CupertinoIcons.checkmark_seal,
                            color: Design.success,
                            background: Design.successSoft,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('今天的队列已经清空。', style: Design.caption),
                          ),
                        ],
                      ),
                    ),
                  if (model.plans.isNotEmpty)
                    DetailRow(
                      inset: false,
                      title: '提前学习',
                      subtitle: tasks.isEmpty ? '明天与后天的安排' : '完成今日队列后可提前新背',
                      icon: CupertinoIcons.calendar,
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) => UpcomingTasksPage(model: model),
                            ),
                          ),
                    ),
                  if (model.events.any(
                    (e) => e.type == LearningEventType.taskRescheduled,
                  ))
                    DetailRow(
                      inset: false,
                      title: '延期记录',
                      subtitle: '查看调整或撤销最近一次延期',
                      icon: CupertinoIcons.clock,
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  PostponementHistoryPage(model: model),
                            ),
                          ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpcomingTasksPage extends StatefulWidget {
  const UpcomingTasksPage({super.key, required this.model});
  final AppModel model;
  @override
  State<UpcomingTasksPage> createState() => _UpcomingTasksPageState();
}

class _UpcomingTasksPageState extends State<UpcomingTasksPage> {
  int days = 1;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final tasks = model.upcomingTasks(days);
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('提前学习')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              CupertinoSlidingSegmentedControl<int>(
                groupValue: days,
                children: const {1: Text('明天'), 2: Text('后天')},
                onValueChanged: (value) {
                  if (value != null) setState(() => days = value);
                },
              ),
              const SizedBox(height: Design.gap),
              Text(
                dateLabel(
                  DateTime(
                    model.today.year,
                    model.today.month,
                    model.today.day + days,
                  ),
                ),
                style: Design.heading,
              ),
              if (model.dueTasks.isNotEmpty)
                const Text('今日队列尚未完成', style: Design.caption),
              if (tasks.isEmpty) const EmptyContent('这天没有安排', '可以查看另一天的计划。'),
              for (final task in tasks)
                DetailRow(
                  inset: false,
                  title: model.taskTitle(task),
                  subtitle:
                      '${task.kind == TaskKind.review ? '复习 · 到期后考核' : '新背'} · ${model.taskScheduleLabel(task)}',
                  done: task.status == TaskStatus.completed,
                  onTap: model.canStartEarly(task)
                      ? () => Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => TaskReadingPage(
                              model: model,
                              task: task,
                              allowEarly: true,
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.model});
  final AppModel model;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final search = TextEditingController();
  int filter = 0;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void importArticle() => Navigator.of(
    context,
    rootNavigator: true,
  ).push(CupertinoPageRoute(builder: (_) => ImportPage(model: widget.model)));

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final query = search.text.trim().toLowerCase();
    final visible = model.articles.where((article) {
      final progress = model.articleProgress(article);
      final matches =
          article.title.toLowerCase().contains(query) ||
          (article.author ?? '').toLowerCase().contains(query);
      return matches &&
          (filter == 0 ||
              (filter == 1 &&
                  progress.active &&
                  progress.mastered < progress.total) ||
              (filter == 2 &&
                  progress.total > 0 &&
                  progress.mastered == progress.total));
    }).toList();
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('文库'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: importArticle,
          child: Semantics(
            label: '导入文章',
            child: const Icon(CupertinoIcons.add),
          ),
        ),
      ),
      child: SafeArea(
        child: model.articles.isEmpty
            ? EmptyContent(
                '文库还是空的',
                '导入第一篇文章后，可以确认分段并安排计划。',
                action: PrimaryAction('导入文章', onPressed: importArticle),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Design.inset,
                  20,
                  Design.inset,
                  24,
                ),
                children: [
                  const Text('你的文库', style: Design.display),
                  const SizedBox(height: 6),
                  const Text('把想记住的文字，放在这里', style: Design.caption),
                  const SizedBox(height: 20),
                  CupertinoSearchTextField(
                    controller: search,
                    placeholder: '搜索文章或作者',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: filter,
                    children: const {
                      0: Text('全部'),
                      1: Text('背诵中'),
                      2: Text('已完成'),
                    },
                    onValueChanged: (value) {
                      if (value != null) setState(() => filter = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    EmptyContent(
                      query.isNotEmpty
                          ? '没有找到相关文章'
                          : filter == 2
                          ? '还没有完成的文章'
                          : '还没有正在背诵的文章',
                      query.isNotEmpty
                          ? '试试其他标题或作者关键词。'
                          : filter == 2
                          ? '当前原文的所有小节通过后，会显示在这里。'
                          : '先为文章制定一个学习计划。',
                    ),
                  for (final article in visible) ...[
                    DetailRow(
                      inset: false,
                      title: article.title,
                      subtitle:
                          '${article.author ?? '未填写作者'} · ${model.articleProgress(article).total}节 · ${model.articleProgress(article).mastered}节已掌握',
                      progress: model.articleProgress(article).total == 0
                          ? null
                          : model.articleProgress(article).mastered /
                                model.articleProgress(article).total,
                      icon: CupertinoIcons.book,
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  ArticlePage(model: model, article: article),
                            ),
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const CardSection(
                    child: Text(
                      '先保存原文与段落，再把文章加入计划。每一节都可以单独阅读、考核和复习。',
                      style: Design.caption,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.model});
  final AppModel model;
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final title = TextEditingController();
  final author = TextEditingController();
  final text = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    title.dispose();
    author.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final preview = previewImportedText(
        title: title.text,
        author: author.text,
        text: text.text,
      );
      setState(() => busy = false);
      final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
        CupertinoPageRoute(
          builder: (_) =>
              SegmentPreviewPage(model: widget.model, draft: preview),
        ),
      );
      if (saved == true && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('导入文章')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Design.inset, 20, Design.inset, 30),
        children: [
          const Text('准备原文', style: Design.heading),
          const SizedBox(height: 8),
          const Text('建议段落之间空一行，保存前会先检查分段。', style: Design.caption),
          const SizedBox(height: 20),
          CardSection(
            child: Column(
              children: [
                CupertinoTextField(
                  controller: title,
                  placeholder: '文章标题',
                  padding: const EdgeInsets.all(15),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: author,
                  placeholder: '作者（可选）',
                  padding: const EdgeInsets.all(15),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: text,
                  placeholder: '粘贴正文',
                  maxLines: 14,
                  minLines: 10,
                  padding: const EdgeInsets.all(15),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ],
            ),
          ),
          PrimaryAction('预览分段', onPressed: save, busy: busy),
          CupertinoButton(
            onPressed: () async {
              try {
                final file = await openFile(
                  acceptedTypeGroups: const [
                    XTypeGroup(
                      label: '文本文件',
                      extensions: ['txt'],
                      uniformTypeIdentifiers: ['public.plain-text'],
                    ),
                  ],
                );
                if (file != null) {
                  final content = await file.readAsString();
                  if (mounted) text.text = content;
                }
              } catch (e) {
                if (context.mounted) await showError(context, e);
              }
            },
            child: const Text('导入文本文件'),
          ),
        ],
      ),
    ),
  );
}

class SegmentPreviewPage extends StatefulWidget {
  const SegmentPreviewPage({
    super.key,
    required this.model,
    required this.draft,
  });
  final AppModel model;
  final ImportedText draft;
  @override
  State<SegmentPreviewPage> createState() => _SegmentPreviewPageState();
}

class _SegmentPreviewPageState extends State<SegmentPreviewPage> {
  late List<TextEditingController> sections;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    sections = widget.draft.segments
        .map((s) => TextEditingController(text: s))
        .toList();
  }

  @override
  void dispose() {
    for (final c in sections) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (sections.any((c) => normalizeForAssessment(c.text).isEmpty)) {
        throw const FormatException('每节都需要有效正文，请补全空白小节');
      }
      await widget.model.service.importPreparedArticle(
        ImportedText(
          title: widget.draft.title,
          author: widget.draft.author,
          segments: sections.map((c) => c.text).toList(),
        ),
      );
      await widget.model.reload();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => busy = false);
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('确认分段')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          Text(widget.draft.title, style: Design.heading),
          const SizedBox(height: 8),
          Text(
            '共 ${sections.length} 节 · ${sections.fold<int>(0, (sum, c) => sum + c.text.trim().length)} 字',
            style: Design.caption,
          ),
          const SizedBox(height: 4),
          const Text('可直接修改、按句拆分或合并相邻段落', style: Design.caption),
          for (var i = 0; i < sections.length; i++) ...[
            const SizedBox(height: Design.sectionGap),
            Text('第${i + 1}节'),
            const SizedBox(height: 8),
            CardSection(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '第${i + 1}节',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${sections[i].text.trim().length} 字',
                        style: Design.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: sections[i],
                    minLines: 3,
                    maxLines: 8,
                    padding: const EdgeInsets.all(12),
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            Wrap(
              children: [
                CupertinoButton(
                  onPressed: busy
                      ? null
                      : () {
                          final parts = splitSegmentIntoSentences(
                            sections[i].text,
                          );
                          if (parts.length < 2) return;
                          setState(() {
                            final old = sections.removeAt(i);
                            old.dispose();
                            sections.insertAll(
                              i,
                              parts.map((s) => TextEditingController(text: s)),
                            );
                          });
                        },
                  child: const Text('按句拆分'),
                ),
                if (i + 1 < sections.length)
                  CupertinoButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            sections[i].text =
                                '${sections[i].text}\n${sections[i + 1].text}';
                            sections.removeAt(i + 1).dispose();
                          }),
                    child: const Text('合并下一节'),
                  ),
              ],
            ),
          ],
          PrimaryAction('保存文章', onPressed: save, busy: busy),
        ],
      ),
    ),
  );
}

class ArticlePage extends StatelessWidget {
  const ArticlePage({super.key, required this.model, required this.article});
  final AppModel model;
  final Article article;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => buildDetails(context),
  );

  Widget buildDetails(BuildContext context) {
    final current = model.articles.firstWhere(
      (a) => a.id == article.id,
      orElse: () => article,
    );
    final version = model.store.getArticleVersion(current.currentVersionId);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(current.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.ellipsis_circle),
          onPressed: () async {
            final action = await showCupertinoModalPopup<String>(
              context: context,
              builder: (c) => CupertinoActionSheet(
                title: const Text('文章操作'),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(c, 'edit'),
                    child: const Text('编辑文章'),
                  ),
                  CupertinoActionSheetAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(c, 'delete'),
                    child: const Text('删除文章'),
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('取消'),
                ),
              ),
            );
            if (!context.mounted) return;
            if (action == 'edit') {
              await Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) =>
                      ArticleEditPage(model: model, article: current),
                ),
              );
              return;
            }
            if (action == 'delete' &&
                await confirm(
                  context,
                  '删除文章？',
                  '删除后原文将从文库移除，历史考核记录会保留。',
                  action: '删除',
                )) {
              try {
                await model.service.deleteArticle(article.id);
                await model.reload();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) await showError(context, e);
              }
            }
          },
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<ArticleVersion?>(
          future: version,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CupertinoActivityIndicator());
            }
            final segments = snapshot.data!.segments;
            return ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                Builder(
                  builder: (_) {
                    final progress = model.articleProgress(current);
                    final ratio = progress.total == 0
                        ? 0.0
                        : progress.mastered / progress.total;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Design.inset,
                        12,
                        Design.inset,
                        8,
                      ),
                      child: CardSection(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const IconBadge(CupertinoIcons.book, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${progress.mastered}/${progress.total} 节已掌握',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                StatusChip(
                                  progress.active ? '背诵中' : '未安排',
                                  color: progress.active
                                      ? Design.accent
                                      : Design.secondary,
                                  background: progress.active
                                      ? Design.accentSoft
                                      : Design.grouped,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ProgressBar(
                              value: ratio,
                              color: ratio == 1
                                  ? Design.success
                                  : Design.accent,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              progress.total == 0
                                  ? '等待安排学习计划'
                                  : '逐节完成无提示考核后会自动更新进度',
                              style: Design.caption,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(Design.inset),
                  child: Text(
                    '${segments.length} 节 · ${current.author ?? '未填写作者'}',
                    style: Design.caption,
                  ),
                ),
                for (final segment in segments)
                  DetailRow(
                    title: '第${segment.order + 1}节',
                    subtitle: segment.text,
                    icon: CupertinoIcons.text_alignleft,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) => SegmentReadingPage(
                              title:
                                  '${current.title} · 第${segment.order + 1}节',
                              text: segment.text,
                            ),
                          ),
                        ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(Design.inset),
                  child: PrimaryAction(
                    '为这篇文章制定计划',
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) =>
                                PlanCreatePage(model: model, article: current),
                          ),
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ArticleEditPage extends StatefulWidget {
  const ArticleEditPage({
    super.key,
    required this.model,
    required this.article,
  });
  final AppModel model;
  final Article article;
  @override
  State<ArticleEditPage> createState() => _ArticleEditPageState();
}

class _ArticleEditPageState extends State<ArticleEditPage> {
  final title = TextEditingController();
  final author = TextEditingController();
  final sections = <TextEditingController>[];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    title.text = widget.article.title;
    author.text = widget.article.author ?? '';
    widget.model.store.getArticleVersion(widget.article.currentVersionId).then((
      version,
    ) {
      if (!mounted || version == null) return;
      setState(
        () => sections.addAll(
          version.segments.map((s) => TextEditingController(text: s.text)),
        ),
      );
    });
  }

  @override
  void dispose() {
    title.dispose();
    author.dispose();
    for (final c in sections) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.model.service.updateArticle(
        article: widget.article,
        title: title.text,
        author: author.text,
        segments: sections.map((c) => c.text).toList(),
      );
      await widget.model.reload();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('编辑文章')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          const Text('修改内容', style: Design.heading),
          const SizedBox(height: 8),
          const Text('保存后会生成新的原文版本，历史成绩继续保留。', style: Design.caption),
          const SizedBox(height: 20),
          CupertinoTextField(
            controller: title,
            placeholder: '文章标题',
            padding: const EdgeInsets.all(15),
          ),
          const SizedBox(height: 10),
          CupertinoTextField(
            controller: author,
            placeholder: '作者（可选）',
            padding: const EdgeInsets.all(15),
          ),
          if (sections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CupertinoActivityIndicator(),
            ),
          for (var i = 0; i < sections.length; i++) ...[
            const SizedBox(height: 18),
            Text('第${i + 1}节', style: Design.caption),
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: sections[i],
              minLines: 3,
              maxLines: 8,
              padding: const EdgeInsets.all(14),
            ),
          ],
          PrimaryAction(
            '保存修改',
            onPressed: sections.isEmpty ? null : save,
            busy: busy,
          ),
        ],
      ),
    ),
  );
}

class PlansPage extends StatelessWidget {
  const PlansPage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('计划'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: model.articles.isEmpty
            ? null
            : () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) => ArticlePickerPage(model: model),
                ),
              ),
        child: Semantics(label: '新建计划', child: const Icon(CupertinoIcons.add)),
      ),
    ),
    child: SafeArea(
      child: model.plans.isEmpty
          ? EmptyContent('还没有学习计划', '先导入文章，再决定每天背几节。')
          : ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    Design.inset,
                    18,
                    Design.inset,
                    8,
                  ),
                  child: Text('安排你的节奏', style: Design.display),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Design.inset),
                  child: Text(
                    '${model.plans.where((p) => !p.paused).length} 个进行中的计划 · ${model.plans.length} 个计划',
                    style: Design.caption,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Design.inset),
                  child: CardSection(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const IconBadge(CupertinoIcons.calendar_today),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '按计划完成新背，再用间隔复习保持记忆。',
                            style: Design.caption,
                          ),
                        ),
                        Text(
                          '${model.dueTasks.length}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionHeader('全部计划'),
                for (final plan in model.plans)
                  DetailRow(
                    title: plan.name,
                    subtitle:
                        '${dateLabel(plan.startDate)}—${dateLabel(plan.endDate)} · ${plan.segmentIds.length}节${plan.paused ? ' · 已暂停' : ''}',
                    icon: CupertinoIcons.calendar_today,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) =>
                                PlanDetailPage(model: model, plan: plan),
                          ),
                        ),
                  ),
              ],
            ),
    ),
  );
}

class SegmentReadingPage extends StatefulWidget {
  const SegmentReadingPage({
    super.key,
    required this.title,
    required this.text,
  });
  final String title;
  final String text;
  @override
  State<SegmentReadingPage> createState() => _SegmentReadingPageState();
}

class _SegmentReadingPageState extends State<SegmentReadingPage> {
  double scale = 1;
  bool showFirstCharacter = false;

  String get displayedText {
    if (!showFirstCharacter || widget.text.isEmpty) return widget.text;
    final hiddenCount = (widget.text.length - 1).clamp(0, 18).toInt();
    return '${String.fromCharCode(widget.text.runes.first)}${List.filled(hiddenCount, '·').join()}';
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('阅读原文')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          Text(widget.title, style: Design.heading),
          const SizedBox(height: 12),
          CardSection(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(CupertinoIcons.textformat_size, color: Design.accent),
                    SizedBox(width: 8),
                    Text('阅读设置', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('字号', style: Design.caption),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(44, 44),
                      onPressed: () => setState(
                        () => scale = (scale - .1).clamp(.8, 1.4).toDouble(),
                      ),
                      child: const Text('小'),
                    ),
                    Text('${(scale * 100).round()}%', style: Design.caption),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(44, 44),
                      onPressed: () => setState(
                        () => scale = (scale + .1).clamp(.8, 1.4).toDouble(),
                      ),
                      child: const Text('大'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(child: Text('首字提示', style: Design.caption)),
                    CupertinoSwitch(
                      value: showFirstCharacter,
                      onChanged: (v) => setState(() => showFirstCharacter = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Design.sectionGap),
          Text(
            displayedText,
            style: Design.reading.copyWith(fontSize: 20 * scale),
          ),
          const SizedBox(height: 16),
          const Text('阅读原文属于辅助练习，不会生成自动通过记录。', style: Design.caption),
        ],
      ),
    ),
  );
}

class TaskReadingPage extends StatelessWidget {
  const TaskReadingPage({
    super.key,
    required this.model,
    required this.task,
    this.allowEarly = false,
  });
  final AppModel model;
  final Task task;
  final bool allowEarly;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('准备背诵')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          Text(model.taskTitle(task), style: Design.heading),
          if (allowEarly)
            Text('提前新背 · 原定${dateLabel(task.dueDate)}', style: Design.caption),
          CupertinoButton(
            onPressed: () async {
              final saved = await openPostponement(context, model, [task.id]);
              if (saved == true && context.mounted) Navigator.pop(context);
            },
            child: const Text('延后这项任务'),
          ),
          const SizedBox(height: 12),
          CardSection(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const IconBadge(CupertinoIcons.book, size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '先读一遍原文，准备好后选择正式考核方式。正式考核不会显示原文。',
                    style: Design.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Design.gap),
          Text(
            model.segments[task.segmentId]?.text ?? '原文暂时不可用',
            style: Design.reading,
          ),
          const SizedBox(height: Design.sectionGap),
          CupertinoButton(
            onPressed: model.segments.containsKey(task.segmentId)
                ? () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => SegmentReadingPage(
                        title: model.taskTitle(task),
                        text: model.segments[task.segmentId]!.text,
                      ),
                    ),
                  )
                : null,
            child: const Text('进入辅助阅读'),
          ),
          PrimaryAction(
            '开始无提示考核',
            onPressed: model.segments.containsKey(task.segmentId)
                ? () => Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => TextAssessmentPage(
                        model: model,
                        task: task,
                        allowEarly: allowEarly,
                      ),
                    ),
                  )
                : null,
          ),
          CupertinoButton(
            onPressed: model.segments.containsKey(task.segmentId)
                ? () => Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => SpeechAssessmentPage(
                        model: model,
                        task: task,
                        allowEarly: allowEarly,
                      ),
                    ),
                  )
                : null,
            child: const Text('语音输入考核'),
          ),
        ],
      ),
    ),
  );
}

class ArticlePickerPage extends StatelessWidget {
  const ArticlePickerPage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('选择文章')),
    child: SafeArea(
      child: ListView(
        children: [
          for (final article in model.articles)
            DetailRow(
              title: article.title,
              subtitle: article.author ?? '未填写作者',
              icon: CupertinoIcons.book,
              onTap: () async {
                final created = await Navigator.of(context, rootNavigator: true)
                    .push<bool>(
                      CupertinoPageRoute(
                        builder: (_) =>
                            PlanCreatePage(model: model, article: article),
                      ),
                    );
                if (context.mounted && created == true) {
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
    ),
  );
}

class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({super.key, required this.model, required this.plan});
  final AppModel model;
  final Plan plan;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => buildDetails(context),
  );

  Widget buildDetails(BuildContext context) {
    final current = model.plans.firstWhere(
      (p) => p.id == plan.id,
      orElse: () => plan,
    );
    final tasks = model.tasks.where((t) => t.planId == plan.id).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final completed = tasks
        .where(
          (t) =>
              t.kind == TaskKind.newLearning &&
              t.status == TaskStatus.completed,
        )
        .length;
    final totalNew = tasks.where((t) => t.kind == TaskKind.newLearning).length;
    final progress = totalNew == 0 ? 0.0 : completed / totalNew;
    final completedReviews = tasks
        .where(
          (t) => t.kind == TaskKind.review && t.status == TaskStatus.completed,
        )
        .length;
    final totalReviews = tasks.where((t) => t.kind == TaskKind.review).length;
    final needsReview = model.attempts
        .where(
          (a) =>
              tasks.any((t) => t.id == a.taskId) &&
              a.status == AttemptStatus.needsReview,
        )
        .length;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(current.name),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.ellipsis_circle),
          onPressed: () async {
            final action = await showCupertinoModalPopup<String>(
              context: context,
              builder: (c) => CupertinoActionSheet(
                title: const Text('计划操作'),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(c, 'edit'),
                    child: const Text('编辑计划'),
                  ),
                  CupertinoActionSheetAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(c, 'delete'),
                    child: const Text('删除计划'),
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('取消'),
                ),
              ),
            );
            if (!context.mounted) return;
            if (action == 'edit') {
              await Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) => PlanEditPage(model: model, plan: current),
                ),
              );
            } else if (action == 'delete' &&
                await confirm(
                  context,
                  '删除计划？',
                  '已完成的历史记录会保留，未完成任务会从计划中移除。',
                  action: '删除',
                )) {
              try {
                await model.service.deletePlan(current.id);
                await model.reload();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) await showError(context, e);
              }
            }
          },
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(Design.inset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已完成 $completed / $totalNew 节新背', style: Design.heading),
                  const SizedBox(height: Design.gap),
                  ProgressBar(
                    value: progress,
                    color: progress == 1 && totalNew > 0
                        ? Design.success
                        : Design.accent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress == 1 && totalNew > 0
                        ? '新背内容已全部完成'
                        : '完成新背后会自动进入间隔复习',
                    style: Design.caption,
                  ),
                  const SizedBox(height: Design.gap),
                  Row(
                    children: [
                      MetricTile(
                        value: '$completedReviews/$totalReviews',
                        label: '复习完成',
                        detail: '已安排复习',
                      ),
                      MetricTile(
                        value: '$needsReview',
                        label: '待人工复核',
                        detail: '需确认结果',
                        color: needsReview > 0 ? Design.error : Design.ink,
                      ),
                    ],
                  ),
                  const SizedBox(height: Design.gap),
                  Text(
                    '${dateLabel(current.startDate)} 至 ${dateLabel(current.endDate)}\n每天 ${current.dailyNewQuota} 节 · 一致率至少 ${current.rule.accuracyThreshold}% · 覆盖率至少 ${current.rule.coverageThreshold}%',
                    style: Design.caption,
                  ),
                  PlanPauseControl(model: model, plan: current),
                  DetailRow(
                    inset: false,
                    title: '计划月历',
                    subtitle: '按日期查看本计划',
                    icon: CupertinoIcons.calendar,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) => ScheduleCalendarPage(
                              model: model,
                              planId: current.id,
                            ),
                          ),
                        ),
                  ),
                  if (!current.paused &&
                      tasks.any(
                        (t) =>
                            t.kind == TaskKind.newLearning &&
                            t.status == TaskStatus.pending,
                      ))
                    DetailRow(
                      inset: false,
                      title: '重新安排新背',
                      subtitle: '修改每日配额和学习日，先预览再保存',
                      icon: CupertinoIcons.calendar,
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) => ScheduleReplanPage(
                                model: model,
                                planId: current.id,
                              ),
                            ),
                          ),
                    ),
                ],
              ),
            ),
            for (final task in tasks) ...[
              DetailRow(
                title: model.taskTitle(task),
                subtitle:
                    '${dateLabel(task.dueDate)} · ${task.kind == TaskKind.newLearning ? '新背' : '复习'} · ${model.taskScheduleLabel(task)}',
                done: task.status == TaskStatus.completed,
                onTap:
                    task.status == TaskStatus.pending &&
                        (!task.dueDate.isAfter(model.today) ||
                            model.canStartEarly(task)) &&
                        !current.paused
                    ? () => Navigator.of(context, rootNavigator: true).push(
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
              if (task.status == TaskStatus.pending && !current.paused)
                CupertinoButton(
                  onPressed: () => openPostponement(context, model, [task.id]),
                  child: Text(
                    '调整第${(model.segments[task.segmentId]?.order ?? 0) + 1}节的日期',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlanEditPage extends StatefulWidget {
  const PlanEditPage({super.key, required this.model, required this.plan});
  final AppModel model;
  final Plan plan;
  @override
  State<PlanEditPage> createState() => _PlanEditPageState();
}

class _PlanEditPageState extends State<PlanEditPage> {
  late final TextEditingController name = TextEditingController(
    text: widget.plan.name,
  );
  late double accuracy = widget.plan.rule.accuracyThreshold.toDouble();
  late double coverage = widget.plan.rule.coverageThreshold.toDouble();
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.model.service.updatePlan(
        Plan(
          id: widget.plan.id,
          name: name.text.trim(),
          segmentIds: widget.plan.segmentIds,
          startDate: widget.plan.startDate,
          endDate: widget.plan.endDate,
          dailyNewQuota: widget.plan.dailyNewQuota,
          weekdays: widget.plan.weekdays,
          timeZone: widget.plan.timeZone,
          paused: widget.plan.paused,
          rule: AssessmentRule(
            accuracyThreshold: accuracy.round(),
            coverageThreshold: coverage.round(),
            requireKeywords: widget.plan.rule.requireKeywords,
            ignorePunctuation: widget.plan.rule.ignorePunctuation,
          ),
        ),
      );
      await widget.model.reload();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('编辑计划')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          const Text('计划设置', style: Design.heading),
          const SizedBox(height: 8),
          const Text('修改名称和考核标准，原有任务与历史记录会保留。', style: Design.caption),
          const SizedBox(height: 20),
          CupertinoTextField(
            controller: name,
            placeholder: '计划名称',
            padding: const EdgeInsets.all(15),
          ),
          const SizedBox(height: 24),
          Text('一致率至少 ${accuracy.round()}%'),
          CupertinoSlider(
            value: accuracy,
            min: 80,
            max: 100,
            divisions: 20,
            onChanged: busy ? null : (v) => setState(() => accuracy = v),
          ),
          Text('覆盖率至少 ${coverage.round()}%'),
          CupertinoSlider(
            value: coverage,
            min: 80,
            max: 100,
            divisions: 20,
            onChanged: busy ? null : (v) => setState(() => coverage = v),
          ),
          PrimaryAction('保存计划', onPressed: save, busy: busy),
        ],
      ),
    ),
  );
}

class PlanPauseControl extends StatefulWidget {
  const PlanPauseControl({super.key, required this.model, required this.plan});
  final AppModel model;
  final Plan plan;
  @override
  State<PlanPauseControl> createState() => _PlanPauseControlState();
}

class _PlanPauseControlState extends State<PlanPauseControl> {
  bool busy = false;
  Future<void> change(bool paused) async {
    setState(() => busy = true);
    try {
      await widget.model.service.setPlanPaused(widget.plan.id, paused);
      await widget.model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: Text('暂停计划')),
          CupertinoSwitch(
            value: widget.plan.paused,
            onChanged: busy ? null : change,
          ),
        ],
      ),
      if (widget.plan.paused)
        const Text('任务和历史记录已保留，继续后可补背到期任务。', style: Design.caption),
    ],
  );
}

class ArticleSelectionPage extends StatefulWidget {
  const ArticleSelectionPage({
    super.key,
    required this.model,
    required this.selected,
  });
  final AppModel model;
  final List<String> selected;
  @override
  State<ArticleSelectionPage> createState() => _ArticleSelectionPageState();
}

class _ArticleSelectionPageState extends State<ArticleSelectionPage> {
  late final ids = [...widget.selected];
  void toggle(String id) => setState(() {
    if (!ids.remove(id)) ids.add(id);
  });
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('计划文章'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: ids.isEmpty ? null : () => Navigator.pop(context, ids),
        child: const Text('确定'),
      ),
    ),
    child: SafeArea(
      child: ListView(
        children: [
          for (final article in widget.model.articles)
            CupertinoListTile(
              title: Text(article.title),
              subtitle: Text(article.author ?? '未填写作者'),
              leading: CupertinoCheckbox(
                value: ids.contains(article.id),
                onChanged: (_) => toggle(article.id),
              ),
              onTap: () => toggle(article.id),
            ),
        ],
      ),
    ),
  );
}

class PlanCreatePage extends StatefulWidget {
  const PlanCreatePage({super.key, required this.model, required this.article});
  final AppModel model;
  final Article article;
  @override
  State<PlanCreatePage> createState() => _PlanCreatePageState();
}

class _PlanCreatePageState extends State<PlanCreatePage> {
  final name = TextEditingController(text: '我的背诵计划');
  int quota = 1;
  int accuracy = 90;
  int coverage = 95;
  AssessmentRule get rule =>
      AssessmentRule(accuracyThreshold: accuracy, coverageThreshold: coverage);
  late DateTime start;
  late DateTime end;
  bool busy = false;
  final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
  late List<String> selectedIds;
  List<Article> get selectedArticles => [
    for (final id in selectedIds)
      widget.model.articles.firstWhere((a) => a.id == id),
  ];
  int get segmentCount => widget.model.segments.values
      .where(
        (s) => selectedArticles.any((a) => a.currentVersionId == s.versionId),
      )
      .length;
  @override
  void initState() {
    super.initState();
    start = widget.model.today;
    end = DateTime(start.year, start.month, start.day + 30);
    selectedIds = [widget.article.id];
  }

  SchedulePreview get preview => previewPlan(
    Plan(
      id: 'draft',
      name: name.text,
      segmentIds: List.generate(segmentCount, (i) => 's$i'),
      startDate: start,
      endDate: end,
      dailyNewQuota: quota,
      weekdays: weekdays,
      rule: rule,
      timeZone: 'Asia/Shanghai',
    ),
  );
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (busy) return;
    if (name.text.trim().isEmpty) {
      await showError(context, const FormatException('请先填写计划名称'));
      return;
    }
    if (selectedIds.isEmpty) {
      await showError(context, const FormatException('请至少选择一篇文章'));
      return;
    }
    if (weekdays.isEmpty) {
      await showError(context, const FormatException('请至少选择一个学习日'));
      return;
    }
    if (end.isBefore(start)) {
      await showError(context, const FormatException('截止日期不能早于开始日期'));
      return;
    }
    if (!preview.fits) {
      await showError(context, StateError('当前安排无法覆盖全部内容，请延长日期或增加每日新背节数'));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.model.service.createPlan(
        name: name.text,
        versionIds: selectedArticles.map((a) => a.currentVersionId).toList(),
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day),
        quota: quota,
        weekdays: weekdays,
        rule: rule,
      );
      await widget.model.reload();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseDate(bool isStart) async {
    var selected = isStart ? start : end;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => Container(
        height: 330,
        color: CupertinoColors.systemBackground,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('取消'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, selected),
                    child: const Text('确定'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selected,
                  onDateTimeChanged: (d) => selected = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      if (!isStart && picked.isBefore(start)) {
        await showError(context, const FormatException('截止日期不能早于开始日期'));
        return;
      }
      setState(() {
        if (isStart) {
          start = picked;
          if (!end.isAfter(picked)) {
            end = DateTime(picked.year, picked.month, picked.day + 30);
          }
        } else {
          end = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('新建计划')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          const Text('把目标安排到每天', style: Design.heading),
          const SizedBox(height: 8),
          const Text('先选文章，再设置节奏和通过标准；创建后可随时暂停。', style: Design.caption),
          const SizedBox(height: 20),
          CupertinoTextField(
            controller: name,
            padding: const EdgeInsets.all(16),
            placeholder: '计划名称',
          ),
          const SizedBox(height: 16),
          DetailRow(
            inset: false,
            title: '计划文章 · ${selectedIds.length}篇',
            subtitle: selectedArticles.map((a) => a.title).join('、'),
            icon: CupertinoIcons.book,
            onTap: busy
                ? null
                : () async {
                    final selected =
                        await Navigator.of(
                          context,
                          rootNavigator: true,
                        ).push<List<String>>(
                          CupertinoPageRoute(
                            builder: (_) => ArticleSelectionPage(
                              model: widget.model,
                              selected: selectedIds,
                            ),
                          ),
                        );
                    if (selected != null && mounted) {
                      setState(() => selectedIds = selected);
                    }
                  },
          ),
          DetailRow(
            inset: false,
            title: '开始日期',
            subtitle: dateLabel(start),
            icon: CupertinoIcons.calendar,
            onTap: () => chooseDate(true),
          ),
          DetailRow(
            inset: false,
            title: '截止日期',
            subtitle: dateLabel(end),
            icon: CupertinoIcons.calendar,
            onTap: () => chooseDate(false),
          ),
          const SizedBox(height: 8),
          CardSection(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const IconBadge(CupertinoIcons.clock, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '排期预览',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview.fits
                            ? '按当前节奏预计 ${dateLabel(preview.finishDate!)} 完成新背'
                            : '当前日期和每日节数无法覆盖全部内容',
                        style: Design.caption,
                      ),
                    ],
                  ),
                ),
                Text(
                  '$segmentCount节',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CardSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('每天新背'),
                const SizedBox(height: Design.gap),
                CupertinoSegmentedControl<int>(
                  groupValue: quota,
                  children: const {
                    1: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('1节'),
                    ),
                    2: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('2节'),
                    ),
                    3: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('3节'),
                    ),
                  },
                  onValueChanged: (v) => setState(() => quota = v),
                ),
                const SizedBox(height: 20),
                const Text('学习日'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      Semantics(
                        label:
                            '星期${['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                        selected: weekdays.contains(day),
                        child: CupertinoButton(
                          color: weekdays.contains(day)
                              ? Design.accentSoft
                              : Design.grouped,
                          borderRadius: BorderRadius.circular(8),
                          padding: const EdgeInsets.all(12),
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  if (!weekdays.add(day)) weekdays.remove(day);
                                }),
                          child: Text(
                            ['一', '二', '三', '四', '五', '六', '日'][day - 1],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CardSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('通过标准：一致率 $accuracy%'),
                CupertinoSlider(
                  value: accuracy.toDouble(),
                  min: 80,
                  max: 100,
                  divisions: 20,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => accuracy = v.round()),
                ),
                Text('原文覆盖率 $coverage%'),
                CupertinoSlider(
                  value: coverage.toDouble(),
                  min: 80,
                  max: 100,
                  divisions: 20,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => coverage = v.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: Design.gap),
          Text(
            '${selectedIds.length}篇文章 · 共$segmentCount节',
            style: Design.caption,
          ),
          Text(
            preview.fits
                ? '预计 ${dateLabel(preview.finishDate!)} 完成新背'
                : '当前安排无法完成，请调整日期或每日节数',
            style: Design.caption,
          ),
          PrimaryAction(
            '创建计划',
            onPressed: preview.fits ? create : null,
            busy: busy,
          ),
        ],
      ),
    ),
  );
}

class SpeechAssessmentPage extends StatefulWidget {
  const SpeechAssessmentPage({
    super.key,
    required this.model,
    required this.task,
    this.speechProvider,
    this.allowEarly = false,
  });
  final AppModel model;
  final Task task;
  final SpeechProvider? speechProvider;
  final bool allowEarly;
  @override
  State<SpeechAssessmentPage> createState() => _SpeechAssessmentPageState();
}

class _SpeechAssessmentPageState extends State<SpeechAssessmentPage> {
  late final SpeechProvider provider;
  StreamSubscription<SpeechUpdate>? subscription;
  Timer? ticker;
  SpeechState state = SpeechState.idle;
  String transcript = '';
  String? error;
  bool busy = false;
  bool leaving = false;
  bool hasSession = false;
  bool interruptionRecorded = false;
  Attempt? result;
  late String attemptId;
  final active = Stopwatch();

  @override
  void initState() {
    super.initState();
    provider = widget.speechProvider ?? IosSpeechProvider();
    attemptId = createLocalId();
    subscription = provider.updates.listen((update) {
      if (!mounted || leaving || result != null) return;
      if (update.state == SpeechState.ready && update.finalText != null) {
        if (!busy) unawaited(finish(finalText: update.finalText));
        return;
      }
      setState(() {
        state = busy ? SpeechState.finalizing : update.state;
        error = update.error;
      });
      if (update.state == SpeechState.failed ||
          update.state == SpeechState.unavailable) {
        active.stop();
        unawaited(recordInterruption());
      }
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && active.isRunning) setState(() {});
    });
  }

  Future<void> closeProvider() async {
    await subscription?.cancel();
    try {
      await provider.cancel();
    } catch (_) {
      // A missing platform bridge must not cause an unhandled disposal error.
    }
    if (provider is IosSpeechProvider) {
      await (provider as IosSpeechProvider).dispose();
    }
  }

  @override
  void dispose() {
    leaving = true;
    ticker?.cancel();
    active.stop();
    unawaited(closeProvider());
    super.dispose();
  }

  Future<void> recordInterruption() async {
    if (!hasSession || result != null || interruptionRecorded) return;
    interruptionRecorded = true;
    try {
      await widget.model.service.submitFinalTranscript(
        taskId: widget.task.id,
        attemptId: attemptId,
        transcript: '',
        isFinal: true,
        technicalFailure: true,
        activeSeconds: active.elapsed.inSeconds,
      );
      await widget.model.reload();
    } catch (e) {
      if (mounted && !leaving) {
        setState(() => error = '录音已停止，记录未保存，请重试');
      }
    }
  }

  Future<void> start() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      state = SpeechState.idle;
      transcript = '';
      attemptId = createLocalId();
      hasSession = false;
      interruptionRecorded = false;
      active.reset();
    });
    try {
      if (!await provider.requestPermission()) {
        if (mounted && !leaving) {
          setState(() {
            state = SpeechState.unavailable;
            error = '需要麦克风和语音识别权限，请在系统设置中允许后重试';
          });
        }
        return;
      }
      if (!mounted || leaving) return;
      await provider.start(locale: 'zh-CN');
      if (!mounted || leaving) {
        await provider.cancel();
        return;
      }
      hasSession = true;
      active.start();
      setState(() => state = SpeechState.recording);
    } catch (e) {
      if (mounted && !leaving) {
        setState(() {
          state = SpeechState.failed;
          error = e is PlatformException
              ? e.message ?? '录音启动失败，请重试'
              : '此设备暂时无法启动语音识别，请重试或使用文字考核';
        });
      }
    } finally {
      if (mounted && !leaving) setState(() => busy = false);
    }
  }

  Future<void> finish({String? finalText}) async {
    if (busy ||
        leaving ||
        result != null ||
        (finalText == null && state != SpeechState.recording)) {
      return;
    }
    active.stop();
    setState(() {
      state = SpeechState.finalizing;
      busy = true;
    });
    try {
      final text = finalText ?? (await provider.stopAndFinalize()).finalText;
      if (!mounted || leaving) return;
      if (text == null || normalizeForAssessment(text).isEmpty) {
        throw StateError('没有识别到有效内容，请重新背诵');
      }
      final attempt = await widget.model.service.submitFinalTranscript(
        taskId: widget.task.id,
        attemptId: attemptId,
        transcript: text,
        isFinal: true,
        allowEarly: widget.allowEarly,
        activeSeconds: active.elapsed.inSeconds,
      );
      await widget.model.reload();
      if (mounted && !leaving) {
        setState(() {
          result = attempt;
          state = SpeechState.ready;
          transcript = text;
        });
      }
    } catch (e) {
      if (mounted && !leaving) {
        setState(() {
          state = SpeechState.failed;
          error = e is StateError
              ? e.message
              : e is PlatformException
              ? e.message ?? '识别中断，请重试'
              : '识别或校对失败，请重试';
        });
        await recordInterruption();
      }
    } finally {
      if (mounted && !leaving) setState(() => busy = false);
    }
  }

  void retry() {
    active.reset();
    setState(() {
      result = null;
      transcript = '';
      error = null;
      state = SpeechState.idle;
      hasSession = false;
    });
  }

  Future<void> exit() async {
    if (leaving || busy) return;
    if (hasSession && result == null && state == SpeechState.recording) {
      if (!await confirm(
        context,
        '结束本次考核？',
        '录音将停止，本次记为中断，任务仍需完成。',
        action: '结束考核',
      )) {
        return;
      }
    }
    if (!mounted) return;
    leaving = true;
    active.stop();
    try {
      await provider.cancel();
    } catch (_) {}
    await recordInterruption();
    if (!mounted) return;
    setState(() {});
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final score = result?.score;
    final recording = state == SpeechState.recording;
    final finalizing = state == SpeechState.finalizing || busy;
    final elapsed = active.elapsed;
    final duration =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: leaving || (!hasSession && !busy) || result != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) unawaited(exit());
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('语音考核'),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: busy ? null : exit,
            child: const Text('返回'),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              Text(widget.model.taskTitle(widget.task), style: Design.heading),
              const SizedBox(height: 8),
              Text(
                recording ? '请自然背诵，结束后与原文校对。' : '原文和实时转录已隐藏，准备好后开始录音。',
                style: Design.caption,
              ),
              const SizedBox(height: 22),
              CardSection(
                child: Column(
                  children: [
                    Icon(
                      recording ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                      size: 46,
                      color: recording ? Design.error : Design.accent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      finalizing
                          ? '正在处理，请稍候'
                          : recording
                          ? '正在聆听'
                          : result != null
                          ? '已完成校对'
                          : '等待开始',
                      style: Design.heading,
                    ),
                    const SizedBox(height: 12),
                    if (finalizing)
                      const CupertinoActivityIndicator()
                    else
                      Text(duration, style: Design.display),
                    const SizedBox(height: 12),
                    const Text(
                      '语音识别由 iOS 系统提供，可能需要联网。录音不保存。',
                      style: Design.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                CardSection(
                  child: Text(
                    error!,
                    style: const TextStyle(color: Design.error),
                  ),
                ),
              ],
              if (result != null && score != null) ...[
                const SizedBox(height: 16),
                CardSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusChip(
                        result!.status == AttemptStatus.passed
                            ? '考核通过'
                            : result!.status == AttemptStatus.needsReview
                            ? '识别待确认'
                            : '仍需练习',
                        color: result!.status == AttemptStatus.passed
                            ? Design.success
                            : Design.error,
                        background: result!.status == AttemptStatus.passed
                            ? Design.successSoft
                            : Design.errorSoft,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${score.accuracy.toStringAsFixed(1)}%',
                        style: Design.display,
                      ),
                      Text(
                        '内容一致率 · 原文覆盖率 ${score.coverage.toStringAsFixed(1)}%',
                        style: Design.caption,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '漏字 ${score.deleted} · 错字 ${score.substituted} · 多说 ${score.inserted}',
                        style: Design.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CompletionFeedback(
                  model: widget.model,
                  task: widget.task,
                  attempt: result!,
                ),
                Text(
                  '原文：${widget.model.segments[widget.task.segmentId]?.text ?? ''}',
                  style: Design.reading,
                ),
                const SizedBox(height: 16),
                Text('你的背诵：$transcript', style: Design.reading),
              ],
              if (result == null && !recording && !finalizing)
                PrimaryAction('开始录音', onPressed: start),
              if (recording) PrimaryAction('结束并校对', onPressed: finish),
              if (result != null) PrimaryAction('再次考核', onPressed: retry),
              CupertinoButton(
                onPressed: busy ? null : exit,
                child: const Text('退出考核'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TextAssessmentPage extends StatefulWidget {
  const TextAssessmentPage({
    super.key,
    required this.model,
    required this.task,
    this.allowEarly = false,
  });
  final AppModel model;
  final Task task;
  final bool allowEarly;
  @override
  State<TextAssessmentPage> createState() => _TextAssessmentPageState();
}

class _TextAssessmentPageState extends State<TextAssessmentPage>
    with WidgetsBindingObserver {
  final answer = TextEditingController();
  bool busy = false;
  Attempt? result;
  final active = Stopwatch();
  late String attemptId;
  @override
  void initState() {
    super.initState();
    attemptId = createLocalId();
    active.start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && result == null) {
      active.start();
    } else {
      active.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    answer.dispose();
    active.stop();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (result != null) {
      setState(() {
        result = null;
        answer.clear();
        attemptId = createLocalId();
        active.reset();
        active.start();
      });
      return;
    }
    if (normalizeForAssessment(answer.text).isEmpty) {
      await showError(context, const FormatException('请先输入有效背诵内容'));
      return;
    }
    setState(() => busy = true);
    active.stop();
    try {
      result = await widget.model.service.submitFinalTranscript(
        taskId: widget.task.id,
        attemptId: attemptId,
        transcript: answer.text,
        isFinal: true,
        allowEarly: widget.allowEarly,
        activeSeconds: active.elapsed.inSeconds,
      );
      await widget.model.reload();
    } catch (e) {
      if (mounted) await showError(context, e);
      active.start();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.model.segments[widget.task.segmentId];
    final score = result?.score;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('文字考核')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Design.inset),
          children: [
            Text(widget.model.taskTitle(widget.task), style: Design.heading),
            const SizedBox(height: 8),
            Text('无提示输入背诵内容，提交后与原文校对。', style: Design.caption),
            const SizedBox(height: 24),
            if (result == null)
              CupertinoTextField(
                controller: answer,
                maxLines: 12,
                minLines: 8,
                padding: const EdgeInsets.all(16),
                placeholder: '输入你背出的内容',
                textAlignVertical: TextAlignVertical.top,
              ),
            PrimaryAction(
              result == null ? '提交并校对' : '再次考核',
              onPressed: submit,
              busy: busy,
            ),
            if (result != null && score != null) ...[
              CardSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(
                      result!.status == AttemptStatus.passed
                          ? '考核通过'
                          : result!.status == AttemptStatus.needsReview
                          ? '识别待确认'
                          : '仍需练习',
                      color: result!.status == AttemptStatus.passed
                          ? Design.success
                          : Design.error,
                      background: result!.status == AttemptStatus.passed
                          ? Design.successSoft
                          : Design.errorSoft,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${score.accuracy.toStringAsFixed(1)}%',
                      style: Design.display,
                    ),
                    const Text('内容一致率', style: Design.caption),
                    const SizedBox(height: 12),
                    ProgressBar(
                      value: score.accuracy / 100,
                      color: result!.status == AttemptStatus.passed
                          ? Design.success
                          : Design.accent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '原文覆盖率 ${score.coverage.toStringAsFixed(1)}%',
                      style: Design.caption,
                    ),
                    Text(
                      '漏字 ${score.deleted} · 错字 ${score.substituted} · 多说 ${score.inserted}',
                      style: Design.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CompletionFeedback(
                model: widget.model,
                task: widget.task,
                attempt: result!,
              ),
              Text('原文：${segment?.text ?? ''}', style: Design.reading),
              const SizedBox(height: 16),
              Text('你的背诵：${result!.transcript ?? ''}', style: Design.reading),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final report = model.report(ReportPeriod.week, model.today);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('我的')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Design.inset),
          children: [
            const Text('我的学习', style: Design.display),
            const SizedBox(height: 16),
            CardSection(
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.person_crop_circle,
                    size: 44,
                    color: Design.accent,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本机学习档案', style: Design.heading),
                        SizedBox(height: 4),
                        Text('不登录也能使用，数据保存在此设备。', style: Design.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CardSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本周学习', style: Design.heading),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      MetricTile(
                        value: '${report.completedTasks}',
                        label: '完成任务',
                        detail: '共 ${report.dueTasks} 个到期',
                        color: Design.success,
                      ),
                      MetricTile(
                        value: '${report.learningDays}',
                        label: '学习天数',
                        detail: '有效学习日',
                      ),
                      MetricTile(
                        value: '${report.focusMinutes}',
                        label: '学习分钟',
                        detail: '有效时长',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    report.dueTasks == 0
                        ? '暂无到期任务'
                        : '${report.completedTasks} / ${report.dueTasks} 个任务完成',
                  ),
                  const SizedBox(height: 8),
                  ProgressBar(
                    value: report.dueTasks == 0
                        ? 0
                        : report.completedTasks / report.dueTasks,
                    color:
                        report.completedTasks == report.dueTasks &&
                            report.dueTasks > 0
                        ? Design.success
                        : Design.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '有效学习 ${report.focusMinutes} 分钟 · 学习 ${report.learningDays} 天',
                    style: Design.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            DetailRow(
              inset: false,
              title: '学习报告',
              subtitle: '周报 · 月报 · 年报',
              icon: CupertinoIcons.chart_bar,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => ReportsPage(model: model)),
              ),
            ),
            DetailRow(
              inset: false,
              title: '备份与恢复',
              subtitle: model.backupDue ? '已超过七天，建议导出一份档案' : '导出或恢复本机学习档案',
              icon: CupertinoIcons.archivebox,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => BackupPage(model: model)),
              ),
            ),
            DetailRow(
              inset: false,
              title: '提醒设置',
              subtitle: '学习时间与每周备份提醒',
              icon: CupertinoIcons.bell,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) => ReminderSettingsPage(model: model),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.model});
  final AppModel model;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportPeriod period = ReportPeriod.week;
  late DateTime anchor;
  @override
  void initState() {
    super.initState();
    anchor = widget.model.today;
  }

  void move(int direction) => setState(() {
    anchor = switch (period) {
      ReportPeriod.week => DateTime(
        anchor.year,
        anchor.month,
        anchor.day + 7 * direction,
      ),
      ReportPeriod.month => DateTime(anchor.year, anchor.month + direction),
      ReportPeriod.year => DateTime(anchor.year + direction),
    };
  });
  @override
  Widget build(BuildContext context) {
    final r = widget.model.report(period, anchor);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('学习报告')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Design.inset),
          children: [
            CupertinoSlidingSegmentedControl<ReportPeriod>(
              groupValue: period,
              children: const {
                ReportPeriod.week: Text('周报'),
                ReportPeriod.month: Text('月报'),
                ReportPeriod.year: Text('年报'),
              },
              onValueChanged: (p) {
                if (p != null) setState(() => period = p);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => move(-1),
                  child: const Icon(CupertinoIcons.chevron_left),
                ),
                const Text('查看周期'),
                CupertinoButton(
                  onPressed: r.end.isBefore(widget.model.today)
                      ? () => move(1)
                      : null,
                  child: const Icon(CupertinoIcons.chevron_right),
                ),
              ],
            ),
            Text(
              '${dateLabel(r.start)}—${dateLabel(r.end)}',
              style: Design.caption,
            ),
            const SizedBox(height: Design.sectionGap),
            CardSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MetricTile(
                        value: '${r.completedTasks}/${r.dueTasks}',
                        label: '到期任务',
                        detail: r.completionRate == null
                            ? '本周期暂无任务'
                            : '${r.completionRate!.toStringAsFixed(0)}% 完成',
                        color: Design.success,
                      ),
                      MetricTile(
                        value: '${r.newMasteredSegments}',
                        label: '新掌握',
                        detail: '节',
                      ),
                      MetricTile(
                        value: '${r.learningDays}',
                        label: '学习天数',
                        detail: '${r.focusMinutes} 分钟',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${r.completedTasks} / ${r.dueTasks}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('到期任务完成'),
                  const SizedBox(height: 16),
                  ProgressBar(
                    value: r.dueTasks == 0 ? 0 : r.completedTasks / r.dueTasks,
                    color: Design.success,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '新掌握 ${r.newMasteredSegments} 节 · 学习 ${r.learningDays} 天',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '完整打卡 ${r.checkInDays} 天 · 有效学习 ${r.focusMinutes} 分钟',
                    style: Design.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Design.gap),
            CardSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('复习质量', style: Design.heading),
                  const SizedBox(height: 10),
                  Text(
                    r.reviewRetention == null
                        ? '暂无复习考核'
                        : '复习考核通过 ${r.reviewPasses} / ${r.reviewAttempts} 次',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '辅助练习 ${r.assistedPractices} 次 · 人工确认 ${r.manualConfirmations} 次',
                    style: Design.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Design.gap),
            ReportActivityChart(model: widget.model, report: r),
          ],
        ),
      ),
    );
  }
}

class ReportActivityChart extends StatelessWidget {
  const ReportActivityChart({
    super.key,
    required this.model,
    required this.report,
  });
  final AppModel model;
  final LearningReport report;

  @override
  Widget build(BuildContext context) {
    final buckets = <({String label, DateTime start, DateTime end})>[];
    if (report.period == ReportPeriod.year) {
      for (var month = 1; month <= 12; month++) {
        buckets.add((
          label: '$month月',
          start: DateTime(report.start.year, month),
          end: DateTime(report.start.year, month + 1, 0),
        ));
      }
    } else if (report.period == ReportPeriod.month) {
      for (var day = 1; day <= report.end.day; day += 7) {
        final end = (day + 6).clamp(1, report.end.day);
        buckets.add((
          label: '$day–$end日',
          start: DateTime(report.start.year, report.start.month, day),
          end: DateTime(report.start.year, report.start.month, end),
        ));
      }
    } else {
      for (var i = 0; i < 7; i++) {
        final date = report.start.add(Duration(days: i));
        buckets.add((
          label: ['一', '二', '三', '四', '五', '六', '日'][i],
          start: date,
          end: date,
        ));
      }
    }
    final counts = <int>[];
    for (final bucket in buckets) {
      final ids = <String>{};
      for (final event in model.events) {
        if (event.type != LearningEventType.taskCompleted ||
            event.taskId == null) {
          continue;
        }
        final local = eventLocalTime(event);
        final date = DateTime(local.year, local.month, local.day);
        if (!date.isBefore(bucket.start) &&
            !date.isAfter(bucket.end) &&
            !date.isAfter(model.today)) {
          ids.add(event.taskId!);
        }
      }
      counts.add(ids.length);
    }
    final maximum = counts.fold<int>(
      1,
      (old, count) => count > old ? count : old,
    );
    return CardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('任务完成趋势', style: Design.heading),
          const SizedBox(height: 6),
          const Text('按实际完成日期统计', style: Design.caption),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < buckets.length; i++)
                  Semantics(
                    label: '${buckets[i].label}，完成 ${counts[i]} 个任务',
                    excludeSemantics: true,
                    child: SizedBox(
                      width: Design.chartColumnWidth,
                      child: Column(
                        children: [
                          Text('${counts[i]}', style: Design.caption),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: Design.chartHeight,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: Design.chartBarWidth,
                                height: counts[i] == 0
                                    ? 2
                                    : Design.chartHeight * counts[i] / maximum,
                                decoration: BoxDecoration(
                                  color: counts[i] == 0
                                      ? Design.line
                                      : Design.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            buckets[i].label,
                            style: Design.caption,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('左右滑动查看完整周期', style: Design.caption),
          ),
        ],
      ),
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.model, this.exportArchive});
  final AppModel model;
  final Future<ShareResult> Function(String archive, Rect? origin)?
  exportArchive;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool busy = false;
  BackupService get backup =>
      BackupService(widget.model.store, profileId: 'local-profile');
  Future<ShareResult> shareArchive(String archive, Rect? origin) async {
    final root = await getTemporaryDirectory();
    final file = File(
      '${root.path}/recitation-backup-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(archive, flush: true);
    if (!mounted) return const ShareResult('', ShareResultStatus.dismissed);
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: '背诵计划学习档案',
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> export() async {
    setState(() => busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final shared = await (widget.exportArchive ?? shareArchive)(
        backup.export(),
        origin,
      );
      if (shared.status == ShareResultStatus.success) {
        await widget.model.savePreferences(exported: true);
      }
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    setState(() => busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '学习档案',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null) return;
      final text = await file.readAsString();
      final preview = backup.preview(text);
      if (!preview.canMerge) {
        throw StateError('存在${preview.conflicts.length}条冲突记录，未修改本机数据');
      }
      if (!mounted ||
          !await confirm(
            context,
            '恢复学习档案',
            '新增${preview.added}条，重复${preview.duplicates}条。恢复前会保留当前档案。',
            action: '恢复',
          )) {
        return;
      }
      await backup.restore(
        text,
        saveCurrentArchive: (old) async {
          final root = await getApplicationDocumentsDirectory();
          final dir = await Directory('${root.path}/recitation/recovery')
              .create(recursive: true);
          await File(
            '${dir.path}/before-${DateTime.now().microsecondsSinceEpoch}.json',
          ).writeAsString(old, flush: true);
        },
      );
      await widget.model.reload();
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (c) => CupertinoAlertDialog(
            title: const Text('恢复完成'),
            content: Text(
              '已新增 ${preview.added} 条记录，跳过 ${preview.duplicates} 条重复记录。\n当前档案已在恢复前自动留存。',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(c),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('备份与恢复')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          const Text('保存每一次积累', style: Design.heading),
          DetailRow(
            inset: false,
            title: '本机快照',
            subtitle: '自动留存与恢复到之前的时间点',
            icon: CupertinoIcons.clock,
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => LocalSnapshotsPage(model: widget.model),
              ),
            ),
          ),
          Text(
            widget.model.preferences.lastExportAt == null
                ? '还没有成功导出记录'
                : '上次导出：${dateLabel(localTime(widget.model.preferences.lastExportAt!, 'Asia/Shanghai'))}',
            style: Design.caption,
          ),
          const SizedBox(height: Design.gap),
          const Text(
            '档案包含文章、计划、成绩和复习记录，不包含录音。可通过系统分享保存到文件。',
            style: Design.caption,
          ),
          const SizedBox(height: Design.gap),
          CardSection(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前档案',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    MetricTile(
                      value: '${widget.model.articles.length}',
                      label: '篇文章',
                    ),
                    MetricTile(
                      value: '${widget.model.plans.length}',
                      label: '个计划',
                    ),
                    MetricTile(
                      value: '${widget.model.tasks.length}',
                      label: '条任务',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('导出会包含文章、计划、成绩和复习记录，不会包含录音。', style: Design.caption),
                const SizedBox(height: 8),
                Text(
                  '当前任务 ${widget.model.tasks.length} 条 · 考核记录 ${widget.model.attempts.length} 条',
                  style: Design.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: Design.gap),
          CardSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导出', style: Design.heading),
                const SizedBox(height: 4),
                const Text('生成一份可保存到文件或云盘的完整档案。', style: Design.caption),
                PrimaryAction('导出完整档案', onPressed: export, busy: busy),
              ],
            ),
          ),
          const SizedBox(height: Design.gap),
          CardSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('恢复', style: Design.heading),
                const SizedBox(height: 4),
                const Text('恢复前会自动保留当前档案，重复记录不会覆盖。', style: Design.caption),
                PrimaryAction('从档案恢复', onPressed: restore, busy: busy),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
