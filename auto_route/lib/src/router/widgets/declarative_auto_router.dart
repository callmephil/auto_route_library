part of 'auto_router.dart';

class _DeclarativeAutoRouter extends StatefulWidget {
  const new({
    required this.routesBuilder,
    required this.navigatorObserversBuilder,
    required this.onPopRoute,
    required this.navigatorKey,
    required this.navRestorationScopeId,
    required this.inheritNavigatorObservers,
    required this.onNavigate,
    required this.placeholderBuilder,
    required this.clipBehavior,
    required this.traversalEdgeBehavior,
    required this.heroControllerBuilder,
    super.key,
  });
  final RoutesBuilder routesBuilder;
  final RoutePopCallBack? onPopRoute;
  final NavigatorObserversBuilder navigatorObserversBuilder;
  final String? navRestorationScopeId;
  final bool inheritNavigatorObservers;
  final GlobalKey<NavigatorState>? navigatorKey;
  final OnNestedNavigateCallBack? onNavigate;
  final WidgetBuilder? placeholderBuilder;
  final Clip clipBehavior;
  final TraversalEdgeBehavior? traversalEdgeBehavior;
  final HeroController Function()? heroControllerBuilder;

  @override
  _DeclarativeAutoRouterState createState() => .new();
}

class _DeclarativeAutoRouterState extends State<_DeclarativeAutoRouter>
    with _HeroControllerOwner<_DeclarativeAutoRouter> {
  NestedStackRouter? _controller;

  @override
  HeroController Function()? get _heroControllerBuilder =>
      widget.heroControllerBuilder;

  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;
  late RoutingController _parentController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final parentData = RouteData.of(context);
      final parentScope = RouterScope.of(context);
      _inheritableObserversBuilder = () {
        final observers = widget.navigatorObserversBuilder();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        final inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      _controller = NestedStackRouter(
        parent: _parentController,
        key: parentData.key,
        matchId: parentData.matchId,
        routeData: parentData,
        managedByWidget: true,
        onNavigate: widget.onNavigate,
        navigatorKey: widget.navigatorKey,
        routeCollection: _parentController.routeCollection.subCollectionOf(
          parentData.name,
        ),
      );
      _parentController.attachChildController(_controller!);
      // Before the navigator's first build: the routes callback reads the
      // routes the url names from the handler.
      _controller!.setupInitialRoutes();
      _updateRoutes();
    }
  }

  @override
  void didUpdateWidget(covariant _DeclarativeAutoRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRoutes();
  }

  // The list the routes callback returned last, until a page is popped.
  List<PageRouteInfo>? _routes;

  // A page the navigator popped leaves the stack the router holds, so the
  // list given before no longer describes it: the next list the app gives
  // is applied even if it is the same, and a page it still names shows
  // again, as Flutter's Navigator shows a popped page still in its pages.
  void _didPop(RouteMatch<Object?> route, Page<Object?> page) {
    _routes = null;
    widget.onPopRoute?.call(route, page);
  }

  // Hands the router the app's list when it changed. Done here, before
  // [build] reads the router's state for the scopes, so the widgets that
  // watch the router see the pages the navigator is about to show.
  void _updateRoutes() {
    final routes = widget.routesBuilder(_controller!.pendingRoutesHandler);
    if (const ListEquality<Object?>().equals(routes, _routes)) return;
    _routes = routes;
    _controller!.updateDeclarativeRoutes(routes);
    // Read now: this widget may be gone by the end of the frame.
    final delegate = AutoRouterDelegate.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      delegate.notifyUrlChanged();
    });
  }

  @override
  void dispose() {
    if (_controller != null) {
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null, 'The router controller is not set up yet.');
    final navigator = AutoRouteNavigator(
      router: _controller!,
      clipBehavior: widget.clipBehavior,
      key: GlobalObjectKey(_controller.hashCode),
      navRestorationScopeId: widget.navRestorationScopeId,
      navigatorObservers: _navigatorObservers,
      didPop: _didPop,
      placeholder: widget.placeholderBuilder,
      routeTraversalEdgeBehavior: widget.traversalEdgeBehavior,
    );
    final heroController = _heroController;
    // A pop changes the router's state without a new list: the scopes
    // rebuild with it, and the navigator, which already took the page off,
    // stays as it is.
    return ListenableBuilder(
      listenable: _controller!,
      builder: (_, child) {
        final stateHash = _controller!.stateHash;
        return RouterScope(
          key: _controller!.globalRouterKey,
          controller: _controller!,
          inheritableObserversBuilder: _inheritableObserversBuilder,
          navigatorObservers: _navigatorObservers,
          stateHash: stateHash,
          child: StackRouterScope(
            controller: _controller!,
            stateHash: stateHash,
            child: child!,
          ),
        );
      },
      child: heroController == null
          ? navigator
          : HeroControllerScope(controller: heroController, child: navigator),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<StackRouter>('controller', controller));
  }
}
