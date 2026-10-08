import 'package:flutter/cupertino.dart';

abstract final class Design {
  static const accent = Color(0xFF0066CC);
  static const accentSoft = Color(0xFFEEF5FF);
  static const grouped = Color(0xFFF2F2F7);
  static const line = Color(0xFFE5E5EA);
  static const panel = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C1C1E);
  static const secondary = Color(0xFF636366);
  static const success = Color(0xFF187A48);
  static const error = Color(0xFFB42318);
  static const inset = 24.0;
  static const gap = 16.0;
  static const sectionGap = 24.0;
  static const reading = TextStyle(fontSize: 20, height: 1.8);
  static const caption = TextStyle(fontSize: 14, color: secondary, height: 1.6);
  static const heading = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
  static const theme = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accent,
    scaffoldBackgroundColor: grouped,
    textTheme: CupertinoTextThemeData(
      primaryColor: accent,
      textStyle: TextStyle(
        fontFamily: 'CupertinoSystemText',
        fontSize: 17,
        color: ink,
        height: 1.45,
      ),
    ),
  );
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction(
    this.label, {
    super.key,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Design.gap, bottom: Design.gap / 2),
    child: SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
            : Text(label, textAlign: TextAlign.center),
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = CupertinoIcons.doc_text,
    this.onTap,
    this.done = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: Design.inset, vertical: 6),
    decoration: BoxDecoration(
      color: Design.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Design.line),
    ),
    child: CupertinoListTile(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: done ? const Color(0xFFEDF8F1) : Design.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          done ? CupertinoIcons.checkmark_circle_fill : icon,
          color: done ? Design.success : Design.accent,
          size: 21,
        ),
      ),
      title: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle, maxLines: 3, style: Design.caption),
      ),
      trailing: onTap == null ? null : const CupertinoListTileChevron(),
      onTap: onTap,
    ),
  );
}

class CardSection extends StatelessWidget {
  const CardSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Design.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Design.line),
    ),
    child: child,
  );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = Design.accent,
  });
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 8,
      color: Design.line,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1),
        child: Container(color: color),
      ),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.color = Design.accent,
    this.background = Design.accentSoft,
  });
  final String label;
  final Color color;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onPressed});
  final String title;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Design.inset, 20, Design.inset, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            child: Text(action!),
          ),
      ],
    ),
  );
}

class EmptyContent extends StatelessWidget {
  const EmptyContent(this.title, this.message, {super.key, this.action});
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Design.inset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Design.sectionGap),
        Text(title, style: Design.heading),
        const SizedBox(height: Design.gap),
        Text(message, style: Design.caption),
        ?action,
      ],
    ),
  );
}

String dateLabel(DateTime d) => '${d.year}年${d.month}月${d.day}日';

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showError(BuildContext context, Object error) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('暂时无法完成'),
        content: Text(
          error is FormatException
              ? error.message
              : error is ArgumentError
              ? '${error.message}'
              : error is StateError
              ? error.message
              : '请重试。若仍无法完成，请检查文件权限和设备存储空间。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
