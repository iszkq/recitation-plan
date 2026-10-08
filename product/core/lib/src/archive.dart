import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Stable JSON for archive checksums and identity comparisons.
String canonicalJson(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(v[k])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

class ArchiveManifest {
  const ArchiveManifest({
    required this.formatVersion,
    required this.profileId,
    required this.exportedAt,
    required this.timeZone,
    required this.includesAudio,
    required this.counts,
  });

  final int formatVersion;
  final String profileId;
  final DateTime exportedAt;
  final String timeZone;
  final bool includesAudio;
  final Map<String, int> counts;

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'profileId': profileId,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'timeZone': timeZone,
        'includesAudio': includesAudio,
        'counts': counts,
      };

  factory ArchiveManifest.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    final profileId = json['profileId'];
    final exportedAt = json['exportedAt'];
    final timeZone = json['timeZone'];
    final counts = json['counts'];
    if (version != 1 ||
        profileId is! String ||
        profileId.trim().isEmpty ||
        exportedAt is! String ||
        timeZone is! String ||
        timeZone.trim().isEmpty ||
        counts is! Map ||
        json['includesAudio'] is! bool ||
        counts.entries.any((e) =>
            e.key is! String || e.value is! int || (e.value as int) < 0)) {
      throw const FormatException('档案清单格式无效');
    }
    return ArchiveManifest(
      formatVersion: version as int,
      profileId: profileId,
      exportedAt: DateTime.parse(exportedAt),
      timeZone: timeZone,
      includesAudio: json['includesAudio'] == true,
      counts: counts.map((key, value) => MapEntry(
          key.toString(), value is int ? value : int.parse(value.toString()))),
    );
  }
}

class ArchiveBundle {
  const ArchiveBundle({required this.manifest, required this.entities});

  final ArchiveManifest manifest;

  /// Versioned entity JSON. Importers merge by stable IDs and never overwrite
  /// an existing article version silently.
  final Map<String, List<Map<String, Object?>>> entities;

  String encode() {
    _validateCounts();
    ArchiveManifest.fromJson(manifest.toJson());
    final payload = <String, Object?>{
      'manifest': manifest.toJson(),
      'entities': entities,
    };
    return jsonEncode({
      ...payload,
      'checksum': sha256.convert(utf8.encode(canonicalJson(payload))).toString()
    });
  }

  void _validateCounts() {
    if (manifest.counts.length != entities.length)
      throw const FormatException('档案数量清单不一致');
    for (final entry in entities.entries) {
      if (manifest.counts[entry.key] != entry.value.length)
        throw const FormatException('档案数量不一致');
      final ids = <String>{};
      for (final entity in entry.value) {
        final id = entity['id'];
        if (id is! String || id.trim().isEmpty || !ids.add(id))
          throw const FormatException('实体ID无效或重复');
      }
    }
  }

  factory ArchiveBundle.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['manifest'] is! Map ||
        decoded['entities'] is! Map) {
      throw const FormatException('背诵档案格式无效');
    }
    final checksum = decoded['checksum'];
    final payload = {
      'manifest': decoded['manifest'],
      'entities': decoded['entities']
    };
    if (checksum is! String ||
        sha256.convert(utf8.encode(canonicalJson(payload))).toString() !=
            checksum) {
      throw const FormatException('档案校验失败，文件可能损坏');
    }
    final rawEntities = decoded['entities'] as Map;
    final entities = <String, List<Map<String, Object?>>>{};
    for (final entry in rawEntities.entries) {
      final list = entry.value;
      if (list is! List) throw const FormatException('档案实体列表无效');
      entities[entry.key.toString()] = list.map((item) {
        if (item is! Map) throw const FormatException('档案实体无效');
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    }
    final bundle = ArchiveBundle(
      manifest: ArchiveManifest.fromJson((decoded['manifest'] as Map)
          .map((key, value) => MapEntry(key.toString(), value))),
      entities: entities,
    );
    bundle._validateCounts();
    return bundle;
  }
}
