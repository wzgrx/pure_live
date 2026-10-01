import 'dart:convert';

import 'package:live_store/live_store.dart';

// The multi-view's last arrangement in `LiveStore.meta` (M13.12) and its
// copy in a full backup (F.5a item 5).

/// The meta key of the last arrangement: layout, "small cells save data",
/// danmaku, and each cell's room (identity and card fields).
const String multiviewSessionKey = 'multiview.session';

/// The stored arrangement, or null when there is none or it cannot be read.
Future<Map<String, Object?>?> readMultiviewSession(MetaStore meta) async {
  final raw = await meta.get(multiviewSessionKey);
  if (raw == null) return null;
  try {
    return multiviewSessionOf(jsonDecode(raw));
  } on FormatException {
    return null;
  }
}

/// Stores [session] as the last arrangement (a backup's, checked with
/// [multiviewSessionOf] first).
Future<void> writeMultiviewSession(MetaStore meta, Map<String, Object?> session) =>
    meta.set(multiviewSessionKey, jsonEncode(session));

/// [value] as an arrangement: a map whose fields have the stored types (the
/// layout a name, the switches booleans, the rooms a list of maps or empty
/// cells); null when it is not one. Unknown fields are dropped.
Map<String, Object?>? multiviewSessionOf(Object? value) {
  if (value is! Map) return null;
  final rooms = value['rooms'];
  if (rooms != null && rooms is! List) return null;
  final layout = value['layout'];
  return {
    if (layout is String) 'layout': layout,
    'smallCellsLowQuality': value['smallCellsLowQuality'] == true,
    'danmaku': value['danmaku'] == true,
    'rooms': [
      for (final room in rooms as List? ?? const [])
        if (room is Map) {for (final MapEntry(:key, :value) in room.entries) '$key': value} else null,
    ],
  };
}
