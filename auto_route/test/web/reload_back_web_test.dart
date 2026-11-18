// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, after a reload, the back and forward buttons onto the entries
// from before the reload show the page of each entry, as a link to its url
// does, and never pile pages over the ones open. A shop: Home, then Shoes,
// then the Runner X page, and a reload there. Back opens Shoes alone, back
// again Home alone, and forward walks the same entries to Runner X.
//
// Before, the reloaded app opened the page of an entry from before it over
// the pages it showed: back read Runner X, Shoes, and back again Runner X,
// Shoes, Home, with a back arrow on Home that walked the user's path in
// reverse.
//
// Native behavior this holds to: the HTML standard's session history
// traversal and the History API, as a real Chrome shows for a page that moves
// with history.pushState and is reloaded: each entry keeps only its url and
// its serialized state across the reload, the back button lands on one entry
// and fires a single popstate with that state, and the page shows that entry,
// never the entries after it; the entries ahead stay for the forward button.
// A site of separate pages shows the same: each press shows the one page of
// its entry. Flutter's Router hands the app such an entry as a
// RouteInformation of its url and state.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ShoesRoute', '/shoes'),
      ('RunnerXRoute', '/runner-x'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

// The urls of the browser's entries of this test page, as the Navigation
// API lists them, each by its hash, the current one starred.
String get _browserEntries {
  final navigation = globalContext.getProperty<JSObject>('navigation'.toJS);
  final current = navigation
      .getProperty<JSObject>('currentEntry'.toJS)
      .getProperty<JSNumber>('index'.toJS)
      .toDartInt;
  final entries = navigation
      .callMethod<JSArray<JSObject>>('entries'.toJS)
      .toDart;
  return [
    for (final entry in entries)
      [
        Uri.parse(entry.getProperty<JSString>('url'.toJS).toDart).fragment,
        if (entry.getProperty<JSNumber>('index'.toJS).toDartInt == current) '*',
      ].join(),
  ].join(' ');
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('On web, after a reload, back and forward show the page of '
      'each entry from before it, alone', (tester) async {
    // The app before the reload, Home, Shoes, then Runner X, and the app
    // after it.
    final [first, router] = [for (var i = 0; i < 2; i++) _router()];
    await pumpRouterConfigApp(tester, first.config());
    await settleBrowser(tester);
    for (final name in ['ShoesRoute', 'RunnerXRoute']) {
      unawaited(first.push(NamedRoute(name)));
      await settleBrowser(tester);
    }
    final before = _browserEntries;
    await tester.pumpWidget(const SizedBox());
    await settleBrowser(tester);
    first.dispose();

    // The reload: a new app on the same browser history, on Runner X.
    addTearDown(router.dispose);
    openBrowserAt(tester, '/runner-x');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(routerConfig: router.config()),
    );

    final walk = <String>[];
    void read(String step) => walk.add(
      '$step: $browserPath '
      '${router.stack.map((page) => page.name).join(' ')}',
    );
    read('reload');
    await pressBrowserBack(tester);
    read('back');
    await pressBrowserBack(tester);
    read('back');
    await pressBrowserForward(tester);
    read('forward');
    await pressBrowserForward(tester);
    read('forward');
    printOnFailure('entries before the reload: $before, now: $_browserEntries');

    expect(walk, [
      'reload: /runner-x RunnerXRoute',
      'back: /shoes ShoesRoute',
      'back: / HomeRoute',
      'forward: /shoes HomeRoute ShoesRoute',
      'forward: /runner-x HomeRoute ShoesRoute RunnerXRoute',
    ]);
    // The browser keeps the entries it had: none is written over or lost.
    expect(_browserEntries, before);
  });
}
