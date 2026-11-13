import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A fragment given to a child route reaches the url and the page when the
// child is opened with its parent.
// Steps: '/help' has the children '' and 'docs'. The app runs on '/'. Push
// the docs page with its parent and a fragment, the way the README opens a
// nested route: `HelpRoute(children: [DocsRoute(fragment: 'faq')])`.
// Was: the url was /help/docs, without #faq, and the page's
// RouteData.fragment was empty: the matcher handed the parent's fragment to
// each child, and the parent's was '', which took the place of the child's
// own. Found by the second audit (U2-4).
// Controls: the link /help/docs#faq, the same route pushed inside the open
// nested router, and a fragment given to the parent all keep '#faq'.
// Native behavior this holds to: a url has one fragment, and it belongs to
// the document that is shown (RFC 3986 section 3.5): with
// history.pushState('/help/docs#faq') the browser keeps the fragment
// whatever frames the page is nested in.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'HelpRoute',
      path: '/help',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'HelpHomeRoute',
          path: '',
          builder: (_, _) => const Text('HelpHomeRoute'),
        ),
        NamedRouteDef(
          name: 'DocsRoute',
          path: 'docs',
          builder: (_, data) => Text('Docs at [${data.fragment}]'),
        ),
      ],
    ),
  ],
);

// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> _sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

void main() {
  testWidgets('Control: the link /help/docs#faq keeps its fragment', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await _sendPlatformLink(tester, '/help/docs#faq');
    await tester.pumpAndSettle();
    expect(find.text('Docs at [faq]'), findsOneWidget);
    expect(router.currentUrl, '/help/docs#faq');
  });

  testWidgets('Control: pushed inside the open nested router, the docs page '
      'keeps its fragment', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('HelpRoute')));
    await tester.pumpAndSettle();
    expect(find.text('HelpHomeRoute'), findsOneWidget);
    final nested = router.innerRouterOf<StackRouter>('HelpRoute')!;
    unawaited(nested.push(const NamedRoute('DocsRoute', fragment: 'faq')));
    await tester.pumpAndSettle();
    expect(find.text('Docs at [faq]'), findsOneWidget);
    expect(router.currentUrl, '/help/docs#faq');
  });

  testWidgets('Control: a fragment given to the parent reaches the url', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute(
          'HelpRoute',
          children: [NamedRoute('DocsRoute')],
          fragment: 'faq',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Docs at [faq]'), findsOneWidget);
    expect(router.currentUrl, '/help/docs#faq');
  });

  testWidgets('A fragment given to the child, pushed with its parent, '
      'reaches the url and the page', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute(
          'HelpRoute',
          children: [NamedRoute('DocsRoute', fragment: 'faq')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/help/docs#faq');
    expect(find.text('Docs at [faq]'), findsOneWidget);
  });

  test('The matcher keeps the fragment of a child route', () {
    final router = _router();
    addTearDown(router.dispose);
    final match = router.matcher.matchByRoute(
      const NamedRoute(
        'HelpRoute',
        children: [NamedRoute('DocsRoute', fragment: 'faq')],
      ),
    );
    expect(match?.children?.lastOrNull?.fragment, 'faq');
  });
}
