import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  test('导入预览按空行分段并保留正文', () {
    final preview =
        previewImportedText(title: '  劝学  ', text: '第一段。\n\n\n第二段！');
    expect(preview.title, '劝学');
    expect(preview.segments, ['第一段。', '第二段！']);
  });

  test('空正文不能保存', () {
    expect(() => previewImportedText(title: '文章', text: '  \n\n '),
        throwsFormatException);
  });
  test('标点正文和空白小节不能保存', () {
    expect(() => previewImportedText(title: '文章', text: '。。。'),
        throwsFormatException);
    expect(() => buildSegments(versionId: 'v1', texts: ['有效正文', '  ']),
        throwsFormatException);
  });

  test('句子拆分与合并可逆', () {
    final parts = splitSegmentIntoSentences('甲。乙！丙？');
    expect(parts, ['甲。', '乙！', '丙？']);
    expect(mergeSegments(parts), '甲。\n\n乙！\n\n丙？');
  });
}
