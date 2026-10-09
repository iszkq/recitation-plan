import 'dart:io';
import 'archive.dart';
import 'backup_service.dart';
import 'memory_store.dart';
import 'recitation_service.dart';

enum LocalSnapshotKind { recent, daily, checkpoint, restore }

class LocalSnapshot {
  const LocalSnapshot(
      {required this.id,
      required this.kind,
      required this.createdAt,
      required this.counts,
      required this.valid});
  final String id;
  final LocalSnapshotKind kind;
  final DateTime createdAt;
  final Map<String, int> counts;
  final bool valid;
}

/// Device-local rollback copies. Portable external export remains necessary.
class LocalSnapshotRepository {
  LocalSnapshotRepository(String path, {DateTime Function()? clock})
      : directory = Directory(path).absolute,
        clock = clock ?? DateTime.now;
  final Directory directory;
  final DateTime Function() clock;
  static const limits = {
    LocalSnapshotKind.recent: 12,
    LocalSnapshotKind.daily: 14,
    LocalSnapshotKind.checkpoint: 5,
    LocalSnapshotKind.restore: 5
  };
  static final _name =
      RegExp(r'^(recent|daily|checkpoint|restore)-[0-9a-f-]+\.json$');
  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return operation;
  }

  File _file(String id) {
    if (!_name.hasMatch(id)) throw const FormatException('快照名称无效');
    return File('${directory.path}/$id');
  }

  Future<List<LocalSnapshot>> list() async {
    if (!await directory.exists()) return [];
    final result = <LocalSnapshot>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final id = entity.uri.pathSegments.last;
      if (!_name.hasMatch(id)) continue;
      final kind = LocalSnapshotKind.values.byName(id.split('-').first);
      try {
        final text = await entity.readAsString();
        final bundle = ArchiveBundle.decode(text);
        BackupService(MemoryRecitationStore(), profileId: 'validation')
            .snapshotState(text);
        result.add(LocalSnapshot(
            id: id,
            kind: kind,
            createdAt: bundle.manifest.exportedAt,
            counts: Map.unmodifiable(bundle.manifest.counts),
            valid: true));
      } catch (_) {
        result.add(LocalSnapshot(
            id: id,
            kind: kind,
            createdAt: (await entity.stat()).modified.toUtc(),
            counts: const {},
            valid: false));
      }
    }
    result.sort((a, b) {
      final time = b.createdAt.compareTo(a.createdAt);
      return time != 0 ? time : b.id.compareTo(a.id);
    });
    return result;
  }

  Future<String> read(String id) async {
    final file = _file(id);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) throw StateError('快照文件不可用');
    final text = await file.readAsString();
    BackupService(MemoryRecitationStore(), profileId: 'validation')
        .snapshotState(text);
    return text;
  }

  Future<void> captureBeforeWrite(Map<String, dynamic> state) =>
      _serialized(() async {
        if (MemoryRecitationStore.tables
            .every((t) => (state[t] as Map).isEmpty)) return;
        final now = clock().toUtc();
        final backup = BackupService(MemoryRecitationStore(initial: state),
            profileId: 'local-profile');
        final text = backup.export(at: now);
        final local = localTime(now, 'Asia/Shanghai');
        final date =
            '${local.year.toString().padLeft(4, '0')}${local.month.toString().padLeft(2, '0')}${local.day.toString().padLeft(2, '0')}';
        final daily = _file('daily-$date.json');
        if (!await daily.exists()) await _write(daily, text);
        await _write(_file(_id(LocalSnapshotKind.recent, now)), text);
        await _prune();
      });

  Future<void> save(String text,
          {LocalSnapshotKind kind = LocalSnapshotKind.checkpoint}) =>
      _serialized(() async {
        BackupService(MemoryRecitationStore(), profileId: 'validation')
            .snapshotState(text);
        await _write(_file(_id(kind, clock().toUtc())), text);
        await _prune();
      });

  String _id(LocalSnapshotKind kind, DateTime now) =>
      '${kind.name}-${now.microsecondsSinceEpoch}-${createLocalId()}.json';
  Future<void> _write(File file, String text) async {
    await directory.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _prune() async {
    final snapshots = await list();
    for (final kind in LocalSnapshotKind.values) {
      final own = snapshots.where((s) => s.kind == kind && s.valid).toList();
      for (final item in own.skip(limits[kind]!)) {
        await _file(item.id).delete();
      }
    }
  }
}
