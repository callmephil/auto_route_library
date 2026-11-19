part of 'routing_controller.dart';

/// Signature for a function that builds [DeepLink]
/// [deepLink] is the pre-resolved link coming from platform window
typedef DeepLinkBuilder = FutureOr<DeepLink> Function(
  PlatformDeepLink deepLink,
);

/// Signature for a function that transform the incoming [Uri]
/// [uri] is the pre-resolved uri coming from platform window
/// This is call before the [DeepLinkBuilder] to allow to transform the [Uri]
typedef DeepLinkTransformer = Future<Uri> Function(Uri uri);

/// An auto_route implementation for [RouterDelegate]
class AutoRouterDelegate extends RouterDelegate<UrlState> with ChangeNotifier {
  /// Default constructor
  new(
    this.controller, {
    this.placeholder,
    this.navRestorationScopeId,
    this.navigatorObservers = defaultNavigatorObserversBuilder,
    this.deepLinkBuilder,
    this.rebuildStackOnDeepLink = false,
    this.reevaluateListenable,
    this.clipBehavior = Clip.hardEdge,
    this.routeTraversalEdgeBehavior,
  }) {
    _navigatorObservers = navigatorObservers();
    controller.navigationHistory.addListener(_handleRebuild);
    reevaluateListenable?.addListener(_reevaluateGuards);
    if (!kIsWeb) {
      // Pages can change without the url changing; the Router saves them
      // through currentConfiguration.
      controller.addListener(notifyListeners);
    } else {
      // A deep link's url is set before its page is in; the Router, which
      // builds the pages, hears of the first one here.
      controller.addListener(_reportFirstPage);
    }
  }

  /// An object that provides pages stack to [Navigator.pages]
  /// and wraps a navigator key to handle stack navigation actions
  final StackRouter controller;

  /// Clients can use this to intercept deep-links
  /// coming from platform and validate, abort or override it.
  final DeepLinkBuilder? deepLinkBuilder;

  /// Passed to [Navigator.restorationScopeId]
  final String? navRestorationScopeId;

  /// A builder function that returns a list of observes
  ///
  /// Why isn't this a list of navigatorObservers?
  /// The reason for that is a [NavigatorObserver] instance can only
  /// be used by a single [Navigator], so unless you're using a one
  /// single router or you don't want your nested routers to inherit
  /// observers make sure navigatorObservers builder always returns
  /// fresh observer instances.
  final NavigatorObserversBuilder navigatorObservers;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with `Theme.scaffoldBackgroundColor`.
  final WidgetBuilder? placeholder;

  /// if set to true the new stack
  /// will replace the old one on
  /// deep-links coming from the platform
  ///
  /// replaces all previous routes with the new ones, each on a screen of its
  /// own, once the guards let the new ones in, as [StackRouter.replaceAll]
  /// does; a link they reject leaves the stack as it was. A page a guard
  /// shows meanwhile, such as a login with
  /// [NavigationResolver.redirectUntil], goes on over the pages that are
  /// open, and back from it rejects the link and shows them
  ///
  /// on the web, the browser's back and forward buttons are no deep-links:
  /// they show the page of the entry they go to, with the pages under it,
  /// as without this flag, since they change no entry; a url typed into
  /// the address bar is one
  ///
  /// this is used after a deep-link is
  /// resolved by [deepLinkBuilder] if provided
  ///
  /// defaults to false
  final bool rebuildStackOnDeepLink;

  /// A listenable that triggers a re-evaluation of the guards
  final Listenable? reevaluateListenable;

  /// The clip behavior of the navigator
  final Clip clipBehavior;

  /// The traversal edge behavior of the navigator
  final TraversalEdgeBehavior? routeTraversalEdgeBehavior;

  /// Builds an empty observers list
  static List<NavigatorObserver> defaultNavigatorObserversBuilder() => const [];

  /// Looks up and casts the scoped [Router] to [AutoRouterDelegate]
  static AutoRouterDelegate of(BuildContext context) {
    final delegate = Router.of(context).routerDelegate;
    assert(
      delegate is AutoRouterDelegate,
      'The nearest Router does not use an AutoRouterDelegate.',
    );
    return delegate as AutoRouterDelegate;
  }

  /// Forces a url update
  static void reportUrlChanged(BuildContext context, String url) {
    Router.of(context).routeInformationProvider
        ?.routerReportsNewRouteInformation(
          RouteInformation(uri: Uri.parse(url)),
          type: .navigate,
        );
  }

  @override
  Future<bool> popRoute() async => await controller.maybePopTop();

  late List<NavigatorObserver> _navigatorObservers;

  void _reportFirstPage() {
    if (!controller.hasEntries) return;
    controller.removeListener(_reportFirstPage);
    _handleRebuild();
  }

  /// The url state of the pages on screen, see [RoutingController.urlState].
  UrlState get urlState => controller.navigationHistory.shownUrlState;

  /// The current [urlState] with the pages of every router and the route the
  /// platform started the app at, which the [Router] reports to the platform
  /// and saves for state restoration.
  ///
  /// Null on the web, where [urlState] is the way to read the url: the
  /// navigation history writes the browser's entries itself, whenever the
  /// app navigates, and the [Router], which writes once a frame, must write
  /// none. A Router reports nothing for a null configuration. The web has
  /// no state restoration to save a route for.
  ///
  /// Off the web, null until the first navigation has put a page in the root
  /// router, so that the Router reports no empty url before the deep link
  /// the app opens.
  @override
  UrlState? get currentConfiguration {
    // Only before the first page: later the stack can be empty for a moment,
    // as in pushAndPopUntil, and the url must still be reported.
    _hadPage = _hadPage || controller.hasEntries;
    if (!_hadPage || controller.navigationHistory.writesBrowser) return null;
    return urlState.copyWith(
      savedRoutes: {
        _routesKey: controller._savedRoutes(),
        _launchLinkKey: _launchLink,
      },
    );
  }

  // The keys of what currentConfiguration saves for state restoration.
  static const _routesKey = 'routes';
  static const _launchLinkKey = 'launchLink';

  // The route the platform started this process at: a link, or '/'.
  static String get _launchLink =>
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  var _hadPage = false;

  // Whether the Router handed this delegate a route, through
  // setInitialRoutePath, setNewRoutePath or setRestoredRoutePath.
  bool _wasGivenRoute = false;

  // Numbers the links handed to the delegate, in the order they came.
  int _handedOverLinks = 0;

  // The number of the link handed over last of those that started opening.
  int _lastOpenedLink = 0;

  @override
  Future<void> setInitialRoutePath(UrlState configuration) async {
    _wasGivenRoute = true;
    // setInitialRoutePath is re-fired on enabling
    // select widget mode from flutter inspector,
    // this check is preventing it from rebuilding the app
    if (controller.hasEntries) {
      return;
    }
    // A browser opens the app at its url, so a later route on the web is never
    // the link of the launch.
    if (!kIsWeb && _launchLink == Navigator.defaultRouteName) {
      _launchWatch = AppLifecycleListener(onHide: _endLaunch);
    }
    final platformDeepLink = PlatformDeepLink._(configuration, true);
    final handover = ++_handedOverLinks;
    if (deepLinkBuilder != null) {
      final resolvedLink = await deepLinkBuilder!(platformDeepLink);
      if (_wasOvertaken(handover)) return;
      return await _openLaunchLink(resolvedLink, handover: handover);
    } else if (platformDeepLink.isValid) {
      return await _openLaunchLink(platformDeepLink, handover: handover);
    }
    throw FlutterError(_unresolvedMessage(platformDeepLink));
  }

  // Opens [link], the link the app is launched at. When the app turns it
  // down, the url is that of the pages a guard let in below it, such as the
  // page a link brings below its own, or '/' with none; a later link reports
  // its own url.
  Future<void> _openLaunchLink(DeepLink link, {required int handover}) async {
    final root = controller.root;
    final asks = root._startLaunchAsks();
    try {
      var isAccepted = false;
      final opening = _handleDeepLink(
        link,
        handover: handover,
        onAccepted: () => isAccepted = true,
      );
      final count = root._linkCount;
      await opening;
      if (!isAccepted &&
          !_isDisposed &&
          controller.hasEntries &&
          count == root._linkCount) {
        return _reportTurnedDownLink(link);
      }
      // No page came in and no later link took over: the first page of the
      // app shows rather than an empty screen, see [_reportRejectedLaunch].
      if (!isAccepted &&
          !_isDisposed &&
          !controller.hasEntries &&
          count == root._linkCount) {
        await root._openInitialRoutesOfEmptiedRoot(asks);
        if (!_isDisposed &&
            !controller.hasEntries &&
            count == root._linkCount &&
            !asks.hasReportedLoop) {
          _reportNoPageAtLaunch();
        }
      }
      _reportRejectedLaunch();
    } finally {
      root._endLaunchAsks(asks);
    }
  }

  // The guards turned down the link the app launched at and its first page
  // too, and no page is left to show. Flutter's Navigator refuses an empty
  // list of pages the same way, with an error in place of a blank screen.
  void _reportNoPageAtLaunch() {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts([
          ErrorSummary('The app launched with no page to show.'),
          ErrorDescription(
            'The guards turned down the link the app launched at, and the '
            'first page of the app, the route marked initial or at /, too. '
            'No page of the app is below them, so the screen is empty.',
          ),
          ErrorHint(
            'A guard that turns down the first page of the app should '
            'redirect to a page the user may see, e.g. call '
            'resolver.redirectUntil(LoginRoute()) in place of '
            'resolver.next(false).',
          ),
        ]),
        library: 'auto_route',
      ),
    );
  }

  // Whether a link handed over after the link numbered [handover] started
  // opening while deepLinkBuilder answered for it. The later link wins, as a
  // route whose parse ends after a newer one was reported is dropped in
  // Flutter's Router; unless the app shows no page yet, as when the later
  // link was rejected. A link the app ignores starts nothing, so it drops no
  // link before it.
  bool _wasOvertaken(int handover) =>
      _isDisposed || (_lastOpenedLink > handover && controller.hasEntries);

  // The app opened at a link that put no page in, as when a guard rejected it.
  // No url is reported until a page is in, so the link would stay in the
  // address bar and a reload would open it again; now the empty url takes
  // its place. A page that comes later is reported as usual.
  void _reportRejectedLaunch() {
    if (_hadPage || controller.hasEntries) return;
    _hadPage = true;
    // The rejected link's url was set before its guards ran.
    controller.navigationHistory.onNewUrlState(
      UrlState.fromSegments(const []).copyWith(shouldReplace: true),
      notify: false,
    );
    notifyListeners();
  }

  // Opens [deepLink], the link numbered [handover] as it was handed over.
  // The pageless routes in [closing], such as a dialog the link came over,
  // close only once its guards let it in, when [onAccepted] runs too: a link
  // the app turns down changes nothing on screen.
  Future<void> _handleDeepLink(
    DeepLink deepLink, {
    required int handover,
    required VoidCallback onAccepted,
    bool replacesLaunchPage = false,
    bool rebuildsStack = false,
    List<Route<Object?>> closing = const [],
  }) {
    if (deepLink is _IgnoredDeepLink) return SynchronousFuture(null);

    if (!deepLink.isValid) throw FlutterError(_unresolvedMessage(deepLink));
    if (handover > _lastOpenedLink) _lastOpenedLink = handover;
    return controller.root._openLink(
      () => _openDeepLink(
        deepLink,
        replacesLaunchPage: replacesLaunchPage,
        rebuildsStack: rebuildsStack,
      ),
      onAccepted: () {
        _closePagelessRoutes(closing);
        onAccepted();
      },
    );
  }

  // The running app turned down [link], the link it was handed, as when a
  // guard rejected it or deepLinkBuilder answered DeepLink.none. The link's
  // url, set before its guards ran, gives way to that of the pages the app
  // shows, reported over the link's browser entry, as [_reportRejectedLaunch]
  // does for the launch. Off the web that url went into the app's own
  // history as an entry of its own, and the pages the link reached again,
  // such as a tabs page the link went on through, may have reported theirs
  // after it: the entry of the page the link named, which never opened,
  // leaves, or back() would go to it.
  void _reportTurnedDownLink(DeepLink link) {
    final history = controller.navigationHistory;
    final shown = UrlState.fromSegments(
      controller.currentSegments,
      shouldReplace: true,
    );
    // A url state the link left alone keeps its path state.
    if (!const ListEquality<Object?>().equals(
      history.urlState.segments,
      shown.segments,
    )) {
      history.onNewUrlState(shown, notify: false);
    }
    // The url is the page's on screen by now, so this changes the entries
    // alone.
    if (link is PlatformDeepLink && !history.writesBrowser) {
      if (link.configuration.flatten.topMatch?.id case final linkPage?) {
        history.rebuildUrlAfterClosingUnbuilt([linkPage]);
      }
    }
    final context = controller.navigatorKey.currentContext;
    if (context == null || history.writesBrowser) {
      return notifyListeners();
    }
    Router.neglect(context, notifyListeners);
  }

  // The dialogs, sheets and other pageless routes over the top page of the
  // top-most router, the newest first.
  List<Route<Object?>> _pagelessRoutesOnTop() {
    final topMost = controller.topMostRouter();
    if (topMost is! StackRouter || !topMost.hasPagelessTopRoute) {
      return const [];
    }
    final observer = topMost.pagelessRoutesObserver;
    final pageRoute = observer.topPageRoute;
    if (pageRoute == null) return const [];
    return observer.pagelessRoutesOver(pageRoute).reversed.toList();
  }

  // Closes the pageless [routes], the newest first, that are still open: the
  // one on top is popped, one a page now covers, such as a guard's sign-in
  // page, is removed unseen.
  static void _closePagelessRoutes(List<Route<Object?>> routes) {
    for (final route in routes) {
      final navigator = route.navigator;
      if (navigator == null || !route.isActive) continue;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
  }

  // With [rebuildsStack], the link's pages replace the stack, each on a screen
  // of its own; a replacement a guard rejects puts the stack back.
  Future<void> _openDeepLink(
    DeepLink deepLink, {
    required bool replacesLaunchPage,
    required bool rebuildsStack,
  }) {
    if (deepLink is PlatformDeepLink) {
      _onNewUrlState(deepLink.configuration);
      // A replacement a guard rejects puts the launch page back.
      return replacesLaunchPage || rebuildsStack
          ? controller._replaceAllMatches(
              deepLink.matches,
              updateExistingRoutes: !rebuildsStack,
              isLink: true,
            )
          : controller.navigateAll(deepLink.matches);
    } else if (deepLink is _PathDeepLink) {
      final matches = rebuildsStack
          ? controller.matcher.match(
              deepLink.path,
              includePrefixMatches: deepLink.includePrefixMatches,
            )
          : null;
      // A path no route matches is reported by navigatePath and pushPath.
      if (matches != null) {
        return controller._replaceAllMatches(
          matches,
          updateExistingRoutes: false,
          isLink: true,
        );
      }
      if (deepLink.navigate) {
        return controller.navigatePath(
          deepLink.path,
          includePrefixMatches: deepLink.includePrefixMatches,
        );
      }
      return controller.pushPath(
        deepLink.path,
        includePrefixMatches: deepLink.includePrefixMatches,
      );
    } else if (deepLink is _RoutesDeepLink) {
      if (rebuildsStack) {
        return controller._replaceAll(
          deepLink.routes,
          updateExistingRoutes: false,
          isLink: true,
        );
      }
      if (deepLink.navigate) {
        return controller._navigateAllRoutes(deepLink.routes);
      }
      return controller.pushAll(deepLink.routes);
    }
    throw FlutterError('Unsupported DeepLink ${deepLink.runtimeType}');
  }

  /// Rebuilds the pages of every router from [UrlState.savedRoutes] when the
  /// app is restored, guards included; without them, opens the restored url.
  ///
  /// A page that can't be built without the args it was opened with is left
  /// out, since args aren't saved.
  ///
  /// A link the platform started the restored app with then opens over the
  /// restored pages, as it does in the running app. A link that also started
  /// the app that was saved is not opened again: Android restarts an app from
  /// its recent apps with the link that first opened it.
  @override
  Future<void> setRestoredRoutePath(UrlState configuration) {
    _wasGivenRoute = true;
    final saved = configuration.savedRoutes;
    if (_launchLink != Navigator.defaultRouteName &&
        (saved is! Map || saved[_launchLinkKey] != _launchLink)) {
      _openLaunchLinkAfterRestore();
    }
    // Saved before the launch link was, the routes alone.
    final routes = _restoredRoutes(saved is Map ? saved[_routesKey] : saved);
    // A saved route that no longer matches drops the saved stack, rather
    // than throwing.
    final matches = routes == null || routes.isEmpty || controller.hasEntries
        ? null
        : controller._matchAllOrReportFailure(routes, shouldThrow: false);
    final buildable = matches == null
        ? const <RouteMatch<Object?>>[]
        : _buildableMatches(matches, controller);
    if (buildable.isEmpty) {
      return setNewRoutePath(configuration);
    }
    controller.root._markRestored(buildable);
    return controller.navigateAll(buildable);
  }

  // Hands the launch link to the Router's route information provider once the
  // restored pages are built, the way the platform hands a link to the
  // running app, so the parser and deepLinkBuilder see it too.
  void _openLaunchLinkAfterRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = controller.navigatorKey.currentContext;
      // Typed as Object so the check below makes it an observer.
      final Object? provider = context == null
          ? null
          : Router.maybeOf(context)?.routeInformationProvider;
      if (provider is WidgetsBindingObserver) {
        unawaited(
          provider.didPushRouteInformation(
            RouteInformation(uri: Uri.parse(_launchLink)),
          ),
        );
      }
    }, debugLabel: 'AutoRouterDelegate.openLaunchLinkAfterRestore');
  }

  // Names the link no route matched, which on a phone can come from another
  // app, so the error says what to look for.
  String _unresolvedMessage(DeepLink deepLink) {
    if (deepLink is! PlatformDeepLink) return 'Can not resolve initial route';
    return 'Can not resolve initial route: no route matches "${deepLink.uri}". '
        "Add RedirectRoute(path: '*', redirectTo: '/') last in your routes to open "
        'links no route matches on your initial page. The routes of the '
        'app, by full path:\n'
        '${controller.routeCollection.toTreeString()}';
  }

  // Lives while the app that started at the platform's default route has
  // stayed on screen and been handed no route since.
  AppLifecycleListener? _launchWatch;

  void _endLaunch() {
    _launchWatch?.dispose();
    _launchWatch = null;
  }

  // Whether [link], handed over while the launch page is all the app shows,
  // takes that page's place. iOS hands the link of a cold start over after the
  // first frame, so the app opens '/' first and the link then lands on top of
  // it. With prefix matches off, a link names only its own page, so a cold
  // start at it keeps nothing below it, and neither does this. Only while the
  // app has stayed on screen: a link that reaches an app that has been in the
  // background opens over its page, as in any running app.
  bool _doesLinkReplaceLaunchPage(DeepLink link) {
    if (_launchWatch == null || link is! PlatformDeepLink) return false;
    final launchPage = controller.stack.singleOrNull;
    final context = controller.navigatorKey.currentContext;
    final parser = context == null
        ? null
        : Router.maybeOf(context)?.routeInformationParser;
    return launchPage != null &&
        parser is DefaultRouteParser &&
        !parser.includePrefixMatches &&
        link.matches.firstOrNull?.name != launchPage.name;
  }

  @override
  Future<void> setNewRoutePath(UrlState configuration) async {
    _wasGivenRoute = true;
    final history = controller.navigationHistory;
    if (history.consumeOwnBrowserMove(configuration)) {
      return;
    }
    if (history.isBrowserBehindApp && _doesTopRouteRefusePop()) {
      history.returnBrowserToApp();
      return;
    }
    history.followBrowser();
    final pageless = _pagelessRoutesOnTop();

    final pageToPush = history.pageToPushForBrowserEntry(configuration);
    if (pageToPush != null) {
      final (stack, page) = pageToPush;
      // The future completes when the page is popped.
      unawaited(
        stack._pushAllGuarded([
          page,
        ], onFirstRouteAccepted: () => _closePagelessRoutes(pageless)),
      );
    } else if (configuration.hasSegments) {
      final entryRoutes = controller.navigationHistory.routesOfBrowserEntry(
        configuration,
      );
      if (entryRoutes != null && entryRoutes.isEmpty) {
        notifyListeners();
        return;
      }
      final platLink = PlatformDeepLink._(
        entryRoutes == null
            ? configuration
            : configuration.copyWith(segments: entryRoutes),
        false,
      );
      final handover = ++_handedOverLinks;
      final resolvedLink = deepLinkBuilder == null
          ? platLink
          : await deepLinkBuilder!(platLink);
      if (_wasOvertaken(handover)) return;
      final replacesLaunchPage = _doesLinkReplaceLaunchPage(resolvedLink);
      _endLaunch();
      var isAccepted = false;
      final root = controller.root;
      final Future<void> opening;
      try {
        root._isOpeningBrowserEntry = entryRoutes != null;
        opening = _handleDeepLink(
          resolvedLink,
          handover: handover,
          replacesLaunchPage: replacesLaunchPage,
          // An entry from before a reload opens as a link whose pages take
          // the place of the app's, which have their entries ahead of it.
          // An entry the app wrote is no link: back and forward change no
          // entry, so the pages under its page stay, with their entries.
          rebuildsStack:
              (rebuildStackOnDeepLink && entryRoutes == null) ||
              history.isOnEntryBeforeApp,
          closing: pageless,
          onAccepted: () => isAccepted = true,
        );
      } finally {
        root._isOpeningBrowserEntry = false;
      }
      // The count of this link, or of the one before for a link the app
      // ignores.
      final count = controller.root._linkCount;
      await opening;
      // A later link reports its own url.
      if (!isAccepted && !_isDisposed && count == controller.root._linkCount) {
        return _reportTurnedDownLink(resolvedLink);
      }
    }

    // The link's navigation ends when its page leaves the stack, which
    // disposing the router also does.
    if (_isDisposed) return;
    notifyListeners();
  }

  // A Router hands its route to the delegate it starts with alone. A delegate
  // swapped into a running Router, as by an app that picks one of two routers
  // when the user signs in, is never given one and would show no page. So it
  // opens the route the Router shows, the way setInitialRoutePath would.
  Future<void> _openRouteOfRunningRouter(BuildContext context) async {
    if (_wasGivenRoute || controller.hasEntries) return;
    final router = Router.of(context);
    final information = router.routeInformationProvider?.value;
    final parser = router.routeInformationParser;
    if (information == null || parser == null) return;
    final configuration = await parser.parseRouteInformationWithDependencies(
      information,
      context,
    );
    // The Router may have handed it a route while the parser ran.
    if (configuration is UrlState && !_wasGivenRoute) {
      await setInitialRoutePath(configuration);
      _endLaunch();
    }
  }

  // Whether the route on top of the top-most navigator refuses to be popped,
  // through a PopScope; asks it the way Navigator.maybePop does, so it hears
  // of the attempt.
  bool _doesTopRouteRefusePop() {
    final topMost = controller.topMostRouter();
    if (topMost is! StackRouter) return false;
    Route<Object?>? topRoute;
    // The predicate stops at the first route it's given, the top one, so
    // nothing is popped.
    topMost.navigatorKey.currentState?.popUntil((route) {
      topRoute = route;
      return true;
    });
    final route = topRoute;
    if (route == null) return false;
    if (route.popDisposition == .doNotPop) {
      route.onPopInvokedWithResult(false, null);
      return true;
    }
    return false;
  }

  void _onNewUrlState(UrlState state) {
    final pathInBrowser = state.uri.path;
    var matchedUrlState = state.flatten;
    // On the web the browser made an entry for the link, with the link's own
    // path; a path the router writes differently, after a redirect, a
    // transformer or a nested segment written again, takes that entry. Off
    // the web the link has no entry of its own: its pages get a new one.
    if (controller.navigationHistory.writesBrowser &&
        pathInBrowser != matchedUrlState.path) {
      matchedUrlState = matchedUrlState.copyWith(shouldReplace: true);
    }
    controller.root._showingLink(
      () => controller.navigationHistory.onNewUrlState(matchedUrlState),
      isLink: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // A Router builds this delegate: the history's urls can be written from
    // now on, by the Router or, on the web, through its provider.
    controller.navigationHistory.markShownByRouter(context);
    return _AutoRootRouter(
      router: controller,
      navigatorObservers: _navigatorObservers,
      navigatorObserversBuilder: navigatorObservers,
      navRestorationScopeId: navRestorationScopeId,
      placeholderBuilder: placeholder,
      clipBehavior: clipBehavior,
      routeTraversalEdgeBehavior: routeTraversalEdgeBehavior,
    );
  }

  // A listener returns nothing, so the reevaluation runs on its own.
  void _reevaluateGuards() => unawaited(controller.reevaluateGuards());

  void _handleRebuild() {
    final context = controller.navigatorKey.currentContext;
    // On the web the history writes the url itself, and the Router none.
    if (controller.navigationHistory.urlState.shouldReplace &&
        context != null &&
        !controller.navigationHistory.writesBrowser) {
      // Flutter's default route information provider ignores
      // AutoRouteInformation.replace; it replaces the entry only when the
      // router reports the change as neglected.
      Router.neglect(context, notifyListeners);
    } else {
      notifyListeners();
    }
  }

  // Disposing the root router disposes this delegate, and this delegate
  // disposes the root router; the second call returns at once.
  bool _isDisposed = false;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _endLaunch();
    super.dispose();
    controller.navigationHistory.removeListener(_handleRebuild);
    reevaluateListenable?.removeListener(_reevaluateGuards);
    controller.removeListener(notifyListeners);
    controller.removeListener(_reportFirstPage);
    controller.dispose();
  }

  /// Force this delegate to rebuild
  void notifyUrlChanged() => _handleRebuild();
}

class _AutoRootRouter extends StatefulWidget {
  const new({
    required this.router,
    required this.navigatorObserversBuilder,
    required this.navRestorationScopeId,
    required this.navigatorObservers,
    required this.placeholderBuilder,
    required this.clipBehavior,
    required this.routeTraversalEdgeBehavior,
  });

  final Clip clipBehavior;
  final StackRouter router;
  final String? navRestorationScopeId;
  final List<NavigatorObserver> navigatorObservers;
  final NavigatorObserversBuilder navigatorObserversBuilder;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with `Theme.scaffoldBackgroundColor`.
  final WidgetBuilder? placeholderBuilder;

  final TraversalEdgeBehavior? routeTraversalEdgeBehavior;

  @override
  _AutoRootRouterState createState() => .new();
}

class _AutoRootRouterState extends State<_AutoRootRouter> {
  StackRouter get router => widget.router;

  // A hot reload may have changed the routes the router was built from.
  @override
  void reassemble() {
    super.reassemble();
    router._reassemble();
  }

  // A new router here means the Router swapped its delegate, which it hands
  // no route: the new delegate opens the Router's route itself, after this
  // frame, since opening it notifies the widgets being built.
  @override
  void didUpdateWidget(_AutoRootRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.router, oldWidget.router)) return;
    WidgetsBinding.instance.addPostFrameCallback(
      _openRouteOfSwappedDelegate,
      debugLabel: 'AutoRootRouter.openRouteOfSwappedDelegate',
    );
  }

  void _openRouteOfSwappedDelegate(Duration _) {
    if (!mounted) return;
    final delegate = Router.of(context).routerDelegate;
    if (delegate is AutoRouterDelegate &&
        identical(delegate.controller, router)) {
      unawaited(delegate._openRouteOfRunningRouter(context));
    }
  }

  // Flutter tells Android whether the app takes back from the root navigator's
  // stack alone; while it says no, Android closes the app itself. A tabs router
  // away from its home tab, or with tabs in its history, takes back too: it
  // shows another tab (TabsRouter.maybePop). So this corrects the value, and
  // sends it again after a tab switch, which the navigator never reports.
  bool? _canHandlePopAsReported;
  bool _didTabsTakeBack = false;
  bool _isReportScheduled = false;

  bool _doTabsTakeBack() {
    for (
      RoutingController? r = router.topMostRouter();
      r != null;
      r = r.parent()
    ) {
      if (r is TabsRouter && r._doesTakeBack) return true;
    }
    return false;
  }

  bool _didHandleNavigationNotification(NavigationNotification notification) {
    _didTabsTakeBack = _doTabsTakeBack();
    if (notification.canHandlePop || !_didTabsTakeBack) {
      _canHandlePopAsReported = notification.canHandlePop;
      return false;
    }
    _report(true);
    return true;
  }

  void _report(bool canHandlePop) {
    _canHandlePopAsReported = canHandlePop;
    NavigationNotification(canHandlePop: canHandlePop).dispatch(context);
  }

  void _scheduleTabsReport() {
    if (_isReportScheduled) return;
    _isReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isReportScheduled = false;
      if (!mounted) return;
      final doTabsTakeBack = _doTabsTakeBack();
      if (doTabsTakeBack == _didTabsTakeBack) return;
      _didTabsTakeBack = doTabsTakeBack;
      final canHandlePop = doTabsTakeBack || _doesRootNavigatorTakeBack();
      if (canHandlePop != _canHandlePopAsReported) _report(canHandlePop);
    }, debugLabel: 'AutoRootRouter.reportTabsBack');
  }

  // What the root navigator reports: whether it can pop, or its top route
  // refuses the pop.
  bool _doesRootNavigatorTakeBack() {
    final navigator = router.navigatorKey.currentState;
    if (navigator == null) return false;
    if (navigator.canPop()) return true;
    Route<Object?>? topRoute;
    // The predicate stops at the first route it's given, the top one, so
    // nothing is popped.
    navigator.popUntil((route) {
      topRoute = route;
      return true;
    });
    return topRoute?.popDisposition == .doNotPop;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: _didHandleNavigationNotification,
      child: ListenableBuilder(
        listenable: router,
        builder: (context, _) {
          _scheduleTabsReport();
          final stateHash = router.stateHash;
          return RouterScope(
            key: router.globalRouterKey,
            controller: router,
            navigatorObservers: widget.navigatorObservers,
            inheritableObserversBuilder: widget.navigatorObserversBuilder,
            stateHash: stateHash,
            child: StackRouterScope(
              stateHash: stateHash,
              controller: router,
              child: AutoRouteNavigator(
                router: router,
                clipBehavior: widget.clipBehavior,
                key: GlobalObjectKey(widget.router.hashCode),
                placeholder: widget.placeholderBuilder,
                navRestorationScopeId: widget.navRestorationScopeId,
                navigatorObservers: widget.navigatorObservers,
                routeTraversalEdgeBehavior: widget.routeTraversalEdgeBehavior,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Holds deep-link information
abstract class DeepLink {
  /// Builds a deep-link from a list of `PageRouteInfo`s
  const factory(List<PageRouteInfo> routes, {bool navigate}) = _RoutesDeepLink;

  /// Builds a deep-link from a single `PageRouteInfo`
  factory single(PageRouteInfo route, {bool navigate = true}) {
    return _RoutesDeepLink([route], navigate: navigate);
  }

  /// Builds a deep-link form string path
  const factory path(String path, {bool includePrefixMatches, bool navigate}) =
      _PathDeepLink;
  const new _();

  /// Whether this link is navigable
  ///
  /// e.g PathDeepLink.path.isNotEmpty;
  bool get isValid;

  /// Builds a deep link with initial path
  static const DeepLink defaultPath = DeepLink.path(Navigator.defaultRouteName);

  /// Builds an ignored deep link instance
  static const DeepLink none = _IgnoredDeepLink();

  /// Helper function to remove the prefix path of a [Uri]
  /// You can use this method to remove the prefix of a path, such as '/app'
  /// from 'https://app.example.com/app/books/1', which becomes
  /// 'https://app.example.com/books/1'
  ///
  /// The prefix is one or more whole segments at the start of the path, with
  /// or without its leading `/`: '/app' strips '/app/books' and '/app', not
  /// '/application'. The host, query and fragment stay; a path the prefix
  /// doesn't start is left as it is
  static DeepLinkTransformer prefixStripper(String prefix) {
    var segments = prefix;
    while (segments.endsWith('/')) {
      segments = segments.substring(0, segments.length - 1);
    }
    final prefixPath = segments.startsWith('/') ? segments : '/$segments';
    return (Uri uri) {
      final path = uri.path;
      if (prefixPath == '/' ||
          (path != prefixPath && !path.startsWith('$prefixPath/'))) {
        return SynchronousFuture(uri); // No change if prefix not found
      }
      final rest = path.substring(prefixPath.length);
      return SynchronousFuture(uri.replace(path: rest.isEmpty ? '/' : rest));
    };
  }
}

class _PathDeepLink extends DeepLink {
  const new(this.path, {this.includePrefixMatches = true, this.navigate = true})
    : super._();
  final String path;
  final bool includePrefixMatches;

  /// if false the path will be pushed instead of navigated
  final bool navigate;

  @override
  bool get isValid => path.isNotEmpty;
}

class _RoutesDeepLink extends DeepLink {
  const new(this.routes, {this.navigate = true}) : super._();
  final List<PageRouteInfo> routes;

  /// if false the routes will be pushed instead of navigated
  final bool navigate;

  @override
  bool get isValid => routes.isNotEmpty;
}

class _IgnoredDeepLink extends DeepLink {
  const new() : super._();

  @override
  bool get isValid => false;
}

/// Holds information of the deep-link
/// coming from the platform window
class PlatformDeepLink extends DeepLink {
  const new _(this.configuration, this.initial) : super._();

  /// The initial url state parsed from initial raw path
  final UrlState configuration;

  /// The raw deep-link as String
  String get path => configuration.path;

  /// The parsed uri from the raw path
  Uri get uri => configuration.uri;

  /// Whether this is the initial deep-link
  final bool initial;

  /// The pre-matched routes from the row path
  List<RouteMatch<Object?>> get matches => configuration.segments;

  @override
  bool get isValid => configuration.hasSegments;
}
