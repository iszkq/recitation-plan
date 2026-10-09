import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'memory_store.dart';
import 'local_snapshots.dart';
import 'archive.dart';

/// One Hive value is the atomic unit for a local learning batch.
/// Existing filenames are retained even when iOS relocates the data container.
class HiveRecitationStore extends MemoryRecitationStore {
  HiveRecitationStore._(this._box, this.snapshots, Map<String, dynamic>? state)
      : super(initial: state);
  final Box<String> _box;
  final LocalSnapshotRepository snapshots;
  String? snapshotError;
  bool _closed = false;
  static Future<HiveRecitationStore> open(String path,
      {DateTime Function()? clock}) async {
    final directory = Directory(path).absolute;
    await directory.create(recursive: true);
    final suffix = sha256
        .convert(utf8.encode(directory.path.toLowerCase()))
        .toString()
        .substring(0, 16);
    final existingNames = await directory
        .list()
        .where((entity) => entity is File)
        .map((entity) => entity.uri.pathSegments.last)
        .where((name) =>
            RegExp(r'^recitation_snapshot_[0-9a-f]{16}\.hive$').hasMatch(name))
        .map((name) => name.substring(0, name.length - '.hive'.length))
        .toList();
    if (existingNames.length > 1) {
      throw const FormatException('发现多个本机档案，请先导出并确认恢复方式；原有数据未清除');
    }
    // The path hash names new profiles only; a moved profile keeps its identity.
    final name = existingNames.isEmpty
        ? 'recitation_snapshot_$suffix'
        : existingNames.single;
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
      return HiveRecitationStore._(
          box,
          LocalSnapshotRepository('${directory.path}/snapshots', clock: clock),
          state);
    } catch (_) {
      await box.close();
      rethrow;
    }
  }

  @override
  Future<void> persist(Map<String, dynamic> next) async {
    if (_closed) throw StateError('本机档案已关闭');
    final previous = snapshot();
    if (canonicalJson(previous) != canonicalJson(next)) {
      try {
        await snapshots.captureBeforeWrite(previous);
        snapshotError = null;
      } catch (_) {
        snapshotError = '本机快照保存失败，请检查存储空间并导出档案。学习记录仍会保存。';
      }
    }
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
