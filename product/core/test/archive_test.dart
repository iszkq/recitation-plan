import 'package:recitation_core/recitation_core.dart';
import 'package:test/test.dart';

void main() {
  test('档案可编码、解码并保留版本信息', () {
    final bundle = ArchiveBundle(
      manifest: ArchiveManifest(
        formatVersion: 1,
        profileId: 'local-profile-1',
        exportedAt: DateTime.utc(2026, 10, 8),
        timeZone: 'Asia/Shanghai',
        includesAudio: false,
        counts: const {'articles': 1},
      ),
      entities: const {
        'articles': [
          {'id': 'a1', 'title': '劝学'},
        ],
      },
    );
    final restored = ArchiveBundle.decode(bundle.encode());
    expect(restored.manifest.formatVersion, 1);
    expect(restored.manifest.profileId, 'local-profile-1');
    expect(restored.manifest.includesAudio, isFalse);
    expect(restored.entities['articles']!.single['title'], '劝学');
  });

  test('无效档案不会静默恢复', () {
    expect(
        () => ArchiveBundle.decode('{"entities":[]}'), throwsFormatException);
  });
}
