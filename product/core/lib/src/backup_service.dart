import 'archive.dart';
import 'codec.dart';
import 'memory_store.dart';
import 'ports.dart';

class RestorePreview {
  const RestorePreview(
      {required this.added, required this.duplicates, required this.conflicts});
  final int added;
  final int duplicates;
  final List<String> conflicts;
  bool get canMerge => conflicts.isEmpty;
}

class BackupService {
  BackupService(this.store,
      {required this.profileId, this.timeZone = 'Asia/Shanghai'});
  final MemoryRecitationStore store;
  final String profileId;
  final String timeZone;

  /// Portable structured data only. Local audio paths are never exported.
  String export({DateTime? at}) {
    final state = store.snapshot();
    final tables = <String, List<Map<String, Object?>>>{};
    for (final name in MemoryRecitationStore.tables) {
      tables[name] = (state[name] as Map)
          .values
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();
    }
    for (final a in tables['attempts']!) {
      a['audioPath'] = null;
    }
    return ArchiveBundle(
      manifest: ArchiveManifest(
          formatVersion: 1,
          profileId: profileId,
          exportedAt: (at ?? DateTime.now()).toUtc(),
          timeZone: timeZone,
          includesAudio: false,
          counts: tables.map((k, v) => MapEntry(k, v.length))),
      entities: tables,
    ).encode();
  }

  RestorePreview preview(String text) {
    final bundle = _read(text);
    final current = store.snapshot();
    var added = 0;
    var duplicates = 0;
    final conflicts = <String>[];
    for (final table in bundle.entities.entries) {
      for (final value in table.value) {
        final id = value['id'] as String;
        final old = (current[table.key] as Map)[id];
        if (old == null) {
          added++;
        } else {
          final portable = Map<String, Object?>.from(old as Map);
          if (table.key == 'attempts') portable['audioPath'] = null;
          if (canonicalJson(portable) == canonicalJson(value)) {
            duplicates++;
          } else {
            conflicts.add('${table.key}/$id');
          }
        }
      }
    }
    return RestorePreview(
        added: added, duplicates: duplicates, conflicts: conflicts);
  }

  /// Only merges additions and identical entities; conflicting versions need a
  /// user-selected resolution. Backup callback must finish before any mutation.
  Future<RestorePreview> restore(String text,
      {required Future<void> Function(String) saveCurrentArchive}) async {
    final result = preview(text);
    if (!result.canMerge) throw StateError('存在冲突记录，请先选择恢复方式');
    final bundle = _read(text);
    final current = store.snapshot();
    for (final table in bundle.entities.entries) {
      for (final e in table.value) {
        (current[table.key] as Map).putIfAbsent(e['id'], () => e);
      }
    }
    _validateReferences(current);
    await saveCurrentArchive(export());
    await store.writeBatch(_batch(bundle));
    return result;
  }

  /// Exact rollback is explicit and distinct from the normal conflict-safe merge.
  Map<String, dynamic> snapshotState(String text) {
    final bundle = _read(text);
    if (bundle.entities.keys.toSet().length !=
            MemoryRecitationStore.tables.length ||
        MemoryRecitationStore.tables
            .any((t) => !bundle.entities.containsKey(t))) {
      throw const FormatException('快照不完整，不能恢复');
    }
    final state = MemoryRecitationStore.emptyState();
    for (final table in bundle.entities.entries) {
      for (final row in table.value) {
        (state[table.key] as Map)[row['id']] = row;
      }
    }
    _validateReferences(state);
    return state;
  }

  Future<void> restoreSnapshot(String text,
      {required Map<String, dynamic> expected,
      required Future<void> Function(String) saveCurrentArchive}) async {
    final state = snapshotState(text);
    await store.replaceSnapshot(state, expected: expected,
        saveCurrent: (current) async {
      final stable = MemoryRecitationStore(initial: current);
      await saveCurrentArchive(
          BackupService(stable, profileId: profileId, timeZone: timeZone)
              .export());
    });
  }

  ArchiveBundle _read(String text) {
    final bundle = ArchiveBundle.decode(text);
    if (bundle.manifest.includesAudio ||
        bundle.entities.keys
            .toSet()
            .difference(MemoryRecitationStore.tables.toSet())
            .isNotEmpty) {
      throw const FormatException('当前版本只支持结构化学习档案');
    }
    // Decode all entities before writing anything to the store.
    try {
      _batch(bundle);
    } catch (_) {
      throw const FormatException('实体数据格式无效');
    }
    return bundle;
  }

  RecitationBatch _batch(ArchiveBundle bundle) {
    final e = bundle.entities;
    List<T> read<T>(String table, T Function(JsonObject) decoder) =>
        (e[table] ?? [])
            .map((j) => decoder(Map<String, dynamic>.from(j)))
            .toList();
    return RecitationBatch(
      articles: read('articles', EntityCodec.readArticle),
      versions: read('versions', EntityCodec.readVersion),
      plans: read('plans', EntityCodec.readPlan),
      tasks: read('tasks', EntityCodec.readTask),
      attempts: read('attempts', EntityCodec.readAttempt),
      events: read('events', EntityCodec.readEvent),
    );
  }

  void _validateReferences(Map<String, dynamic> state) {
    final articles = state['articles'] as Map;
    final versions = state['versions'] as Map;
    final plans = state['plans'] as Map;
    final tasks = state['tasks'] as Map;
    final segments = <String>{};
    for (final v in versions.values) {
      if (!articles.containsKey(v['articleId']))
        throw const FormatException('文章版本缺少所属文章');
      for (final s in v['segments']) {
        if (s['versionId'] != v['id'] || !segments.add(s['id']))
          throw const FormatException('段落版本引用无效');
      }
    }
    for (final a in articles.values) {
      if (versions[a['currentVersionId']]?['articleId'] != a['id'])
        throw const FormatException('文章缺少原文版本');
    }
    for (final p in plans.values) {
      if ((p['segmentIds'] as List).any((s) => !segments.contains(s)))
        throw const FormatException('计划缺少对应段落');
    }
    for (final t in tasks.values) {
      if (!plans.containsKey(t['planId']) ||
          !(plans[t['planId']]['segmentIds'] as List).contains(t['segmentId']))
        throw const FormatException('任务引用无效');
    }
    for (final a in (state['attempts'] as Map).values) {
      if (tasks[a['taskId']]?['segmentId'] != a['segmentId'])
        throw const FormatException('考核缺少对应任务');
    }
    final events = state['events'] as Map;
    final attempts = state['attempts'] as Map;
    for (final e in events.values) {
      if (e['taskId'] != null && !tasks.containsKey(e['taskId']))
        throw const FormatException('历史事件缺少对应任务');
      if (e['segmentId'] != null && !segments.contains(e['segmentId']))
        throw const FormatException('历史事件缺少对应段落');
      if (e['attemptId'] != null && !attempts.containsKey(e['attemptId']))
        throw const FormatException('历史事件缺少对应考核');
      if (e['undoOf'] != null) {
        final original = events[e['undoOf']];
        if (original == null ||
            original['type'] != 'taskRescheduled' ||
            original['taskId'] != e['taskId'] ||
            original['undoOf'] != null) throw const FormatException('撤销事件引用无效');
      }
    }
  }
}
