import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  test('标点和空白不影响评分', () {
    final result = alignText('学不可以已。', '学 不可以已！');
    expect(result.accuracy, 100);
    expect(result.coverage, 100);
  });

  test('漏字不会让后续字符全部错位', () {
    final result = alignText('学不可以已', '学可以已');
    expect(result.deleted, 1);
    expect(result.substituted, 0);
    expect(result.accuracy, 80);
  });

  test('多说内容会扣一致率', () {
    final result = alignText('学不可以已', '学不可以已可以');
    expect(result.inserted, 2);
    expect(result.coverage, 100);
    expect(result.accuracy, 60);
  });
}
