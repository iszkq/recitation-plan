import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:recitation_core/recitation_core.dart';

import 'design.dart';

class TextComparison extends StatefulWidget {
  const TextComparison({
    super.key,
    required this.original,
    required this.attempt,
  });
  final String original;
  final Attempt attempt;
  @override
  State<TextComparison> createState() => _TextComparisonState();
}

class _TextComparisonState extends State<TextComparison> {
  bool showRaw = false;
  @override
  Widget build(BuildContext context) {
    final attempt = widget.attempt;
    final raw = attempt.transcript ?? '';
    final voice = attempt.input == AssessmentInput.speech;
    final result = alignText(
      widget.original,
      raw,
      ignorePunctuation: attempt.rule.ignorePunctuation,
      allowHomophones: voice && attempt.acceptHomophones,
    );
    final issues = result.edits
        .where((e) => e.kind != TextEditKind.match)
        .toList();
    final corrections = issues
        .where((e) => e.kind == TextEditKind.homophone)
        .length;
    final corrected = correctedSpeechText(raw, result.edits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('逐字对比', style: Design.heading),
        const SizedBox(height: Design.smallGap),
        Text(
          voice
              ? '红色：错字或漏背；蓝色删除线：多背；绿色下划线：同音校正。识别文字可能有误，可查看原始转录。'
              : '红色：错字或漏字；蓝色删除线：多写。方括号标出缺少内容，未改写你的默写。',
          style: Design.caption,
        ),
        Text(
          attempt.rule.ignorePunctuation
              ? '本次忽略标点和空白；位置按参与评分的字符计数。'
              : '本次标点参与评分，空白忽略；位置按参与评分的字符计数。',
          style: Design.caption,
        ),
        const SizedBox(height: Design.gap),
        LayoutBuilder(
          builder: (context, constraints) {
            final reference = _paragraph(
              '原文',
              widget.original,
              result.edits,
              original: true,
            );
            final answer = _paragraph(
              voice ? '你的背诵（校正后）' : '你的默写',
              raw,
              result.edits,
              original: false,
            );
            return constraints.maxWidth >= Design.comparisonWideWidth
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: reference),
                      const SizedBox(width: Design.gap),
                      Expanded(child: answer),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      reference,
                      const SizedBox(height: Design.gap),
                      answer,
                    ],
                  );
          },
        ),
        const SizedBox(height: Design.gap),
        Text(
          issues.isEmpty
              ? '逐字一致，没有发现错字、漏字或多字。'
              : '错字 ${result.substituted} · ${voice ? '漏背' : '漏字'} ${result.deleted} · ${voice ? '多背' : '多写'} ${result.inserted}${voice ? ' · 同音校正 $corrections' : ''}',
          style: Design.caption,
        ),
        for (final issue in _groups(issues))
          Padding(
            padding: const EdgeInsets.only(top: Design.smallGap),
            child: Text(_description(issue, voice), style: Design.caption),
          ),
        if (voice) ...[
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => showRaw = !showRaw),
            child: Text(showRaw ? '收起原始转录' : '查看原始转录'),
          ),
          if (showRaw) SelectableText('原始转录：$raw', style: Design.reading),
          if (corrections > 0)
            const Text(
              '同音字按原文校正并计入匹配；未补全漏背。此结果是内容校对，不是专业发音评分。',
              style: Design.caption,
            ),
        ],
        // Corrected text is exposed as a full readable sentence for VoiceOver.
        if (voice && corrections > 0)
          Semantics(
            label: '校正后完整内容：$corrected',
            child: const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _paragraph(
    String title,
    String text,
    List<TextEdit> edits, {
    required bool original,
  }) {
    final spans = <TextSpan>[];
    var offset = 0;
    final missing = StringBuffer();
    void flushMissing() {
      if (missing.isEmpty) return;
      spans.add(
        TextSpan(text: '［漏：$missing］', style: _style(TextEditKind.deletion)),
      );
      missing.clear();
    }

    for (final edit in edits) {
      final start = original ? edit.originalOffset : edit.transcriptOffset;
      if (start == null) {
        if (!original && edit.kind == TextEditKind.deletion) {
          missing.write(edit.expected);
        }
        continue;
      }
      if (start > offset) {
        spans.add(TextSpan(text: text.substring(offset, start)));
      }
      flushMissing();
      final value = original ? edit.expected : edit.actual;
      spans.add(
        TextSpan(
          text: !original && edit.kind == TextEditKind.homophone
              ? edit.expected
              : value,
          style: _style(edit.kind, original: original),
        ),
      );
      offset = start + value.length;
    }
    flushMissing();
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    if (spans.isEmpty) spans.add(const TextSpan(text: '（没有有效内容）'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Design.caption),
        const SizedBox(height: Design.smallGap),
        SelectableText.rich(TextSpan(children: spans), style: Design.reading),
      ],
    );
  }

  TextStyle? _style(TextEditKind kind, {bool original = false}) =>
      switch (kind) {
        TextEditKind.match => null,
        TextEditKind.homophone => const TextStyle(
          color: Design.success,
          backgroundColor: Design.successSoft,
          decoration: TextDecoration.underline,
        ),
        TextEditKind.insertion => const TextStyle(
          color: Design.accent,
          backgroundColor: Design.accentSoft,
          decoration: TextDecoration.lineThrough,
        ),
        TextEditKind.substitution || TextEditKind.deletion => TextStyle(
          color: Design.error,
          backgroundColor: Design.errorSoft,
          decoration: original ? TextDecoration.underline : null,
        ),
      };

  List<List<TextEdit>> _groups(List<TextEdit> edits) {
    final groups = <List<TextEdit>>[];
    for (final edit in edits) {
      final last = groups.isEmpty ? null : groups.last.last;
      final adjacent =
          last != null &&
          last.kind == edit.kind &&
          (edit.originalPosition == null ||
              last.originalPosition == edit.originalPosition! - 1) &&
          (edit.transcriptPosition == null ||
              last.transcriptPosition == edit.transcriptPosition! - 1);
      if (adjacent) {
        groups.last.add(edit);
      } else {
        groups.add([edit]);
      }
    }
    return groups;
  }

  String _description(List<TextEdit> edits, bool voice) {
    final first = edits.first;
    final expected = edits.map((e) => e.expected).join();
    final actual = edits.map((e) => e.actual).join();
    final position = first.originalPosition ?? first.transcriptPosition!;
    final location = first.originalPosition == null
        ? '你的内容第$position字'
        : '原文第$position字';
    return switch (first.kind) {
      TextEditKind.substitution =>
        '错字 · $location：应为「$expected」，你${voice ? '背成' : '写成'}「$actual」。',
      TextEditKind.deletion =>
        '${voice ? '漏背' : '漏字'} · $location：缺少「$expected」。',
      TextEditKind.insertion =>
        '${voice ? '多背' : '多写'} · $location：多出「$actual」。',
      TextEditKind.homophone => '同音校正 · $location：「$actual」→「$expected」，计为匹配。',
      TextEditKind.match => '',
    };
  }
}
