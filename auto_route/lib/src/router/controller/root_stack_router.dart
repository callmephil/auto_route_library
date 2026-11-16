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

  // Counts the links the delegate opened.
  int _linkCount = 0;

  // The count of the link whose navigation is starting, while it starts.
  int? _startingLink;

  // The count of the latest link the app let in. A navigation a link starts
  // stops at its next guard once a link that started after it has been let
  // in: a slow guard of the link the app started at must not open its page
  // over the pages of a link that came after it. A link the app turns down
  // cancels no link before it, as a refused navigation changes nothing.
  int _letInLink = 0;

  // What each link does once it is let in, by its count, until a guarded
  // navigation of that link takes it, see [_takeLinkStep].
  final _linkSteps = <int, VoidCallback>{};

  // Whether the url reported right now is that of a link the delegate
  // opened, the launch url included.
  bool _isShowingLink = false;

  /// Whether the url state that reaches the [navigationHistory] right now is
  /// that of a link the delegate opened, the launch url included, and not
  /// of a navigation the app called.
  ///
  /// The pages a link opens together share its browser entry, while pages
  /// the app opens together get one each.
  @internal
  bool get isShowingLink => _isShowingLink;

  // Runs [show], which reports a url, as the url of a link when [isLink].
  T _showingLink<T>(T Function() show, {required bool isLink}) {
    final wasShowingLink = _isShowingLink;
    _isShowingLink = isLink || wasShowingLink;
    try {
      return show();
    } finally {
      _isShowingLink = wasShowingLink;
    }
  }

  // Runs [open], which starts the navigation of a new link, as that link's.
  // The navigation starts before [open] returns, up to its first guard, and
  // knows its link from [_startingLink] then. What it goes on to later, such
  // as the nested router of a page already open or a tabs router after a
  // guard's wait, is handed the link as an argument by the batch that causes
  // it; a navigation the app starts is never a link's, whatever code it runs
  // from, such as a listener a guard set up while a link opened.
  // [onAccepted] runs once the guards that navigation asks let the link in,
  // so a link the app turns down changes nothing else; when it asks no
  // guard, such as a link to the page already open, once it ends.
  Future<void> _openLink(
    Future<void> Function() open, {
    VoidCallback? onAccepted,
  }) {
    final link = _startingLink = ++_linkCount;
    _linkSteps[link] = () {
      if (link > _letInLink) {
        _letInLink = link;
        // The links before it give up at their next guard.
        _linkSteps.removeWhere((other, _) => other < link);
      }
      onAccepted?.call();
    };
    final Future<void> navigation;
    try {
      navigation = open();
    } finally {
      _startingLink = null;
    }
    if (_linkSteps.containsKey(link)) {
      // The navigation's own failure reaches its caller, which awaits it.
      unawaited(
        navigation.then(
          (_) => _linkSteps.remove(link)?.call(),
          onError: (Object _) => null,
        ),
      );
    }
    return navigation;
  }

  // Whether a link that started after [link] has been let in.
  bool _isLinkOvertaken(int link) => _letInLink > link;

  // The step [link] takes once it is let in, for the guarded navigation of
  // that link to run; null once taken.
  VoidCallback? _takeLinkStep(int link) => _linkSteps.remove(link);

  // Makes [step] the step of [link], for the guarded navigation of that
  // link that starts next to take, as when a tab change hands it on to the
  // tab's nested router, after any step that waits already. Drops it when a
  // later link has been let in.
  void _handLinkStepOn(int link, VoidCallback step) {
    if (_isLinkOvertaken(link)) return;
    final waiting = _linkSteps[link];
    _linkSteps[link] = waiting == null
        ? step
        : () {
            waiting();
            step();
          };
  }

  // Whether [step] waits for [link] to be let in, as it does while a guard
  // of that link has yet to answer; it then runs with the link's own step,
  // or not at all if the link is turned down.
  bool _deferToLinkAccepted(int link, VoidCallback step) {
    final linkStep = _linkSteps[link];
    if (linkStep == null) return false;
    _linkSteps[link] = () {
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
