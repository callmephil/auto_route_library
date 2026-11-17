@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../main_router.dart';
import '../router_test_utils.dart';
import 'browser_history.dart';

// On Flutter 3.50.0 the address bar showed every url the app reported encoded
// twice: '/caf%25C3%25A9' for '/café', so a refresh or a shared link opened
// '/caf%C3%A9' as the literal path 'caf%C3%A9'. auto_route escaped each '%'
// once more for the web engine, which until Flutter 3.50.0 decoded the uri
// before writing it to the browser (flutter/flutter#180373).
//
// The browser's own behavior, which these tests hold to: a path typed into the
// address bar or pushed with history.pushState is stored and shown
// percent-encoded once, per the WHATWG URL standard's path and fragment
// percent-encode sets: 'é' becomes '%C3%A9', a space '%20', and an escape
// already there stays as it is.
void main() {
  useRealBrowserHistory();

  late RootStackRouter router;
  setUp(() async {
    router = RootStackRouter.build(
      routes: [
        AutoRoute(page: FirstRoute.page, path: '/'),
        AutoRoute(page: _CafeRoute.page, path: '/café'),
        AutoRoute(page: _DessertRoute.page, path: '/dessert/:name'),
      ],
    );
    addTearDown(router.dispose);
    await rewindBrowserHistory();
  });

  // Steps: type '/café' into the address bar, then push a page whose path
  // param is '100% crème', then refresh.
  // Should: the address bar shows '/caf%C3%A9', as the browser encodes the
  // typed path, then '/dessert/100%25%20cr%C3%A8me', and the refreshed page
  // reads '100% crème' whole.
  testWidgets('On web, the address bar shows a url encoded once', (
    tester,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);

    await browserMove(tester, () => window.location.hash = '/café');
    expect(find.text('Café'), findsOneWidget);
    expect(browserPath, '/caf%C3%A9');

    unawaited(router.push(_DessertRoute(name: '100% crème')));
    await settleBrowser(tester);
    expect(find.text('100% crème'), findsOneWidget);
    expect(router.urlState.uri.toString(), '/dessert/100%25%20cr%C3%A8me');
    expect(browserPath, '/dessert/100%25%20cr%C3%A8me');

    // A refresh opens the app at the url in the address bar.
    final refreshed = await router.defaultRouteParser().parseRouteInformation(
      RouteInformation(uri: Uri.parse(browserPath)),
    );
    expect(refreshed.topMatch?.params.rawMap, {'name': '100% crème'});
  });

  // Steps: the same push, with the app built from routerDelegate and
  // routeInformationParser, which leaves reporting urls to Flutter's own route
  // information provider.
  // Should: the address bar shows '/dessert/100%25%20cr%C3%A8me'.
  testWidgets(
    "On web, the address bar shows a url encoded once with Flutter's route "
    'information provider',
    (tester) async {
      await pumpRouterApp(tester, router);
      await settleBrowser(tester);

      unawaited(router.push(_DessertRoute(name: '100% crème')));
      await settleBrowser(tester);
      expect(find.text('100% crème'), findsOneWidget);
      expect(browserPath, '/dessert/100%25%20cr%C3%A8me');
    },
  );
}

class _CafeRoute extends PageRouteInfo<void> {
  const new() : super(pageName);

  static const String pageName = 'CafeRoute';
  static final PageInfo page = PageInfo(
    pageName,
    builder: (_) => const Text('Café'),
  );
}

class _DessertRoute extends PageRouteInfo<void> {
  new({required String name}) : super(pageName, rawPathParams: {'name': name});

  static const String pageName = 'DessertRoute';
  static final PageInfo page = PageInfo(
    pageName,
    builder: (data) => Text(data.params.getString('name')),
  );
}
