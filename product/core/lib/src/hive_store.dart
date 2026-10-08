import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'memory_store.dart';

/// One Hive value is the atomic unit for a local learning batch.
/// Uses the public Hive API with a path-specific box name and no adapters.
class HiveRecitationStore extends MemoryRecitationStore {
  HiveRecitationStore._(this._box, Map<String, dynamic>? state)
      : super(initial: state);
  final Box<String> _box;
  bool _closed = false;
  static Future<HiveRecitationStore> open(String path) async {
    final directory = Directory(path).absolute;
    await directory.create(recursive: true);
    final suffix = sha256
        .convert(utf8.encode(directory.path.toLowerCase()))
        .toString()
        .substring(0, 16);
    final name = 'recitation_snapshot_$suffix';
    if (Hive.isBoxOpen(name)) throw StateError('同一档案已打开');
    final box = await Hive.openBox<String>(name, path: directory.path);
    try {
      final text = box.get('state');
      Map<String, dynamic>? state;
      if (text != null) {
        state = Map<String, dynamic>.from(jsonDecode(text) as Map);
        if (state['schemaVersion'] != 1 ||
            MemoryRecitationStore.tables.any((t) => state![t] is! Map)) {
          throw const FormatException('本机档案版本不支持；未清除原有数据');
        }
      }
      return HiveRecitationStore._(box, state);
    } catch (_) {
      await box.close();
      rethrow;
    }
  }

  @override
  Future<void> persist(Map<String, dynamic> next) async {
    if (_closed) throw StateError('本机档案已关闭');
    await _box.put('state', jsonEncode(next));
    await _box.flush();
  }

  @override
  Future<void> close() async {
    await super.close();
    _closed = true;
    await _box.close();
  }
}
