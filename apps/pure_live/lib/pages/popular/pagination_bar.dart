import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The desktop page bar (3.x `DesktopPaginationBar`): refresh, previous,
/// page numbers, next, rooms per page and "go to page".
class PopularPaginationBar extends StatefulWidget {
  /// Creates the bar.
  const new({
    required this.page,
    required this.lastPage,
    required this.canNext,
    required this.busy,
    required this.pageSize,
    required this.pageSizes,
    required this.showGoto,
    required this.onPage,
    required this.onPageSize,
    required this.onRefresh,
    super.key,
  });

  /// The page shown.
  final int page;

  /// The last page once the platform said there are no more; null while
  /// unknown.
  final int? lastPage;

  /// Whether a next page exists or may exist.
  final bool canNext;

  /// A request is running.
  final bool busy;

  /// Rooms per page.
  final int pageSize;

  /// The page-size choices; null hides the selector (setting).
  final List<int>? pageSizes;

  /// Shows "go to page" (setting `page_show_goto_button`, which 3.x
  /// stored but never read).
  final bool showGoto;

  /// Go to a page.
  final ValueChanged<int> onPage;

  /// Pick rooms per page.
  final ValueChanged<int> onPageSize;

  /// Refresh.
  final VoidCallback onRefresh;

  @override
  State<PopularPaginationBar> createState() => _PopularPaginationBarState();
}

class _PopularPaginationBarState extends State<PopularPaginationBar> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _jump() {
    final target = int.tryParse(_input.text.trim());
    if (target == null || target < 1) return;
    final last = widget.lastPage;
    widget.onPage(last != null && target > last ? last : target);
    _input.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = context.textStyles;
    final current = widget.page;
    final last = widget.lastPage;
    final busy = widget.busy;
    Widget dots() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text('...', style: styles.t13Muted),
    );
    Widget number(int page) {
      final selected = page == current;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          key: ValueKey('popular-page-$page'),
          borderRadius: BorderRadius.circular(6),
          onTap: selected || busy ? null : () => widget.onPage(page),
          child: Container(
            constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              '$page',
              style: selected
                  ? styles.t13Bold.copyWith(color: theme.colorScheme.onPrimary)
                  : styles.t13.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      );
    }

    final pages = <Widget>[number(1)];
    if (current > 3) pages.add(dots());
    var end = current + 1;
    if (last != null && end >= last) end = last - 1;
    for (var page = current - 1 < 2 ? 2 : current - 1; page <= end; page++) {
      if (last == null && !widget.canNext && page > current) break;
      pages.add(number(page));
    }
    if (last != null && last > 1) {
      if (end < last - 1) pages.add(dots());
      pages.add(number(last));
    } else if (last == null && widget.canNext) {
      pages.add(dots());
    }

    final sizes = widget.pageSizes;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('popular-pagination'),
        scrollDirection: Axis.horizontal,
        physics: const PureLiveBoundedScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(i18n('refresh')),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: current > 1 && !busy ? () => widget.onPage(current - 1) : null,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 12),
                  label: Text(i18n('prev_page')),
                ),
                const SizedBox(width: 8),
                ...pages,
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.canNext && !busy ? () => widget.onPage(current + 1) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(i18n('next_page')),
                      const SizedBox(width: 4),
                      if (busy)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                    ],
                  ),
                ),
                if (sizes != null) ...[
                  const SizedBox(width: 24),
                  Text('${i18n('per_page')}: ', style: styles.t13Muted),
                  PopupMenuButton<int>(
                    key: const ValueKey('popular-page-size'),
                    initialValue: widget.pageSize,
                    tooltip: i18n('per_page'),
                    position: PopupMenuPosition.under,
                    onSelected: widget.onPageSize,
                    itemBuilder: (context) => [
                      for (final size in sizes)
                        PopupMenuItem(
                          value: size,
                          child: Text(
                            '$size',
                            style: size == widget.pageSize
                                ? styles.t13Bold.copyWith(color: theme.colorScheme.primary)
                                : styles.t13,
                          ),
                        ),
                    ],
                    child: Container(
                      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.pageSize}', style: styles.t13),
                          Icon(Icons.arrow_drop_down_rounded, size: 18, color: theme.hintColor),
                        ],
                      ),
                    ),
                  ),
                ],
                if (widget.showGoto) ...[
                  const SizedBox(width: 24),
                  Text(i18n('go_to'), style: styles.t13Muted),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 50,
                      child: TextField(
                        key: const ValueKey('popular-goto'),
                        controller: _input,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: styles.t13.copyWith(height: 1.2),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onSubmitted: (_) => _jump(),
                      ),
                    ),
                  ),
                  Text(i18n('page_unit'), style: styles.t13Muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
