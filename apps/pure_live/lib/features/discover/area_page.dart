import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';

/// Rooms of one area.
class AreaPage extends StatelessWidget {
  const new({required this.platform, required this.area, super.key});

  /// Platform id.
  final String platform;

  /// The area; null when the page was restored without it.
  final Area? area;

  @override
  Widget build(BuildContext context) {
    final area = this.area;
    return Scaffold(
      appBar: AppBar(title: Text(area?.name ?? '')),
      body: area == null
          ? MessageView(title: '分区信息已失效', actionLabel: '返回', onAction: () => context.pop())
          : RoomGrid(query: AreaQuery(platform, area)),
    );
  }
}
