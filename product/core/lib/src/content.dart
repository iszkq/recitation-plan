import 'models.dart';
import 'normalization.dart';

class ImportedText {
  const ImportedText(
      {required this.title, required this.segments, this.author});

  final String title;
  final String? author;
  final List<String> segments;
}

/// Creates an import preview without changing any saved article.
/// Empty lines are paragraph boundaries; repeated empty lines are collapsed.
ImportedText previewImportedText(
    {required String title, required String text, String? author}) {
  final cleanTitle = title.trim();
  if (cleanTitle.isEmpty) throw const FormatException('文章标题不能为空');
  final segments = text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) throw const FormatException('正文不能为空');
  if (segments.any((part) => normalizeForAssessment(part).isEmpty)) {
    throw const FormatException('每节需要有效正文，不能只有标点或空白');
  }
  return ImportedText(
      title: cleanTitle,
      author: author?.trim().isEmpty == true ? null : author?.trim(),
      segments: segments);
}

List<String> splitSegmentIntoSentences(String text) {
  final result = <String>[];
  var buffer = StringBuffer();
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    buffer.write(character);
    if ('。！？!?；;'.contains(character)) {
      final sentence = buffer.toString().trim();
      if (sentence.isNotEmpty) result.add(sentence);
      buffer = StringBuffer();
    }
  }
  final remainder = buffer.toString().trim();
  if (remainder.isNotEmpty) result.add(remainder);
  return result;
}

String mergeSegments(Iterable<String> segments) => segments
    .map((segment) => segment.trim())
    .where((segment) => segment.isNotEmpty)
    .join('\n\n');

List<Segment> buildSegments(
    {required String versionId,
    required List<String> texts,
    List<String?> titles = const []}) {
  if (texts.isEmpty) throw const FormatException('至少需要一节正文');
  if (versionId.trim().isEmpty ||
      texts.any((part) => normalizeForAssessment(part).isEmpty)) {
    throw const FormatException('原文版本和每节正文不能为空');
  }
  return [
    for (var i = 0; i < texts.length; i++)
      Segment(
        id: '$versionId:segment:${i + 1}',
        versionId: versionId,
        order: i,
        text: texts[i].trim(),
        title: i < titles.length ? titles[i]?.trim() : null,
      ),
  ];
}
