import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app_model.dart';
import 'design.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.model});
  final AppModel model;
  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  bool busy = false;
  Future<void> changeGoal(int days) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.model.savePreferences(weeklyGoalDays: days);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        await showError(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final growth = model.growth;
      final goal = model.preferences.weeklyGoalDays;
      final badges = [
        (
          name: '初次掌握',
          detail: '无辅助自动通过1节新背',
          earned: growth.masteredSegments >= 1,
        ),
        (name: '三日相伴', detail: '曾连续学习3天', earned: growth.longestStreak >= 3),
        (name: '一周坚持', detail: '曾连续学习7天', earned: growth.longestStreak >= 7),
        (
          name: '温故知新',
          detail: '无辅助自动通过10次复习',
          earned: growth.reviewPasses >= 10,
        ),
        (
          name: '积少成多',
          detail: '无辅助自动掌握20节',
          earned: growth.masteredSegments >= 20,
        ),
      ];
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('学习花园')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Design.inset),
            children: [
              const Text('让记忆慢慢生长', style: Design.display),
              const SizedBox(height: Design.gap),
              CardSection(
                child: Column(
                  children: [
                    Semantics(
                      label: '记忆小芽，${LearningGrowth.stages[growth.stage].name}',
                      child: CustomPaint(
                        size: const Size.square(Design.growthIllustrationSize),
                        painter: _PlantPainter(growth.stage),
                      ),
                    ),
                    Text(
                      LearningGrowth.stages[growth.stage].name,
                      style: Design.heading,
                    ),
                    Text('累计学习 ${growth.totalDays} 天', style: Design.caption),
                    Text(
                      growth.nextStageDays == null
                          ? '已经繁花成荫，继续照顾你的记忆。'
                          : '再学习 ${growth.nextStageDays! - growth.totalDays} 天，解锁下一阶段。',
                      style: Design.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Design.gap),
              Text(
                '连续学习 ${growth.currentStreak} 天 · 最长 ${growth.longestStreak} 天',
                style: Design.heading,
              ),
              Text(
                growth.days.contains(model.today)
                    ? '今天的小芽已经浇过水了。'
                    : growth.currentStreak > 0
                    ? '今天还没学习，完成一次练习或考核就能续上。'
                    : '从今天开始照顾小芽，休息后也可以重新出发。',
                style: Design.caption,
              ),
              const SizedBox(height: Design.sectionGap),
              const Text('本周小目标', style: Design.heading),
              Text(
                '${growth.weekDays} / $goal 天${growth.weekDays >= goal ? ' · 已达成' : ''}',
              ),
              const SizedBox(height: Design.smallGap),
              ProgressBar(value: growth.weekDays / goal, color: Design.success),
              Row(
                children: [
                  CupertinoButton(
                    onPressed: busy || goal <= 1
                        ? null
                        : () => changeGoal(goal - 1),
                    child: const Text('减少'),
                  ),
                  Expanded(
                    child: Text('每周 $goal 天', textAlign: TextAlign.center),
                  ),
                  CupertinoButton(
                    onPressed: busy || goal >= 7
                        ? null
                        : () => changeGoal(goal + 1),
                    child: const Text('增加'),
                  ),
                ],
              ),
              if (busy) const CupertinoActivityIndicator(),
              Wrap(
                spacing: Design.smallGap,
                runSpacing: Design.smallGap,
                children: [
                  for (var i = 0; i < 7; i++) _weekDay(model, growth, i),
                ],
              ),
              const SizedBox(height: Design.sectionGap),
              const Text('成长徽章', style: Design.heading),
              for (final badge in badges)
                DetailRow(
                  inset: false,
                  title: '${badge.name} · ${badge.earned ? '已获得' : '待解锁'}',
                  subtitle: badge.detail,
                  subtitleMaxLines: null,
                  done: badge.earned,
                  icon: CupertinoIcons.rosette,
                ),
              const SizedBox(height: Design.gap),
              const Text(
                '有效练习时长或已保存的自动通过都会浇水，同一天只计一次；辅助练习可养成习惯，掌握和复习徽章只认无辅助自动通过。延期、改期、打开页面和技术失败不增加成长。休息不会让小芽退级。',
                style: Design.caption,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _weekDay(AppModel model, LearningGrowth growth, int i) {
    final date = DateTime(
      model.today.year,
      model.today.month,
      model.today.day - model.today.weekday + 1 + i,
    );
    final learned = growth.days.contains(date);
    final future = date.isAfter(model.today);
    final label = '星期${['一', '二', '三', '四', '五', '六', '日'][i]}';
    return Semantics(
      label:
          '$label，${learned
              ? '已学习'
              : future
              ? '尚未到来'
              : '未学习'}',
      child: StatusChip(
        '$label ${learned ? '✓' : '·'}',
        color: learned ? Design.success : Design.secondary,
        background: learned ? Design.successSoft : Design.grouped,
      ),
    );
  }
}

class _PlantPainter extends CustomPainter {
  const _PlantPainter(this.stage);
  final int stage;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width;
    final soil = Paint()..color = Design.accentSoft;
    canvas.drawOval(
      Rect.fromLTWH(scale * .15, scale * .82, scale * .7, scale * .12),
      soil,
    );
    final green = Paint()..color = Design.success;
    if (stage == 0) {
      canvas.drawOval(
        Rect.fromLTWH(scale * .45, scale * .72, scale * .1, scale * .12),
        green,
      );
      return;
    }
    final top =
        scale *
        (stage >= 4
            ? .23
            : stage >= 2
            ? .32
            : .52);
    final stem = Paint()
      ..color = Design.success
      ..strokeWidth = scale * .035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(scale * .5, scale * .86),
      Offset(scale * .5, top),
      stem,
    );
    for (var i = 0; i < math.min(stage + 1, 5); i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final y = scale * (.73 - i * .085);
      final leaf = Path()
        ..moveTo(scale * .5, y)
        ..quadraticBezierTo(
          scale * (.5 + side * .03),
          y - scale * .18,
          scale * (.5 + side * .24),
          y - scale * .13,
        )
        ..quadraticBezierTo(
          scale * (.5 + side * .2),
          y + scale * .05,
          scale * .5,
          y,
        );
      canvas.drawPath(leaf, green);
    }
    if (stage >= 3) {
      final petals = Paint()..color = Design.accent;
      if (stage == 3) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(scale * .5, top),
            width: scale * .12,
            height: scale * .18,
          ),
          petals,
        );
      } else {
        for (var i = 0; i < 5; i++) {
          final angle = i * math.pi * 2 / 5;
          canvas.drawCircle(
            Offset(
              scale * .5 + math.cos(angle) * scale * .09,
              top + math.sin(angle) * scale * .09,
            ),
            scale * .07,
            petals,
          );
        }
        canvas.drawCircle(
          Offset(scale * .5, top),
          scale * .045,
          Paint()..color = Design.panel,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PlantPainter oldDelegate) => oldDelegate.stage != stage;
}
