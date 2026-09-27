import 'package:drift/drift.dart';
import 'package:live_store/src/database/database.dart';
import 'package:meta/meta.dart';

/// A followed area (store.md §2: identity is platform, namespace and area id).
@immutable
final class FollowedArea {
  /// Creates an area; [platform] is lower-cased and ids are trimmed. Only
  /// missevan keeps a [namespace].
  factory({
    required String platform,
    required String areaId,
    String namespace = '',
    String areaName = '',
    String typeName = '',
    String? areaPic,
    String? shortName,
    int order = 0,
  }) {
    final site = platform.trim().toLowerCase();
    return FollowedArea._(
      platform: site,
      namespace: site == 'missevan' ? namespace.trim().toLowerCase() : '',
      areaId: areaId.trim(),
      areaName: areaName,
      typeName: typeName,
      areaPic: areaPic,
      shortName: shortName,
      order: order,
    );
  }

  const new _({
    required this.platform,
    required this.namespace,
    required this.areaId,
    required this.areaName,
    required this.typeName,
    required this.order,
    this.areaPic,
    this.shortName,
  });

  /// Lower-case platform id.
  final String platform;

  /// Area id namespace (missevan only).
  final String namespace;

  /// Area id.
  final String areaId;

  /// Area display name.
  final String areaName;

  /// Parent category name.
  final String typeName;

  /// Area icon URL.
  final String? areaPic;

  /// Short name.
  final String? shortName;

  /// Custom order, ascending.
  final int order;

  /// Whether the identity is usable (platform and area id not empty).
  bool get isValid => platform.isNotEmpty && areaId.isNotEmpty;

  /// Identity key, `platform|namespace|areaId`.
  String get key => '$platform|$namespace|$areaId';

  @override
  String toString() => 'FollowedArea($key)';
}

/// Followed areas.
final class FollowAreaStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  SimpleSelectStatement<$FollowAreasTable, FollowAreaRow> _ordered() =>
      _db.select(_db.followAreas)
        ..orderBy([(area) => OrderingTerm.asc(area.sortOrder), (area) => OrderingTerm.asc(area.id)]);

  static FollowedArea _model(FollowAreaRow row) => FollowedArea(
    platform: row.platform,
    namespace: row.namespace,
    areaId: row.areaId,
    areaName: row.areaName,
    typeName: row.typeName,
    areaPic: row.areaPic,
    shortName: row.shortName,
    order: row.sortOrder,
  );

  /// Every followed area in order.
  Future<List<FollowedArea>> all() => _ordered().map(_model).get();

  /// Every followed area in order, re-emitted after each change.
  Stream<List<FollowedArea>> watchAll() => _ordered().map(_model).watch();

  /// Follows [area] at the end, or updates its names when already followed.
  Future<void> follow(FollowedArea area) => _db.transaction(() async {
    if (!area.isValid) throw ArgumentError.value(area, 'area', 'Empty platform or area id');
    final existing = await _find(area);
    if (existing != null) {
      await (_db.update(_db.followAreas)..where((row) => row.id.equals(existing.id))).write(
        FollowAreasCompanion(
          areaName: Value(area.areaName),
          typeName: Value(area.typeName),
          areaPic: Value(area.areaPic),
          shortName: Value(area.shortName),
        ),
      );
      return;
    }
    final max = _db.followAreas.sortOrder.max();
    final last = (await (_db.selectOnly(_db.followAreas)..addColumns([max])).getSingle()).read(max);
    await _db.into(_db.followAreas).insert(companion(area, order: last == null ? 0 : last + 1));
  });

  /// Unfollows [area]; returns whether it was followed.
  Future<bool> unfollow(FollowedArea area) async {
    final existing = await _find(area);
    if (existing == null) return false;
    await (_db.delete(_db.followAreas)..where((row) => row.id.equals(existing.id))).go();
    return true;
  }

  /// Whether [area] is followed.
  Future<bool> contains(FollowedArea area) async => await _find(area) != null;

  Future<FollowAreaRow?> _find(FollowedArea area) =>
      (_db.select(_db.followAreas)..where(
            (row) =>
                row.platform.equals(area.platform) &
                row.namespace.equals(area.namespace) &
                row.areaId.equals(area.areaId),
          ))
          .getSingleOrNull();

  /// Insert companion for [area] at [order].
  @internal
  static FollowAreasCompanion companion(FollowedArea area, {required int order}) => FollowAreasCompanion.insert(
    platform: area.platform,
    namespace: Value(area.namespace),
    areaId: area.areaId,
    areaName: Value(area.areaName),
    typeName: Value(area.typeName),
    areaPic: Value(area.areaPic),
    shortName: Value(area.shortName),
    sortOrder: order,
  );
}
