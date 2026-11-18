// Off the web only: on the web, the browser's own history holds the entries.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, a link into a page of the nested router of another tab adds
// one entry to the app's own history (callmephil/auto_route_library#22).
//
// Steps: on Home, open Tabs on tab One, then select Two and One again. Each
// tab holds a nested router with an Index page and a Detail page. The
// platform hands the app /tabs/two/detail. Then call back() until the
// history has no step back.
// Was: the link added two entries. The page TwoIndex showed for no frame
// and got an entry of its own under TwoDetail. The change to tab Two
// reported the url of its first page before the link's page went on, and
// the app's history took it as a navigation. back() went from TwoDetail to
// TwoIndex.
// Should: one entry for the link, so back() goes from TwoDetail to One, the
// page shown before the link.
//
// Native behavior this holds to: a link is one navigation, and one
// navigation adds one step back. Android's back stack: each
// NavController.navigate() pushes one destination, and back pops it
// (developer.android.com/guide/navigation/backstack). Flutter's
// Navigator.push puts one route on, and pop takes it off. The same rule is
// pinned for plain tabs in back_after_link_to_other_tab_test.dart. The web
// side of this cause runs in forward_after_tabs_page_closes_test.dart.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => NamedPage(name));

// A tab at [path] whose nested router holds an Index page and a Detail page.
NamedRouteDef _tab(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => const AutoRouter(),
  children: [_page('${name}Index', ''), _page('${name}Detail', 'detail')],
);

RootStackRouter _router() => .build(
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Tabs',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('One'), NamedRoute<Object?>('Two')],
        ),
      ),
      children: [_tab('One', 'one'), _tab('Two', 'two')],
    ),
  ],
);

void main() {
  testWidgets('a link into a page of another tab adds one entry', (
    tester,
  ) async {
    final root = _router();
    await pumpRouterConfigApp(tester, root.config());
    unawaited(root.push(const NamedRoute<Object?>('Tabs')));
    await tester.pumpAndSettle();
    final tabs = root.innerRouterOf<TabsRouter>('Tabs')!;
    for (final index in [1, 0]) {
      tabs.setActiveIndex(index);
      await tester.pumpAndSettle();
    }
    final entriesBefore = root.navigationHistory.length;

    await tester.binding.handlePushRoute('/tabs/two/detail');
    await tester.pumpAndSettle();

    expect(root.topRoute.name, 'TwoDetail');
    expect((entriesBefore, root.navigationHistory.length), (4, 5));
    final urls = [root.currentUrl];
    for (var i = 0; i < 8 && root.navigationHistory.canNavigateBack; i++) {
      root.back();
      await tester.pumpAndSettle();
      urls.add(root.currentUrl);
    }
    expect(urls, [
      '/tabs/two/detail',
      '/tabs/one',
      '/tabs/two',
      '/tabs/one',
      '/',
    ]);
  });
}
