import 'package:flutter/cupertino.dart';
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

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final tasks = model.dueTasks;
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
                  const SizedBox(height: 6),
                  Text(
                    tasks.isEmpty ? '今天没有待完成任务' : '今天完成 ${tasks.length} 个任务',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  CardSection(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.sun_max,
                          color: Design.accent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tasks.isEmpty ? '安排一小节，今天就开始' : '完成今天的任务，保持学习节奏',
                            style: Design.caption,
                          ),
                        ),
                        Text(
                          '${tasks.length}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  for (final task in tasks)
                    DetailRow(
                      title: model.taskTitle(task),
                      subtitle:
                          '${task.kind == TaskKind.newLearning ? '新背' : '复习'} · ${model.segments[task.segmentId]?.text ?? ''}',
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
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('文库'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.of(
          context,
          rootNavigator: true,
        ).push(CupertinoPageRoute(builder: (_) => ImportPage(model: model))),
        child: const Icon(CupertinoIcons.add),
      ),
    ),
    child: SafeArea(
      child: model.articles.isEmpty
          ? EmptyContent(
              '文库还是空的',
              '导入第一篇文章后，可以确认分段并安排计划。',
              action: PrimaryAction(
                '导入文章',
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                      CupertinoPageRoute(
                        builder: (_) => ImportPage(model: model),
                      ),
                    ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    Design.inset,
                    8,
                    Design.inset,
                    10,
                  ),
                  child: Text(
                    '你的文章',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                for (final article in model.articles)
                  DetailRow(
                    title: article.title,
                    subtitle:
                        '原文版本 · ${dateLabel(article.updatedAt.toLocal())}',
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
            ),
    ),
  );
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
          Text('共 ${sections.length} 节', style: Design.caption),
          const SizedBox(height: 4),
          const Text('可直接修改或重新拆分', style: Design.caption),
          for (var i = 0; i < sections.length; i++) ...[
            const SizedBox(height: Design.sectionGap),
            Text('第${i + 1}节'),
            const SizedBox(height: 8),
            CardSection(
              padding: const EdgeInsets.all(14),
              child: CupertinoTextField(
                controller: sections[i],
                minLines: 3,
                maxLines: 8,
                padding: const EdgeInsets.all(12),
                textAlignVertical: TextAlignVertical.top,
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
  Widget build(BuildContext context) {
    final version = model.store.getArticleVersion(article.currentVersionId);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(article.title),
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
                      ArticleEditPage(model: model, article: article),
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
                Padding(
                  padding: const EdgeInsets.all(Design.inset),
                  child: Text(
                    '${segments.length} 节 · ${article.author ?? '未填写作者'}',
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
                                  '${article.title} · 第${segment.order + 1}节',
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
                                PlanCreatePage(model: model, article: article),
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
                    8,
                    Design.inset,
                    10,
                  ),
                  child: Text(
                    '学习计划',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
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

class SegmentReadingPage extends StatelessWidget {
  const SegmentReadingPage({
    super.key,
    required this.title,
    required this.text,
  });
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('阅读原文')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          Text(title, style: Design.heading),
          const SizedBox(height: Design.sectionGap),
          Text(text, style: Design.reading),
        ],
      ),
    ),
  );
}

class TaskReadingPage extends StatelessWidget {
  const TaskReadingPage({super.key, required this.model, required this.task});
  final AppModel model;
  final Task task;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('准备背诵')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Design.inset),
        children: [
          Text(model.taskTitle(task), style: Design.heading),
          const SizedBox(height: Design.sectionGap),
          Text(
            model.segments[task.segmentId]?.text ?? '原文暂时不可用',
            style: Design.reading,
          ),
          const SizedBox(height: Design.sectionGap),
          PrimaryAction(
            '开始无提示考核',
            onPressed: model.segments.containsKey(task.segmentId)
                ? () => Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(
                      builder: (_) =>
                          TextAssessmentPage(model: model, task: task),
                    ),
                  )
                : null,
          ),
          CupertinoButton(
            onPressed: model.segments.containsKey(task.segmentId)
                ? () => Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(
                      builder: (_) =>
                          SpeechAssessmentPage(model: model, task: task),
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
                  Text(
                    '已完成 $completed / ${plan.segmentIds.length} 节新背',
                    style: Design.heading,
                  ),
                  const SizedBox(height: Design.gap),
                  Text(
                    '${dateLabel(current.startDate)} 至 ${dateLabel(current.endDate)}\n每天 ${current.dailyNewQuota} 节 · 一致率至少 ${current.rule.accuracyThreshold}% · 覆盖率至少 ${current.rule.coverageThreshold}%',
                    style: Design.caption,
                  ),
                  PlanPauseControl(model: model, plan: current),
                ],
              ),
            ),
            for (final task in tasks)
              DetailRow(
                title: model.taskTitle(task),
                subtitle:
                    '${dateLabel(task.dueDate)} · ${task.kind == TaskKind.newLearning ? '新背' : '复习'} · ${task.status == TaskStatus.completed ? '已完成' : '待完成'}',
                done: task.status == TaskStatus.completed,
                onTap:
                    task.status == TaskStatus.pending &&
                        !task.dueDate.isAfter(model.today) &&
                        !current.paused
                    ? () => Navigator.of(context, rootNavigator: true).push(
                        CupertinoPageRoute(
                          builder: (_) =>
                              TaskReadingPage(model: model, task: task),
                        ),
                      )
                    : null,
              ),
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
      setState(() {
        if (isStart) {
          start = picked;
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
          const SizedBox(height: 20),
          CupertinoTextField(
            controller: name,
            padding: const EdgeInsets.all(16),
            placeholder: '计划名称',
          ),
          const SizedBox(height: 16),
          DetailRow(
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
            title: '开始日期',
            subtitle: dateLabel(start),
            icon: CupertinoIcons.calendar,
            onTap: () => chooseDate(true),
          ),
          DetailRow(
            title: '截止日期',
            subtitle: dateLabel(end),
            icon: CupertinoIcons.calendar,
            onTap: () => chooseDate(false),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每天新背'),
              const SizedBox(height: Design.gap),
              CupertinoSegmentedControl<int>(
                groupValue: quota,
                children: const {1: Text('1节'), 2: Text('2节'), 3: Text('3节')},
                onValueChanged: (v) => setState(() => quota = v),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('学习日'),
          Wrap(
            spacing: 4,
            children: [
              for (var day = 1; day <= 7; day++)
                CupertinoButton(
                  padding: const EdgeInsets.all(10),
                  onPressed: () => setState(() {
                    if (!weekdays.add(day)) weekdays.remove(day);
                  }),
                  child: Text(
                    '${weekdays.contains(day) ? '✓ ' : ''}${['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
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
  });
  final AppModel model;
  final Task task;
  @override
  State<SpeechAssessmentPage> createState() => _SpeechAssessmentPageState();
}

class _SpeechAssessmentPageState extends State<SpeechAssessmentPage> {
  late final IosSpeechProvider provider;
  StreamSubscription<SpeechUpdate>? subscription;
  SpeechState state = SpeechState.idle;
  String transcript = '';
  String? error;
  bool busy = false;
  Attempt? result;
  late String attemptId;
  final active = Stopwatch();

  @override
  void initState() {
    super.initState();
    provider = IosSpeechProvider();
    attemptId = createLocalId();
    subscription = provider.updates.listen((update) {
      if (!mounted) return;
      setState(() {
        state = update.state;
        transcript = update.finalText ?? update.interimText;
        error = update.error;
      });
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    provider.cancel();
    provider.dispose();
    active.stop();
    super.dispose();
  }

  Future<void> start() async {
    setState(() {
      error = null;
      state = SpeechState.idle;
      transcript = '';
    });
    if (!await provider.requestPermission()) {
      setState(() {
        state = SpeechState.unavailable;
        error = '需要麦克风和语音识别权限，请在系统设置中允许后重试';
      });
      return;
    }
    try {
      await provider.start(locale: 'zh-CN');
      active.start();
    } catch (e) {
      setState(() {
        state = SpeechState.failed;
        error = '$e';
      });
    }
  }

  Future<void> finish() async {
    if (state != SpeechState.recording) return;
    active.stop();
    setState(() {
      state = SpeechState.finalizing;
      busy = true;
    });
    try {
      final update = await provider.stopAndFinalize();
      final text = update.finalText ?? transcript;
      if (normalizeForAssessment(text).isEmpty) {
        throw StateError('没有识别到有效内容，请重新背诵');
      }
      final attempt = await widget.model.service.submitFinalTranscript(
        taskId: widget.task.id,
        attemptId: attemptId,
        transcript: text,
        isFinal: true,
        activeSeconds: active.elapsed.inSeconds,
      );
      await widget.model.reload();
      if (mounted) {
        setState(() {
          result = attempt;
          state = SpeechState.ready;
          transcript = text;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          state = SpeechState.failed;
          error = e is StateError ? e.message : '识别或校对失败，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void retry() {
    setState(() {
      result = null;
      attemptId = createLocalId();
      transcript = '';
      error = null;
      state = SpeechState.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final score = result?.score;
    final recording = state == SpeechState.recording;
    final finalizing = state == SpeechState.finalizing || busy;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('语音考核')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Design.inset),
          children: [
            Text(widget.model.taskTitle(widget.task), style: Design.heading),
            const SizedBox(height: 8),
            Text(
              recording ? '请自然背诵，结束后系统会用最终转录和原文校对。' : '原文已隐藏，准备好后开始录音。',
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
                        ? '正在生成最终结果'
                        : recording
                        ? '正在聆听'
                        : state == SpeechState.ready
                        ? '已完成校对'
                        : '等待开始',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ProgressBar(
                    value: recording
                        ? .55
                        : finalizing
                        ? .8
                        : result == null
                        ? 0
                        : 1,
                    color: recording ? Design.error : Design.accent,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    transcript.isEmpty ? '实时转录仅用于显示进度，最终结果才参与考核。' : transcript,
                    style: Design.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              CardSection(
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Design.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: Design.error),
                      ),
                    ),
                  ],
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
                          ? const Color(0xFFEDF8F1)
                          : const Color(0xFFFFF0EE),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${score.accuracy.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '内容一致率 · 原文覆盖率 ${score.coverage.toStringAsFixed(1)}%',
                      style: Design.caption,
                    ),
                  ],
                ),
              ),
            ],
            if (result == null && !recording && !finalizing)
              PrimaryAction('开始录音', onPressed: start),
            if (recording) PrimaryAction('结束并校对', onPressed: finish),
            if (result != null) PrimaryAction('再次考核', onPressed: retry),
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('退出考核'),
            ),
          ],
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
  });
  final AppModel model;
  final Task task;
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
      await showError(context, '请先输入有效背诵内容');
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
              Text(
                result!.status == AttemptStatus.passed
                    ? '考核通过'
                    : result!.status == AttemptStatus.needsReview
                    ? '识别待确认'
                    : '仍需练习',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: result!.status == AttemptStatus.passed
                      ? Design.success
                      : Design.error,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '内容一致率 ${score.accuracy.toStringAsFixed(1)}% · 原文覆盖率 ${score.coverage.toStringAsFixed(1)}%',
                style: Design.caption,
              ),
              Text(
                '漏字 ${score.deleted} · 错字 ${score.substituted} · 多说 ${score.inserted}',
                style: Design.caption,
              ),
              const SizedBox(height: 16),
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
            const Text('本机学习档案', style: Design.heading),
            const SizedBox(height: 8),
            const Text('不登录也能完整使用，数据保存在此设备。', style: Design.caption),
            const SizedBox(height: 28),
            Text('本周学习', style: Design.heading),
            const SizedBox(height: 12),
            Text(
              report.dueTasks == 0
                  ? '暂无到期任务'
                  : '${report.completedTasks} / ${report.dueTasks} 个任务完成',
            ),
            Text(
              '有效学习 ${report.focusMinutes} 分钟 · 学习 ${report.learningDays} 天',
              style: Design.caption,
            ),
            const SizedBox(height: 28),
            DetailRow(
              title: '学习报告',
              subtitle: '周报 · 月报 · 年报',
              icon: CupertinoIcons.chart_bar,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => ReportsPage(model: model)),
              ),
            ),
            DetailRow(
              title: '备份与恢复',
              subtitle: '导出或恢复本机学习档案',
              icon: CupertinoIcons.archivebox,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => BackupPage(model: model)),
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
          ],
        ),
      ),
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.model});
  final AppModel model;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool busy = false;
  BackupService get backup =>
      BackupService(widget.model.store, profileId: 'local-profile');
  Future<void> export() async {
    setState(() => busy = true);
    try {
      final root = await getTemporaryDirectory();
      final file = File(
        '${root.path}/recitation-backup-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(backup.export(), flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: '背诵计划学习档案',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
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
          const SizedBox(height: Design.gap),
          const Text(
            '档案包含文章、计划、成绩和复习记录，不包含录音。可通过系统分享保存到文件。',
            style: Design.caption,
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
