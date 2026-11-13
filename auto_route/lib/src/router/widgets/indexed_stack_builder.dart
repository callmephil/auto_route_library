part of 'auto_tabs_router.dart';

class _IndexedStackBuilder extends StatefulWidget {
  const new({
    required this.activeIndex,
    required this.itemBuilder,
    required this.navigatorObservers,
    required this.stack,
    required this.lazyLoad,
    required this.tabsHash,
    super.key,
  });

  final int activeIndex;
  final IndexedWidgetBuilder itemBuilder;
  final bool lazyLoad;
  final List<AutoRoutePage<Object?>> stack;
  final List<NavigatorObserver> navigatorObservers;
  final int tabsHash;

  @override
  _IndexedStackBuilderState createState() => .new();
}

class _IndexedStackBuilderState extends State<_IndexedStackBuilder>
    with _RouteAwareTabsMixin<_IndexedStackBuilder> {
  final _dummyWidget = const SizedBox.shrink();
  final _initializedPagesTracker = <int, bool>{};

  // [previous] is the tab the router leaves, still active as it preloads.
  // Not the active index of the last build: two changes in one frame pass
  // through a tab that was never built as active.
  bool preload(int index, {required int previous}) {
    if (_initializedPagesTracker[index] == true) {
      if (index != previous) {
        _didChangeTabRoute(index, previous);
      }
      return false;
    }
    // A tab not loaded is either lazy and not opened yet, or keeps no state
    // and was dropped while another tab showed: either way it starts anew.
    _didInitTabRoute(index, previous);
    setState(() => _initializedPagesTracker[index] = true);
    return true;
  }

  @override
  List<RouteMatch<Object?>> get routes =>
      widget.stack.map((e) => e.routeData.route).toList();

  @override
  List<NavigatorObserver> get observers => widget.navigatorObservers;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  // Tabs in [kept] were loaded before a routes change and stay loaded; their
  // pages were reported then. [left] is the tab on screen before that change:
  // when another tab shows now, observers hear of it.
  void _setup({
    Set<AutoRoutePage<Object?>> kept = const {},
    TabPageRoute? left,
  }) {
    for (var i = 0; i < widget.stack.length; ++i) {
      final isKept = kept.contains(widget.stack[i]);
      if (left != null && i == widget.activeIndex) {
        _initializedPagesTracker[i] = true;
        _didShowTabAfterListChange(left, i, isBuiltNow: !isKept);
      } else if (isKept) {
        _initializedPagesTracker[i] = true;
      } else if (i == widget.activeIndex ||
          // A tab that keeps no state is built only once it shows, and
          // reported then.
          (!widget.lazyLoad && widget.stack[i].maintainState)) {
        _initializedPagesTracker[i] = true;
        _didInitTabRoute(i);
      } else {
        _initializedPagesTracker[i] = false;
      }
    }
  }

  @override
  void didUpdateWidget(_IndexedStackBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabsHash != oldWidget.tabsHash) {
      final initializedPages = {
        for (final entry in _initializedPagesTracker.entries)
          if (entry.value) ?oldWidget.stack.elementAtOrNull(entry.key),
      };
      final left = oldWidget.stack.elementAtOrNull(oldWidget.activeIndex);
      _initializedPagesTracker.clear();
      _setup(
        kept: initializedPages,
        left: left == null
            ? null
            : TabPageRoute(
                routeInfo: left.routeData.route,
                index: oldWidget.activeIndex,
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: IndexedStack(
        index: widget.activeIndex,
        sizing: .expand,
        children: List.generate(widget.stack.length, (index) {
          if (!widget.stack[index].maintainState &&
              index != widget.activeIndex) {
            _initializedPagesTracker[index] = false;
          }
          final isInitialized = _initializedPagesTracker[index] == true;
          final child = isInitialized
              ? widget.itemBuilder(context, index)
              : _dummyWidget;
          final isInactive = index != widget.activeIndex;

          // Always wrap with ExcludeSemantics and ExcludeFocus but control with
          // excluding property
          return ExcludeSemantics(
            // Keyed by page so a tab kept across a routes change keeps its
            // state
            key: ObjectKey(widget.stack[index]),
            excluding: isInactive,
            child: ExcludeFocus(excluding: isInactive, child: child),
          );
        }),
      ),
    );
  }
}
