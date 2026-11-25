// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, a jump forward over several entries, as from the list a long
// press on the forward button shows, opens the page of each entry it passes,
// in order, as forward presses do, and changes no entry
// (callmephil/auto_route_library#41). Back then shows those pages again.
//
// Was: the app opened only the page of the entry landed on, over the page
// shown before: it stepped the browser back and pushed that url, which
// dropped the entries between and ahead, so back showed the page before.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.go(3) goes three entries forward and adds or changes no entry.

// The user is signed out until it completes: the guard of A shows Login.
Completer<void>? _signingIn;

// Whether a page B or Login built from now on refuses a pop.
var _bRefusesPop = false;
var _loginRefusesPop = false;

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'ARoute',
      path: '/a',
      guards: [
        AutoRouteGuard.simple((resolver, _) async {
          if (_signingIn case final signingIn?) {
            unawaited(
              resolver.redirectUntil(const NamedRoute<Object?>('LoginRoute')),
            );
            await signingIn.future;
          }
          resolver.next();
        }),
      ],
      builder: (_, _) => const Text('ARoute'),
    ),
    NamedRouteDef(
      name: 'BRoute',
      path: '/b',
      builder: (_, _) =>
          PopScope(canPop: !_bRefusesPop, child: const Text('BRoute')),
    ),
    NamedRouteDef(
      name: 'LoginRoute',
      path: '/login',
      builder: (_, _) =>
          PopScope(canPop: !_loginRefusesPop, child: const Text('LoginRoute')),
    ),
    for (final (name, path) in [
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('RegisterRoute', '/register'),
    ])
      _page(name, path),
  ],
);

List<String?> _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name).toList();

// The stack, the browser's serial count from [home], its path and its length.
(String, int, String, int) _where(RootStackRouter router, int home) => (
  _stack(router).join(' '),
  browserSerialCount - home,
  browserPath,
  browserEntryCount,
);

// Hands [location] over as url_launcher's Link does on the web: the engine
// gets the url first, and pushes an entry for it, then the framework.
Future<ByteData?> _followLink(String location) {
  final replied = Completer<ByteData?>();
  unawaited(SystemNavigator.routeInformationUpdated(uri: Uri.parse(location)));
  ui.channelBuffers.push(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    replied.complete,
  );
  return replied.future;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  tearDown(() {
    _signingIn = null;
    _bRefusesPop = false;
    _loginRefusesPop = false;
  });

  // Opens A, B and C over Home, and returns the serial count of Home.
  Future<int> openABC(WidgetTester tester, RootStackRouter router) async {
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    for (final name in ['ARoute', 'BRoute', 'CRoute']) {
      unawaited(router.push(NamedRoute(name)));
      await settleBrowser(tester);
    }
    return home;
  }

  // Steps: open A, B and C over Home, call popUntilRoot, then go three
  // entries forward at once and press the back button.
  testWidgets('On web, a jump forward over several entries opens the page '
      'of each entry it passes, and back then shows the one before', (
    tester,
  ) async {
    final router = _router();
    final home = await openABC(tester, router);
    router.popUntilRoot();
    await settleBrowser(tester);

    await browserMove(tester, () => window.history.go(3));
    expect(_stack(router), ['HomeRoute', 'ARoute', 'BRoute', 'CRoute']);
    expect((browserSerialCount - home, browserPath), (3, '/c'));

    await pressBrowserBack(tester);
    expect(_stack(router), ['HomeRoute', 'ARoute', 'BRoute']);
    expect((browserSerialCount - home, browserPath), (2, '/b'));
  });

  // Opens A, B and C over Home, presses back three times and signs out, then
  // goes three entries forward at once, or presses forward once: Login shows
  // in place of A.
  Future<(int, int)> onLogin(
    WidgetTester tester,
    RootStackRouter router, {
    bool jumps = true,
    bool bRefusesPop = false,
    bool loginRefusesPop = false,
  }) async {
    final home = await openABC(tester, router);
    final length = browserEntryCount;
    for (var i = 0; i < 3; i++) {
      await pressBrowserBack(tester);
    }
    _signingIn = Completer<void>();
    _bRefusesPop = bRefusesPop;
    _loginRefusesPop = loginRefusesPop;

    if (jumps) {
      await browserMove(tester, () => window.history.go(3));
    } else {
      await pressBrowserForward(tester);
    }
    expect(_where(router, home), (
      'HomeRoute LoginRoute',
      jumps ? 3 : 1,
      jumps ? '/c' : '/login',
      length,
    ));
    return (home, length);
  }

  // Steps: the jump onto C, then back two times. Should: B over Login with
  // the entry of C ahead, then Login, which writes /login over the entry of
  // A; no entry is added or dropped.
  testWidgets('On web, back while a passed entry shows its sign-in page '
      'keeps the entries ahead', (tester) async {
    final router = _router();
    final (home, length) = await onLogin(tester, router);

    await pressBrowserBack(tester);
    expect(_where(router, home), (
      'HomeRoute LoginRoute BRoute',
      2,
      '/b',
      length,
    ));

    await pressBrowserBack(tester);
    expect(_where(router, home), ('HomeRoute LoginRoute', 1, '/login', length));
  });

  // Steps: the jump onto C, with B refusing a pop; back onto B, then back
  // again. Should: B stays on its entry. Native behavior this holds to:
  // Flutter's Navigator, where a PopScope with canPop false keeps its page.
  testWidgets('On web, a back that B refuses after a jump keeps every '
      'entry', (tester) async {
    final router = _router();
    final (home, length) = await onLogin(tester, router, bRefusesPop: true);
    final afterBacks = <(String, int, String, int)>[];
    for (var i = 0; i < 2; i++) {
      await pressBrowserBack(tester);
      afterBacks.add(_where(router, home));
    }

    const onB = ('HomeRoute LoginRoute BRoute', 2, '/b');
    final onBEntry = (onB.$1, onB.$2, onB.$3, length);
    expect(afterBacks, [onBEntry, onBEntry]);
  });

  // Steps: the jump onto C; Register takes the place of Login, as a link to
  // sign up does, then back. Should: B over Register on the entry of B.
  testWidgets('On web, a page that replaces Login after a jump keeps every '
      'entry', (tester) async {
    final router = _router();
    final (home, length) = await onLogin(tester, router);
    unawaited(router.replace(const NamedRoute<Object?>('RegisterRoute')));
    await settleBrowser(tester);

    await pressBrowserBack(tester);
    expect(_where(router, home), (
      'HomeRoute RegisterRoute BRoute',
      2,
      '/b',
      length,
    ));
  });

  String after(bool jumps) => jumps ? 'after a jump' : 'after a forward press';

  // Steps: the jump onto C, or one forward press onto A, with Login refusing
  // a pop; then go back onto Home, three entries or one. Should: the browser
  // goes back to the entry of Login, and no entry is added or dropped.
  // Native behavior this holds to: Flutter's Navigator, where a PopScope with
  // canPop false keeps its page.
  for (final jumps in [true, false]) {
    testWidgets('On web, ${after(jumps)}, a step back that Login refuses '
        'returns the browser to its entry', (tester) async {
      final router = _router();
      final (home, length) = await onLogin(
        tester,
        router,
        jumps: jumps,
        loginRefusesPop: true,
      );

      await browserMove(tester, () => window.history.go(jumps ? -3 : -1));
      expect(_where(router, home), (
        'HomeRoute LoginRoute',
        1,
        '/login',
        length,
      ));
    });
  }

  // Steps: the jump onto C, or one forward press onto A; popAndPush of
  // Register over Login, then back. Should: Register on the entry after
  // Home's, which drops the entries ahead, and back shows Home.
  // Native behavior this holds to: the HTML standard's history.pushState,
  // which drops the entries ahead.
  for (final jumps in [true, false]) {
    testWidgets('On web, ${after(jumps)}, popAndPush of Register over Login '
        'writes the browser', (tester) async {
      final router = _router();
      final (home, length) = await onLogin(tester, router, jumps: jumps);
      unawaited(router.popAndPush(const NamedRoute<Object?>('RegisterRoute')));
      await settleBrowser(tester);
      expect(_where(router, home), (
        'HomeRoute RegisterRoute',
        1,
        '/register',
        length - 2,
      ));

      await pressBrowserBack(tester);
      expect(_where(router, home), ('HomeRoute', 0, '/', length - 2));
    });
  }

  // Steps: open A, B, C and D over Home, press back three times, and reload
  // on A. Press forward two times, back two times, then go three entries
  // forward onto D, which the new app has not stood on, or press forward
  // three times. Should: A, B, C and D on their entries; back shows C.
  for (final jumps in [true, false]) {
    testWidgets('On web, after a reload, every entry stays after '
        '${jumps ? 'history.go(3)' : 'forward presses'} onto an entry from '
        'before it', (tester) async {
      final [first, router] = [for (var i = 0; i < 2; i++) _router()];
      addTearDown(router.dispose);
      final home = await openABC(tester, first);
      unawaited(first.push(const NamedRoute<Object?>('DRoute')));
      await settleBrowser(tester);
      for (var i = 0; i < 3; i++) {
        await pressBrowserBack(tester);
      }
      final length = browserEntryCount;
      await tester.pumpWidget(const SizedBox());
      await settleBrowser(tester);
      first.dispose();
      openBrowserAt(tester, '/a');
      await pumpAsRunApp(
        tester,
        MaterialApp.router(routerConfig: router.config()),
      );
      for (final press in [
        pressBrowserForward,
        pressBrowserForward,
        pressBrowserBack,
        pressBrowserBack,
      ]) {
        await press(tester);
      }
      expect(_where(router, home), ('ARoute', 1, '/a', length));

      if (jumps) {
        await browserMove(tester, () => window.history.go(3));
      } else {
        for (var i = 0; i < 3; i++) {
          await pressBrowserForward(tester);
        }
      }
      expect(_where(router, home), (
        'ARoute BRoute CRoute DRoute',
        4,
        '/d',
        length,
      ));
      await pressBrowserBack(tester);
      expect(_where(router, home), ('ARoute BRoute CRoute', 3, '/c', length));
    });
  }

  // Steps: open A, B and C over Home, press back and forward. Call
  // popUntilRoot and follow a link to D in the same turn, as a tap on
  // url_launcher's Link does. Should: D over Home alone, and back shows Home
  // with the entry of D ahead. Native behavior this holds to: Flutter's
  // Navigator, where a popped page stays closed.
  testWidgets('On web, a link in the turn of popUntilRoot opens its page '
      'over Home alone', (tester) async {
    final router = _router();
    final home = await openABC(tester, router);
    await pressBrowserBack(tester);
    await pressBrowserForward(tester);
    // The browser's entries from the app's first: /, /a, /b and /c.
    final twoEntries = browserEntryCount - 2;

    router.popUntilRoot();
    unawaited(_followLink('/d'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await settleBrowser(tester);
    expect(_where(router, home), ('HomeRoute DRoute', 1, '/d', twoEntries));

    await pressBrowserBack(tester);
    expect(_where(router, home), ('HomeRoute', 0, '/', twoEntries));
  });
}
