import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_writer.dart';
import 'package:auto_route/src/router/controller/navigation_history/navigation_history.dart';
import 'package:auto_route/src/router/controller/routing_controller.dart';
import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:auto_route/src/router/provider/auto_route_information_provider.dart';
import 'package:auto_route/src/router/provider/browser_entry_state_web.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter/widgets.dart'
    show BuildContext, RouteInformationProvider, Router;
import 'package:web/web.dart';

/// An implementation of [NavigationHistory]
/// That's used for web
class NavigationHistoryImpl extends BrowserNavigationHistory {
  /// Default constructor
  new(StackRouter router) : this._(router, _WindowHistory());

  new _(StackRouter router, this._window) : super(router, _window);

  final _WindowHistory _window;

  // The history that writes the browser through each route information
  // provider: the one of the router its Router showed last. An app can
  // swap its router, as when the user signs in, and the Router then shows
  // another router with a history of its own on the same browser.
  static final _writing = Expando<NavigationHistoryImpl>();

  @override
  void markShownByRouter([BuildContext? routerContext]) {
    _window.routerContext = routerContext;
    final provider = _window.provider;
    if (provider != null) {
      final writing = _writing[provider];
      if (!identical(writing, this)) {
        _writing[provider] = this;
        if (writing != null) {
          writing.leaveBrowser();
          takeBrowser();
        }
      }
    }
    super.markShownByRouter(routerContext);
  }
}

// The browser's Navigation API, or null in a browser that has none, where
// the writer steps forward as it is asked.
@JS('navigation')
external _Navigation? get _navigation;

extension type const _Navigation._(JSObject _) implements JSObject {
  external bool get canGoForward;
}

// The browser's history as Flutter's web engine keeps it: every entry the
// app writes goes through the Router's route information provider to the
// engine, which numbers it with a serial count.
class _WindowHistory implements HistoryBrowser {
  JSFunction? _popStateListener;

  // The context the Router that shows the app builds its delegate with,
  // once it has: there also while the app shows no page.
  BuildContext? routerContext;

  Router<Object?>? get _shownBy {
    final context = routerContext;
    return context != null && context.mounted ? Router.maybeOf(context) : null;
  }

  // The route information provider the entries are written through.
  RouteInformationProvider? get provider => _shownBy?.routeInformationProvider;

  @override
  int get index {
    final entryState = window.history.state.dartify();
    if (entryState is Map) {
      final serialCount = entryState['serialCount'];
      if (serialCount is num) return serialCount.toInt();
    }
    return 0;
  }

  @override
  String get url => ui_web.urlStrategy?.getPath() ?? '/';

  @override
  Object? get state => browserEntryState();

  @override
  bool get canWrite => provider != null;

  @override
  bool keepsOut(UrlState entry) {
    final provider = this.provider;
    if (provider is! AutoRouteInformationProvider || !entry.hasSegments) {
      return false;
    }
    final location = entry.url.isEmpty ? '/' : entry.uri.toString();
    return provider.neglectIf?.call(location) ?? false;
  }

  // Through the Router's own parser and provider, so the url is escaped for
  // the engine and the provider knows what the engine holds.
  @override
  void write(UrlState entry, {required bool replaces}) {
    final shownBy = _shownBy;
    // The entry's own replace mark would make the provider replace.
    final information = shownBy?.routeInformationParser
        ?.restoreRouteInformation(entry.copyWith(shouldReplace: replaces));
    if (information == null) return;
    shownBy?.routeInformationProvider?.routerReportsNewRouteInformation(
      information,
      type: replaces ? .neglect : .navigate,
    );
  }

  // In a widget test the engine ignores what the app reports, unless the
  // test connects it to the browser: the reports then reach only a handler
  // the test set on the navigation channel, and nothing keeps an entry.
  @override
  bool get keepsEntries =>
      !ui_web.TestEnvironment.instance.ignorePlatformMessages;

  // The engine handles navigation messages one after another, so its reply
  // to this one comes once every entry reported before it is written.
  @override
  Future<void> whenWritten() => SystemNavigator.selectMultiEntryHistory();

  @override
  void go(int delta) => window.history.go(delta);

  @override
  bool get canGoForward => _navigation?.canGoForward ?? true;

  // The engine has a popstate listener of its own, which gives a serial
  // count to an entry the browser made, as for a url typed into the address
  // bar. This listener may run before it, so the landing is told after the
  // event, when [index] can be read.
  @override
  void listen(void Function() onLanding) {
    close();
    final listener = ((Event _) => Timer.run(onLanding)).toJS;
    _popStateListener = listener;
    window.addEventListener('popstate', listener);
  }

  @override
  void close() {
    final listener = _popStateListener;
    _popStateListener = null;
    if (listener != null) window.removeEventListener('popstate', listener);
  }
}
