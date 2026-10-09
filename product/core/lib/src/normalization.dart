import 'package:lpinyin/lpinyin.dart';

/// 中文背诵评分的文本规范化和对齐算法。
///
/// 规范化只用于评分，不覆盖或修改用户保存的原文。
String normalizeForAssessment(String value, {bool ignorePunctuation = true}) {
  if (!ignorePunctuation)
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(
      RegExp(r'''[，。！？、；："“”‘’（）【】《》〈〉「」『』…—\-·,.!?;:()\[\]{}<>]'''), '');
}

class AlignmentResult {
  const AlignmentResult({
    required this.accuracy,
    required this.coverage,
    required this.matched,
    required this.deleted,
    required this.substituted,
    required this.inserted,
    this.edits = const [],
  });

  final double accuracy;
  final double coverage;
  final int matched;
  final int deleted;
  final int substituted;
  final int inserted;
  final List<TextEdit> edits;
}

enum TextEditKind { match, substitution, deletion, insertion, homophone }

class TextEdit {
  const TextEdit(this.kind,
      {this.expected = '',
      this.actual = '',
      this.originalOffset,
      this.transcriptOffset,
      this.originalPosition,
      this.transcriptPosition});
  final TextEditKind kind;
  final String expected;
  final String actual;
  final int? originalOffset;
  final int? transcriptOffset;
  final int? originalPosition;
  final int? transcriptPosition;
}

class _TextUnit {
  const _TextUnit(this.value, this.raw, this.offset);
  final int value;
  final String raw;
  final int offset;
}

List<_TextUnit> _units(String text, bool ignorePunctuation) {
  final result = <_TextUnit>[];
  var offset = 0;
  for (final rune in text.runes) {
    final raw = String.fromCharCode(rune);
    for (final normalized
        in normalizeForAssessment(raw, ignorePunctuation: ignorePunctuation)
            .runes) {
      result.add(_TextUnit(normalized, raw, offset));
    }
    offset += raw.length;
  }
  return result;
}

/// Ambiguous polyphones and near sounds stay strict. No reference is sent to ASR.
String? _reading(int rune) {
  if (rune < 0x4e00 || rune > 0x9fff) return null;
  final readings = PinyinHelper.convertToPinyinArray(
          String.fromCharCode(rune), PinyinFormat.WITH_TONE_NUMBER)
      .toSet();
  return readings.length == 1 ? readings.single : null;
}

String correctedSpeechText(String transcript, Iterable<TextEdit> edits) {
  final corrections = edits
      .where((e) => e.kind == TextEditKind.homophone)
      .toList()
    ..sort((a, b) => a.transcriptOffset!.compareTo(b.transcriptOffset!));
  final result = StringBuffer();
  var offset = 0;
  for (final edit in corrections) {
    result.write(transcript.substring(offset, edit.transcriptOffset));
    result.write(edit.expected);
    offset = edit.transcriptOffset! + edit.actual.length;
  }
  result.write(transcript.substring(offset));
  return result.toString();
}

/// 使用 Levenshtein 动态规划，避免漏一个字后把后续全部判错。
AlignmentResult alignText(String original, String transcript,
    {bool ignorePunctuation = true, bool allowHomophones = false}) {
  final expected = _units(original, ignorePunctuation);
  final actual = _units(transcript, ignorePunctuation);
  final readings = <int, String?>{};
  bool equivalent(_TextUnit a, _TextUnit b) {
    if (a.value == b.value) return true;
    if (!allowHomophones) return false;
    final first = readings.putIfAbsent(a.value, () => _reading(a.value));
    final second = readings.putIfAbsent(b.value, () => _reading(b.value));
    return first != null && first == second;
  }

  final rows = expected.length + 1;
  final cols = actual.length + 1;
  final cost = List.generate(rows, (_) => List<int>.filled(cols, 0));
  for (var i = 0; i < rows; i++) {
    cost[i][0] = i;
  }
  for (var j = 0; j < cols; j++) {
    cost[0][j] = j;
  }
  for (var i = 1; i < rows; i++) {
    for (var j = 1; j < cols; j++) {
      final substitution = cost[i - 1][j - 1] +
          (equivalent(expected[i - 1], actual[j - 1]) ? 0 : 1);
      cost[i][j] = [cost[i - 1][j] + 1, cost[i][j - 1] + 1, substitution]
          .reduce((a, b) => a < b ? a : b);
    }
  }

  var i = expected.length;
  var j = actual.length;
  var matched = 0;
  var deleted = 0;
  var substituted = 0;
  var inserted = 0;
  final edits = <TextEdit>[];
  void add(TextEditKind kind, {int? originalIndex, int? actualIndex}) {
    final a = originalIndex == null ? null : expected[originalIndex];
    final b = actualIndex == null ? null : actual[actualIndex];
    edits.add(TextEdit(kind,
        expected: a?.raw ?? '',
        actual: b?.raw ?? '',
        originalOffset: a?.offset,
        transcriptOffset: b?.offset,
        originalPosition: originalIndex == null ? null : originalIndex + 1,
        transcriptPosition: actualIndex == null ? null : actualIndex + 1));
  }

  while (i > 0 || j > 0) {
    if (i > 0 &&
        j > 0 &&
        equivalent(expected[i - 1], actual[j - 1]) &&
        cost[i][j] == cost[i - 1][j - 1]) {
      matched++;
      add(
          expected[i - 1].value == actual[j - 1].value
              ? TextEditKind.match
              : TextEditKind.homophone,
          originalIndex: i - 1,
          actualIndex: j - 1);
      i--;
      j--;
    } else if (i > 0 && j > 0 && cost[i][j] == cost[i - 1][j - 1] + 1) {
      substituted++;
      add(TextEditKind.substitution, originalIndex: i - 1, actualIndex: j - 1);
      i--;
      j--;
    } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      deleted++;
      add(TextEditKind.deletion, originalIndex: i - 1);
      i--;
    } else {
      inserted++;
      add(TextEditKind.insertion, actualIndex: j - 1);
      j--;
    }
  }
  final total = expected.length;
  if (total == 0) {
    return const AlignmentResult(
        accuracy: 0,
        coverage: 0,
        matched: 0,
        deleted: 0,
        substituted: 0,
        inserted: 0);
  }
  final accuracy = ((total - substituted - deleted - inserted) / total * 100)
      .clamp(0, 100)
      .toDouble();
  final coverage =
      ((matched + substituted) / total * 100).clamp(0, 100).toDouble();
  return AlignmentResult(
    accuracy: accuracy,
    coverage: coverage,
    matched: matched,
    deleted: deleted,
    substituted: substituted,
    inserted: inserted,
    edits: List.unmodifiable(edits.reversed),
  );
}
