// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history entry.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' show window;

// Canary for Flutter bug https://github.com/flutter/flutter/issues/108697: on
// the web, an app started again on a browser entry gets none of the state it
// saved there. The browser keeps an entry's state across a reload and when
// the user comes back to the entry from another site (history.state, in the
// HTML standard's session history), so the app could read it.
// Setup, without auto_route: the reporter's app, WidgetsApp.router with a
// RouteInformationParser and a RouterDelegate, so Flutter makes the default
// PlatformRouteInformationProvider.
// Steps: make the browser's current entry hold '/changed' with the state the
// engine keeps for an app, {serialCount: 1, state: {changed: ''}}, as the
// app's own navigation left it, then start the app there, as the browser
// does after a reload or a back from another site.
// Today, on Flutter 3.50.0 (and 3.47.9): parseRouteInformation gets the url
// with a null state, though the entry still holds it. The same happens on a
// real reload of a built app; its first report then writes null over the
// state in the entry. WidgetsApp starts the provider with
// `RouteInformation(uri: Uri.parse(_initialRouteName))` and no state: flutter
// lib/src/widgets/app.dart:1504, and the provider's `_valueInEngine` in
// lib/src/widgets/router.dart:1548.
// auto_route reads the entry's state itself when its route information
// provider starts: `browserEntryState()` in
// lib/src/router/provider/browser_entry_state_web.dart, used by
// lib/src/router/provider/auto_route_information_provider.dart. If this test
// fails after a Flutter upgrade, Flutter fixed the bug: drop
// browserEntryState and its two uses, check that
// test/web/state_after_reload_web_test.dart still passes in Chrome, and drop
// this canary.
class _Delegate extends RouterDelegate<RouteInformation> with ChangeNotifier {
  final parsed = <RouteInformation>[];

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  Future<bool> popRoute() => SynchronousFuture(true);

  @override
  Future<void> setNewRoutePath(RouteInformation configuration) {
    parsed.add(configuration);
    return SynchronousFuture(null);
  }
}

class _Parser extends RouteInformationParser<RouteInformation> {
  const new();

  @override
  Future<RouteInformation> parseRouteInformation(
    RouteInformation routeInformation,
  ) => SynchronousFuture(routeInformation);

  @override
  RouteInformation restoreRouteInformation(RouteInformation configuration) =>
      configuration;
}

void main() {
  testWidgets(
    'an app started on a browser entry gets none of the state saved there, '
    'until Flutter fixes flutter/flutter#108697',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
      dispatcher.defaultRouteNameTestValue = '/changed';
      final entry = {
        'serialCount': 1,
        'state': {'changed': ''},
      };
      window.history.replaceState(entry.jsify(), '', '#/changed');
      addTearDown(() => window.history.replaceState(null, '', '#/'));
      final delegate = _Delegate();
      addTearDown(delegate.dispose);

      await tester.pumpWidget(
        WidgetsApp.router(
          color: const Color(0xFF000000),
          routerDelegate: delegate,
          routeInformationParser: const _Parser(),
        ),
      );

      expect(delegate.parsed.map((parsed) => (parsed.uri.path, parsed.state)), [
        ('/changed', null),
      ]);
      expect(window.history.state.dartify(), entry);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
