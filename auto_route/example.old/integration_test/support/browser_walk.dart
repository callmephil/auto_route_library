import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

/// A router with a Home page at '/' and pages A to D at '/a' to '/d', each
/// showing its name.
RootStackRouter buildWalkRouter() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

/// Presses the browser's back button once for each page in [pages] and
/// expects, after each press, that page on top of [router] with its url in
/// the address bar, on the entry one before the last.
///
/// [pages] are the page names and urls the back button shows in turn, such
/// as `[('ARoute', '/a'), ('HomeRoute', '/')]`.
Future<void> expectBrowserBackWalk(
  WidgetTester tester,
  RootStackRouter router,
  List<(String, String)> pages,
) async {
  for (final (name, url) in pages) {
    final entry = browserEntryIndex()!;
    pressBrowserBack();
    await expectBrowserEntry(entry - 1);
    await tester.pumpAndSettle();
    await expectBrowserUrl(url);
    expect(router.topRoute.name, name, reason: 'after the back to $url');
  }
}
