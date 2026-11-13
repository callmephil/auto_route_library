import 'dart:async';

import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:auto_route/src/router/provider/browser_entry_state.dart'
    if (dart.library.js_interop) 'package:auto_route/src/router/provider/browser_entry_state_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The route information provider that propagates the platform route
/// information changes.
///
/// This provider also reports the new route information from the [Router]
/// widget back to engine using message channel method, the
/// [SystemNavigator.routeInformationUpdated].
///
/// Each time [SystemNavigator.routeInformationUpdated] is called, the
/// [SystemNavigator.selectMultiEntryHistory] method is also called. This
/// overrides the initialization behavior of
/// [Navigator.reportsRouteUpdateToEngine].
class AutoRouteInformationProvider extends RouteInformationProvider
    with WidgetsBindingObserver, ChangeNotifier {
  /// Create a platform route information provider.
  ///
  /// Use the [initialRouteInformation] to set the default route information for
  /// this provider.
  factory({
    RouteInformation? initialRouteInformation,
    bool Function(String? location)? neglectWhen,
  }) {
    // On web the engine starts the app with no state, even when the browser
    // entry it opens at holds the state the app saved there, as when the
    // user comes back to the app from another site (flutter/flutter#108697).
    // So the state is read from the entry itself.
    final initialRouteInfo =
        initialRouteInformation ??
        RouteInformation(
          uri: Uri.parse(
            WidgetsBinding.instance.platformDispatcher.defaultRouteName,
          ),
          state: browserEntryState(),
        );

    return AutoRouteInformationProvider._(
      initialRouteInformation: initialRouteInfo,
      neglectIf: neglectWhen,
    );
  }
  new _({required RouteInformation initialRouteInformation, this.neglectIf})
    : _value = initialRouteInformation;

  /// Decides whether a location the router reports is kept from the engine.
  ///
  /// Gets the location as the address bar shows it, with its query, such as
  /// `/books/a%20b?note=x%26y`, on every platform. When it returns true, the
  /// location isn't reported, so the address bar and the history stay as
  /// they were.
  bool Function(String? location)? neglectIf;

  /// A report the router's next report is left out for when it reports the
  /// same location and state.
  ///
  /// The web history writes the browser entries of a turn's navigations itself
  /// as the turn ends; the Router then reports the same url after the frame,
  /// with the frame's one kind, which would write it once more. Any other
  /// report goes through, and ends the skip.
  @internal
  RouteInformation? reportToSkip;

  /// Reports [information] for the web history, which writes a turn's browser
  /// entries itself; [reportToSkip] stays for the router's own report.
  @internal
  void reportFromHistory(
    RouteInformation information, {
    required RouteInformationReportingType type,
  }) {
    final skipped = reportToSkip;
    reportToSkip = null;
    routerReportsNewRouteInformation(information, type: type);
    reportToSkip = skipped;
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = .none,
  }) {
    final skipped = reportToSkip;
    reportToSkip = null;
    if (skipped != null && _isSameReport(skipped, routeInformation)) return;
    // On web DefaultRouteParser hands over the uri escaped for the engine.
    // Compare and keep the app's own uri, and escape one that skipped it.
    final appRouteInformation =
        routeInformation is AutoRouteInformation &&
            routeInformation.appUri != null
        ? RouteInformation(
            uri: routeInformation.appUri,
            state: routeInformation.state,
          )
        : routeInformation;
    // neglectWhen gets the location the address bar shows, the same on every
    // platform, not the string escaped once more for the web engine.
    if (neglectIf?.call(appRouteInformation.uri.toString()) ?? false) {
      return;
    }
    final reportedUri =
        identical(appRouteInformation, routeInformation) && kIsWeb
        ? escapeForWebEngine(routeInformation.uri)
        : routeInformation.uri;

    // The routes saved for state restoration stay with the Router.
    final state = UrlState.platformState(routeInformation.state);
    var shouldReplace =
        type == .neglect ||
        (type == .none &&
            _valueInEngine.uri == appRouteInformation.uri &&
            UrlState.platformState(_valueInEngine.state) == state);

    if (!shouldReplace && routeInformation is AutoRouteInformation) {
      shouldReplace = routeInformation.replace;
    }
    unawaited(SystemNavigator.selectMultiEntryHistory());
    unawaited(
      SystemNavigator.routeInformationUpdated(
        uri: reportedUri,
        state: state,
        replace: shouldReplace,
      ),
    );
    _value = appRouteInformation;
    _valueInEngine = appRouteInformation;
  }

  // Whether [a] and [b] report the same location and state.
  static bool _isSameReport(RouteInformation a, RouteInformation b) {
    Uri appUri(RouteInformation information) => switch (information) {
      AutoRouteInformation(:final appUri?) => appUri,
      _ => information.uri,
    };
    return appUri(a) == appUri(b) &&
        UrlState.platformState(a.state) == UrlState.platformState(b.state);
  }

  @override
  RouteInformation get value => _value;
  RouteInformation _value;

  // The browser entry the app starts at holds the state saved in it, too.
  RouteInformation _valueInEngine = RouteInformation(
    uri: Uri.parse(WidgetsBinding.instance.platformDispatcher.defaultRouteName),
    state: browserEntryState(),
  );

  void _platformReportsNewRouteInformation(RouteInformation routeInformation) {
    if (_value == routeInformation) return;
    _value = routeInformation;
    _valueInEngine = routeInformation;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) WidgetsBinding.instance.addObserver(this);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    // In practice, this will rarely be called. We assume that the listeners
    // will be added and removed in a coherent fashion such that when the object
    // is no longer being used, there's no listener, and so it will get garbage
    // collected.
    if (hasListeners) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    assert(
      hasListeners,
      'The route information provider has no listener to report to.',
    );
    _platformReportsNewRouteInformation(routeInformation);
    return SynchronousFuture(true);
  }
}
