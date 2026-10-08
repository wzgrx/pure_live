import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/areas/area_artwork.dart';

/// The categories and areas of one platform (3.x `AreasListController`).
///
/// Loads once on demand and again on refresh; a failed refresh keeps the
/// areas already shown and reports the error next to them. The selected
/// category is kept by id across refreshes, so a reordered or shrunk
/// catalogue never hides valid areas behind a stale index (3.x).
final class AreaCatalog extends ChangeNotifier {
  /// The catalogue of [site]; loaded pictures teach `pictures`; [precheck]
  /// runs before each request (I03.2 c1: offline).
  new(this.site, {this._pictures, this.precheck});

  /// The platform.
  final LiveSite site;

  /// Runs before the platform is asked; its error is the load's.
  final Future<void> Function()? precheck;

  final AreaPictures? _pictures;
  List<LiveCategory> _categories = const [];
  Object? _error;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;
  int _selected = 0;

  /// Categories in the platform's order.
  List<LiveCategory> get categories => _categories;

  /// The last load's failure, null after a success.
  Object? get error => _error;

  /// Whether a load is running.
  bool get isLoading => _loading != null;

  /// Whether a load has finished (successfully or not).
  bool get hasLoaded => _loaded;

  /// Index of the selected category.
  int get selected => _selected.clamp(0, _categories.isEmpty ? 0 : _categories.length - 1);

  /// Every area of every category, without repeats (the filter searches
  /// these).
  List<LiveArea> get allAreas {
    final seen = <String>{};
    return [
      for (final area in _categories.expand((category) => category.children))
        if (seen.add(area.identityKey ?? '${area.areaType}/${area.areaId}/${area.areaName}')) area,
    ];
  }

  /// Selects category [index].
  void select(int index) {
    if (index < 0 || index >= _categories.length || index == _selected) return;
    _selected = index;
    _notify();
  }

  /// Loads the catalogue unless it has been loaded.
  Future<void> ensureLoaded() => _loaded ? Future.value() : refresh();

  /// Loads the catalogue again; joins a load under way.
  Future<void> refresh() {
    final running = _loading;
    if (running != null) return running;
    final loading = _load().whenComplete(() {
      _loading = null;
      _notify();
    });
    _loading = loading;
    _notify();
    return loading;
  }

  Future<void> _load() async {
    final selectedId = _categories.isEmpty ? null : _categories[selected].id;
    try {
      await precheck?.call();
      // 3.x asked for page 1 of 1000 (one call gives the whole catalogue).
      final categories = await site.getCategories(1, 1000);
      if (_disposed) return;
      _categories = List.unmodifiable(categories);
      final index = categories.indexWhere((category) => category.id == selectedId);
      _selected = index < 0 ? 0 : index;
      _error = null;
      final pictures = _pictures;
      if (pictures != null) await pictures.learn(categories);
    } on Object catch (error) {
      if (_disposed) return;
      _error = error;
    } finally {
      _loaded = true;
    }
  }

  /// Hides the failure over the areas still shown (the error bar's ✕).
  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Areas of [areas] whose name, short name or category matches [keyword]
/// (case ignored; every space-separated word must match).
List<LiveArea> filterAreas(Iterable<LiveArea> areas, String keyword) {
  final words = keyword.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return areas.toList();
  return [
    for (final area in areas)
      if (words.every((word) => '${area.areaName} ${area.shortName} ${area.typeName}'.toLowerCase().contains(word)))
        area,
  ];
}
