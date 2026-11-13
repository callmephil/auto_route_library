part of 'routing_controller.dart';

/// Signature for a function uses `pagesMap` to build an [AutoRoutePage]
typedef PageBuilder = AutoRoutePage<Object?> Function(RouteData<Object?> data);

const ValueKey<String> _kRootKey = ValueKey('%__Root__%');

/// An Implementation of [StackRouter] used by [AutoRouterDelegate]
abstract class RootStackRouter extends StackRouter {
  /// Default constructor
  new({super.navigatorKey}) : super(key: _kRootKey, matchId: _kRootKey) {
    _navigationHistory = NavigationHistory.create(this);
  }

  /// Builds a new instance of [RootStackRouter]
  /// with the provided parameters
  factory build({
    required List<AutoRoute> routes,
    List<AutoRouteGuard> guards,
    GlobalKey<NavigatorState>? navigatorKey,
    RouteType defaultRouteType,
  }) = _RootStackRouterImpl;

  final _rootBackButtonDispatcher = RootBackButtonDispatcher();

  // Counts the links the delegate opened. A navigation a link starts keeps
  // the count it started with, and stops at its next guard once a later link
  // has started: a slow guard of the link the app started at must not open
  // its page over the pages of a link that came after it.
  int _linkCount = 0;

  // The count of the link whose navigation is starting, while it starts.
  int? _startingLink;

  // Holds, in the zone a link's navigation runs in, the count of that link.
  static final _linkZone = Object();

  // What the link counted [_acceptingLink] does once it is let in, until a
  // guarded navigation of that link takes it, see [_takeLinkAcceptedStep].
  VoidCallback? _linkAccepted;
  int? _acceptingLink;

  // Runs [open], which starts the navigation of a new link, as that link's.
  // The navigation starts before [open] returns, up to its first guard, and
  // what it does later, such as navigating the nested router of a page
  // already open or a tabs router, runs in a zone that names the link.
  // [onAccepted] runs once the guards that navigation asks let the link in,
  // so a link the app turns down changes nothing else; when it asks no
  // guard, such as a link to the page already open, once it ends.
  Future<void> _openLink(
    Future<void> Function() open, {
    VoidCallback? onAccepted,
  }) {
    final link = _startingLink = ++_linkCount;
    _linkAccepted = onAccepted;
    _acceptingLink = link;
    final Future<void> navigation;
    try {
      navigation = runZoned(open, zoneValues: {_linkZone: link});
    } finally {
      _startingLink = null;
    }
    if (_acceptingLink == link && _linkAccepted != null) {
      // The navigation's own failure reaches its caller, which awaits it.
      unawaited(
        navigation.then(
          (_) => _takeAcceptedStepOf(link)?.call(),
          onError: (Object _) => null,
        ),
      );
    }
    return navigation;
  }

  // The count of the link whose navigation runs now, or null.
  int? get _currentLink => _startingLink ?? Zone.current[_linkZone] as int?;

  // The step the link whose navigation runs takes once it is let in, for
  // the guarded navigation it starts to run; null for any other navigation
  // and once taken.
  VoidCallback? _takeLinkAcceptedStep() => _takeAcceptedStepOf(_currentLink);

  VoidCallback? _takeAcceptedStepOf(int? link) {
    if (link == null || link != _acceptingLink) return null;
    final step = _linkAccepted;
    _linkAccepted = null;
    return step;
  }

  // Makes [step] the step of the link whose navigation runs now, for the
  // guarded navigation it starts next to take, as when a tab change hands
  // it on to the tab's nested router, after any step that waits already.
  // False when no link's navigation runs, or a later link has started.
  bool _handLinkStepOn(VoidCallback step) {
    final link = _currentLink;
    if (link == null || link != _acceptingLink) return false;
    final waiting = _linkAccepted;
    _linkAccepted = waiting == null
        ? step
        : () {
            waiting();
            step();
          };
    return true;
  }

  // Whether [step] waits for the link whose navigation runs now to be let
  // in, as it does while a guard of that link has yet to answer; it then
  // runs with the link's own step, or not at all if the link is turned down.
  bool _deferToLinkAccepted(VoidCallback step) {
    final linkStep = _linkAccepted;
    if (linkStep == null || _currentLink != _acceptingLink) return false;
    _linkAccepted = () {
      linkStep();
      step();
    };
    return true;
  }

  /// Returns a [RouterConfig] instead to be passed
  /// to [MaterialApp.router]
  RouterConfig<UrlState> config({
    DeepLinkTransformer? deepLinkTransformer,
    DeepLinkBuilder? deepLinkBuilder,
    String? navRestorationScopeId,
    WidgetBuilder? placeholder,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    bool includePrefixMatches = !kIsWeb,
    bool Function(String? location)? neglectWhen,
    bool rebuildStackOnDeepLink = false,
    Listenable? reevaluateListenable,
    Clip clipBehavior = .hardEdge,
  }) {
    return RouterConfig(
      routeInformationParser: defaultRouteParser(
        includePrefixMatches: includePrefixMatches,
        deepLinkTransformer: deepLinkTransformer,
      ),
      routeInformationProvider: routeInfoProvider(neglectWhen: neglectWhen),
      backButtonDispatcher: _rootBackButtonDispatcher,
      routerDelegate: delegate(
        reevaluateListenable: reevaluateListenable,
        rebuildStackOnDeepLink: rebuildStackOnDeepLink,
        navRestorationScopeId: navRestorationScopeId,
        navigatorObservers: navigatorObservers,
        placeholder: placeholder,
        deepLinkBuilder: deepLinkBuilder,
        clipBehavior: clipBehavior,
      ),
    );
  }

  @override
  RouteData<Object?> get routeData => .new(
    router: this,
    type: const RouteType.material(),
    stackKey: _stackKey,
    route: RouteMatch(
      config: DummyRootRoute(path: ''),
      segments: const [''],
      stringMatch: '',
      key: const ValueKey('Root'),
    ),
    pendingChildren: const [],
  );

  /// The list of route entries to match against
  List<AutoRoute> get routes;

  /// A List of Root router guards
  List<AutoRouteGuard> get guards => const [];

  /// The default animation
  RouteType get defaultRouteType => const .material();

  late final NavigationHistory _navigationHistory;

  @override
  bool get managedByWidget => false;

  AutoRouteInformationProvider? _lazyInformationProvider;

  /// Builds a lazy instance of [AutoRouteInformationProvider]
  AutoRouteInformationProvider routeInfoProvider({
    RouteInformation? initialRouteInformation,
    bool Function(String? location)? neglectWhen,
  }) {
    return _lazyInformationProvider ??= AutoRouteInformationProvider(
      initialRouteInformation: initialRouteInformation,
      neglectWhen: neglectWhen,
    );
  }

  AutoRouterDelegate? _lazyRootDelegate;

  /// Builds a lazy instance of [AutoRouterDelegate]
  /// _lazyRootDelegate is only built one time
  AutoRouterDelegate delegate({
    String? navRestorationScopeId,
    WidgetBuilder? placeholder,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    DeepLinkBuilder? deepLinkBuilder,
    bool rebuildStackOnDeepLink = false,
    Listenable? reevaluateListenable,
    Clip clipBehavior = .hardEdge,
  }) {
    return _lazyRootDelegate ??= AutoRouterDelegate(
      this,
      navRestorationScopeId: navRestorationScopeId,
      navigatorObservers: navigatorObservers,
      placeholder: placeholder,
      rebuildStackOnDeepLink: rebuildStackOnDeepLink,
      deepLinkBuilder: deepLinkBuilder,
      reevaluateListenable: reevaluateListenable,
      clipBehavior: clipBehavior,
    );
  }

  /// Builds a lazy instance of [DefaultRouteParser]
  DefaultRouteParser defaultRouteParser({
    bool includePrefixMatches = !kIsWeb,
    DeepLinkTransformer? deepLinkTransformer,
  }) => .new(
    matcher,
    includePrefixMatches: includePrefixMatches,
    // A DeepLinkTransformer returns a Future, and a SynchronousFuture would
    // change timing.
    deepLinkTransformer: deepLinkTransformer ?? Future.value,
  );

  @override
  void updateRouteData(RouteData<Object?> data) {
    throw FlutterError('Root RouteData should not update');
  }

  // Reads routeCollection on every match, so the parsers made before a hot
  // reload match the reloaded routes.
  @override
  late final RouteMatcher matcher = _RootRouteMatcher(this);

  @override
  NavigationHistory get navigationHistory => _navigationHistory;

  /// Disposes this router with the navigation history, the url provider and
  /// the delegate it created, which also disposes the delegate's own
  /// listeners. Disposing that delegate disposes this router too.
  @override
  void dispose() {
    if (_isDisposed) return;
    super.dispose();
    _navigationHistory.dispose();
    _lazyInformationProvider?.dispose();
    _lazyRootDelegate?.dispose();
  }

  RouteCollection? _routeCollection;

  @override
  RouteCollection get routeCollection => _routeCollection ??= .fromList(
    routes,
    root: true,
    onGeneratePath: onGeneratePath,
  );

  // A hot reload may have changed what [routes] returns.
  @override
  void _reassemble() {
    _routeCollection = null;
    super._reassemble();
  }

  /// Generates a path for a route with the provided `name`
  ///
  /// routes with defined path will use the defined path
  /// and will not use this method
  ///
  /// routes marked with `initial` will use either '/' or an empty string
  /// for such routes
  ///
  /// use [isRoot] to determine if the route needs to start with '/'
  String onGeneratePath(AutoRoute route) {
    return RouteCollection.defaultPathGenerator(route);
  }
}

class _RootStackRouterImpl extends RootStackRouter {
  new({
    required this.routes,
    this.guards = const [],
    super.navigatorKey,
    this.defaultRouteType = const RouteType.material(),
    OnGeneratePath? onGeneratePath,
  }) : _onGeneratePath = onGeneratePath ?? RouteCollection.defaultPathGenerator;
  @override
  final List<AutoRoute> routes;

  @override
  final List<AutoRouteGuard> guards;

  @override
  final RouteType defaultRouteType;

  final OnGeneratePath _onGeneratePath;

  @override
  String onGeneratePath(AutoRoute route) {
    return _onGeneratePath(route);
  }
}

class _RootRouteMatcher extends RouteMatcher {
  new(this._router) : super(_router.routeCollection);

  final RootStackRouter _router;

  @override
  // The collection passed to super is the one of the moment; a hot reload
  // replaces it.
  // ignore: avoid-suspicious-super-overrides
  RouteCollection get collection => _router.routeCollection;
}
