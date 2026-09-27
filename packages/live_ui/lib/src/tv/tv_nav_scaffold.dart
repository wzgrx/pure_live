import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/adaptive_scaffold.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/tv/tv_scope.dart';

/// The app shell in TV mode (spec/design/principles.md §5.3, §6.3): a rail
/// on the left that shows icons only and expands with labels while it has
/// focus, over the page rather than pushing it.
///
/// Remote paths: right from the rail enters the page at the card that had
/// focus last on that destination (else the first control below the app
/// bar); left from the page's left edge returns to the rail; OK on a rail
/// item opens it. Back on a top-level page first moves focus to the rail;
/// back on the rail leaves the app without asking.
class TvNavScaffold extends StatefulWidget {
  /// Creates the shell.
  const new({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    super.key,
  });

  /// Destinations in order, the same as on phones.
  final List<NavDestination> destinations;

  /// Selected destination.
  final int selectedIndex;

  /// Called with the chosen destination.
  final ValueChanged<int> onSelected;

  /// Page content.
  final Widget body;

  @override
  State<TvNavScaffold> createState() => TvNavScaffoldState();
}

/// State of a [TvNavScaffold]; public for tests.
class TvNavScaffoldState extends State<TvNavScaffold> {
  final FocusScopeNode _rail = FocusScopeNode(debugLabel: 'tv-rail');
  final FocusScopeNode _content = FocusScopeNode(debugLabel: 'tv-content');
  late List<FocusNode> _items = _createItems();
  final Map<int, FocusNode> _memory = {};
  bool _railFocused = false;

  /// A destination was chosen on the rail: focus goes into its page.
  bool _selecting = false;

  /// Whether the rail has focus (and is expanded).
  bool get railFocused => _railFocused;

  List<FocusNode> _createItems() => [
    for (var i = 0; i < widget.destinations.length; i++) FocusNode(debugLabel: 'tv-rail-$i'),
  ];

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    // Start on the rail's selected item: the remote needs a first focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || !_isInside(primary, _content)) focusRail();
    });
  }

  @override
  void didUpdateWidget(TvNavScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      final old = _items;
      _items = _createItems();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in old) {
          node.dispose();
        }
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    for (final node in _items) {
      node.dispose();
    }
    _rail.dispose();
    _content.dispose();
    super.dispose();
  }

  static bool _isInside(FocusNode node, FocusNode scope) => node == scope || node.ancestors.contains(scope);

  void _onFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    final wasRail = _railFocused;
    final inContent = primary != _content && _isInside(primary, _content);
    if (inContent && primary is! FocusScopeNode) {
      _memory[widget.selectedIndex] = primary;
      _selecting = false;
    }
    final inRail = _isInside(primary, _rail);
    if (inRail != _railFocused && mounted) setState(() => _railFocused = inRail);
    // A page that appears asks its navigator's scope for focus, which parks
    // focus on a scope with nothing inside (the start, a new destination, a
    // pushed page): a remote would then have nothing visible to move. Put it
    // back on the rail when it was there, else on the page.
    final parked = primary is FocusScopeNode && (_isInside(primary, _content) || _rail.ancestors.contains(primary));
    if (parked) {
      final toRail = wasRail && !_selecting;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || FocusManager.instance.primaryFocus != primary) return;
        if (toRail) {
          focusRail();
        } else {
          focusContent();
        }
      });
    }
  }

  /// Moves focus to the selected rail item.
  void focusRail() {
    if (_items.isEmpty) return;
    _items[widget.selectedIndex.clamp(0, _items.length - 1)].requestFocus();
  }

  /// Moves focus into the page: back to the node that had it last on this
  /// destination, else the first one in reading order below the app bar.
  void focusContent() {
    final remembered = _memory[widget.selectedIndex];
    if (remembered != null && remembered.context != null && remembered.canRequestFocus && _onCurrentPage(remembered)) {
      remembered.requestFocus();
      return;
    }
    _firstInContent()?.requestFocus();
  }

  /// Nodes on pages covered by another page (a pushed route) are skipped.
  bool _onCurrentPage(FocusNode node) {
    for (final ancestor in node.ancestors) {
      if (ancestor == _content) return true;
      if (ancestor is FocusScopeNode && ancestor.skipTraversal) return false;
    }
    return false;
  }

  FocusNode? _firstInContent() {
    final candidates = [
      for (final node in _content.traversalDescendants)
        if (node is! FocusScopeNode && node.context != null && _onCurrentPage(node)) node,
    ];
    if (candidates.isEmpty) return null;
    bool inAppBar(FocusNode node) => node.context!.findAncestorWidgetOfExactType<AppBar>() != null;
    final body = candidates.where((node) => !inAppBar(node)).toList();
    final pool = (body.isEmpty ? candidates : body)
      ..sort((a, b) {
        final dy = a.rect.top.round().compareTo(b.rect.top.round());
        return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
      });
    return pool.first;
  }

  KeyEventResult _onRailKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      focusContent();
      return KeyEventResult.handled;
    }
    // Nothing lies left of the rail.
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  /// Left arrows the page could not use (its left edge) go to the rail. Text
  /// fields keep theirs, and dialogs and sheets keep focus inside.
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    final context = primary?.context;
    if (primary == null || context == null || !_isInside(primary, _content)) return KeyEventResult.ignored;
    if (context.findAncestorStateOfType<EditableTextState>() != null) return KeyEventResult.ignored;
    if (ModalRoute.of(context) is PopupRoute) return KeyEventResult.ignored;
    if (primary.focusInDirection(TraversalDirection.left)) return KeyEventResult.handled;
    focusRail();
    return KeyEventResult.handled;
  }

  void _select(int index) {
    _selecting = true;
    widget.onSelected(index);
    // The page of a new destination builds in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusContent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = _railFocused ? TvMetrics.safeX + TvMetrics.railExpandedItems : TvMetrics.railWidth;
    return PopScope(
      // principles §6.3: back on a top-level page goes to the rail first.
      canPop: _railFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) focusRail();
      },
      child: ColoredBox(
        color: scheme.surface,
        child: Stack(
          children: [
            Positioned.fill(
              left: TvMetrics.railWidth,
              child: FocusScope(
                node: _content,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onContentKey,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    // The right overscan margin; top and bottom stay with the
                    // pages' app bars and lists.
                    child: SafeArea(left: false, top: false, bottom: false, child: widget.body),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: still ? Duration.zero : Motion.medium,
                curve: Curves.easeOutCubic,
                width: width,
                decoration: BoxDecoration(
                  color: _railFocused ? scheme.surfaceContainer : scheme.surface,
                  boxShadow: _railFocused
                      ? const [BoxShadow(color: Color(0x4D000000), offset: Offset(1, 0), blurRadius: 3)]
                      : null,
                ),
                child: FocusScope(
                  node: _rail,
                  onKeyEvent: _onRailKey,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(TvMetrics.safeX, TvMetrics.safeY, Space.s3, TvMetrics.safeY),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: Space.s8),
                        for (var i = 0; i < widget.destinations.length; i++)
                          _RailItem(
                            destination: widget.destinations[i],
                            selected: i == widget.selectedIndex,
                            expanded: _railFocused,
                            focusNode: _items[i],
                            onSelect: () => _select(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const new({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.focusNode,
    required this.onSelect,
  });

  final NavDestination destination;
  final bool selected;
  final bool expanded;
  final FocusNode focusNode;
  final VoidCallback onSelect;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Buttons show focus by their fill (principles §5.3): near-white under
    // focus, the selection indicator otherwise.
    final background = _focused
        ? scheme.onSurface
        : widget.selected
        ? scheme.secondaryContainer
        : Colors.transparent;
    final foreground = _focused
        ? scheme.surface
        : widget.selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final d = widget.destination;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: d.label,
      excludeSemantics: true,
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelect();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: GestureDetector(
            onTap: widget.onSelect,
            child: Container(
              height: Sizes.targetTouch,
              margin: const EdgeInsets.symmetric(vertical: Space.s1),
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.full)),
              // The label joins once the expanding rail has room for it.
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Icon(widget.selected ? d.selectedIcon : d.icon, color: foreground, size: Sizes.iconMd),
                    if (widget.expanded && constraints.maxWidth >= Sizes.iconMd + Space.s3 + Sizes.iconLg) ...[
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: Text(
                          d.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelLarge!.copyWith(color: foreground),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
