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
  });

  final double accuracy;
  final double coverage;
  final int matched;
  final int deleted;
  final int substituted;
  final int inserted;
}

/// 使用 Levenshtein 动态规划，避免漏一个字后把后续全部判错。
AlignmentResult alignText(String original, String transcript,
    {bool ignorePunctuation = true}) {
  final expected =
      normalizeForAssessment(original, ignorePunctuation: ignorePunctuation)
          .runes
          .toList();
  final actual =
      normalizeForAssessment(transcript, ignorePunctuation: ignorePunctuation)
          .runes
          .toList();
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
      final substitution =
          cost[i - 1][j - 1] + (expected[i - 1] == actual[j - 1] ? 0 : 1);
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
  while (i > 0 || j > 0) {
    if (i > 0 &&
        j > 0 &&
        expected[i - 1] == actual[j - 1] &&
        cost[i][j] == cost[i - 1][j - 1]) {
      matched++;
      i--;
      j--;
    } else if (i > 0 && j > 0 && cost[i][j] == cost[i - 1][j - 1] + 1) {
      substituted++;
      i--;
      j--;
    } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      deleted++;
      i--;
    } else {
      inserted++;
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
  );
}
