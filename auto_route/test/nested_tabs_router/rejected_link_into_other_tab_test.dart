import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the second audit of auto_route/lib (T2-3); on dev too, no
// upstream issue.
// A link to a page inside a tab other than the one on screen, which that
// page's guard rejects, still switched the tab and closed the dialog the
// user had open: the tabs router ran the link's accepted step once the
// tab's own guards let it in, switched the tab and only then asked the
// tab's nested router. The tab now shows once the guards in its nested
// router let the link in. A tab whose nested router is not built yet is
// built offstage first, on its first page, and then asked.
// Steps: TabsRoute at '/tabs' with tabs [FirstTab, MailTab]; MailTab holds
// a nested router with InboxRoute ('') and MessageRoute (':id'), whose guard
// rejects message 13. The app shows FirstTab with a dialog open, such as an
// unsaved draft, with MailTab opened before or never. The platform hands it
// the link '/tabs/mail/13', as a notification does; or '/tabs/mail/7',
// which the app lets in.
// Native behavior this holds to: a navigation that is refused changes
// nothing. On the web a canceled navigation leaves the document, the url and
// an open <dialog> as they were; on Android an activity that ignores the
// link in onNewIntent keeps its dialogs and its selected tab; on iOS an app
// that cannot open a link returns false from application(_:open:options:),
// and what it then keeps on screen is this package's own rule.
void main() {
  for (final kind in _TabsKind.values) {
    group(kind.name, () {
      for (final wasMailOpened in [true, false]) {
        final mail = wasMailOpened ? 'opened before' : 'never opened';

        testWidgets('A link to a page in another tab ($mail) that its guard '
            'rejects keeps the tab, the dialog and the url', (tester) async {
          final router = _buildRouter(kind);
          await pumpRouterConfigApp(tester, router.config());
          final tabs = await _openTabs(tester, router, wasMailOpened);
          await _showDraft(tester, router);
          final urlBefore = router.currentUrl;
          expect(urlBefore, '/tabs/first');

          await tester.binding.handlePushRoute('/tabs/mail/13');
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Mail 13'), findsNothing);
          expect(tabs.current.name, 'FirstTab');
          expect(find.text('Unsaved draft'), findsOneWidget);
          expect(router.currentUrl, urlBefore);

          // The tab the link reached shows its first page when opened.
          Navigator.of(tester.element(find.text('Unsaved draft'))).pop();
          tabs.setActiveIndex(1);
          await tester.pumpAndSettle();
          expect(find.text('InboxRoute'), findsOneWidget);
          expect(router.currentUrl, '/tabs/mail');
        });

        testWidgets('A link to a page in another tab ($mail) that is let in '
            'shows it and closes the dialog', (tester) async {
          final router = _buildRouter(kind);
          await pumpRouterConfigApp(tester, router.config());
          final tabs = await _openTabs(tester, router, wasMailOpened);
          await _showDraft(tester, router);

          await tester.binding.handlePushRoute('/tabs/mail/7');
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(tabs.current.name, 'MailTab');
          expect(find.text('Mail 7'), findsOneWidget);
          expect(find.text('Unsaved draft'), findsNothing);
          expect(router.currentUrl, '/tabs/mail/7');
        });
      }

      testWidgets('A link to a page in the tab on screen that its guard '
          'rejects keeps the dialog', (tester) async {
        final router = _buildRouter(kind);
        await pumpRouterConfigApp(tester, router.config());
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        await _showDraft(tester, router);

        await tester.binding.handlePushRoute('/tabs/mail/13');
        await tester.pumpAndSettle();

        expect(tabs.current.name, 'MailTab');
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(router.currentUrl, '/tabs/mail');
      });
    });
  }
}

enum _TabsKind { indexedStack, pageView, tabBar, builder }

// Shows FirstTab, after a visit to MailTab when [wasMailOpened].
Future<TabsRouter> _openTabs(
  WidgetTester tester,
  RootStackRouter router,
  bool wasMailOpened,
) async {
  final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
  if (wasMailOpened) {
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();
  }
  expect(tabs.current.name, 'FirstTab');
  return tabs;
}

Future<void> _showDraft(WidgetTester tester, RootStackRouter router) async {
  showDialog<void>(
    context: router.navigatorKey.currentContext!,
    builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
  );
  await tester.pumpAndSettle();
  expect(find.text('Unsaved draft'), findsOneWidget);
}

Widget _tabsOf(_TabsKind kind) {
  const routes = [NamedRoute('FirstTab'), NamedRoute('MailTab')];
  return switch (kind) {
    .indexedStack => const AutoTabsRouter(routes: routes),
    .pageView => const AutoTabsRouter.pageView(routes: routes),
    .tabBar => const AutoTabsRouter.tabBar(routes: routes),
    .builder => AutoTabsRouter.builder(
      routes: routes,
      builder: (_, children, tabs) =>
          IndexedStack(index: tabs.activeIndex, children: children),
    ),
  };
}

RootStackRouter _buildRouter(_TabsKind kind) => .build(
  routes: [
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      initial: true,
      builder: (_, _) => Scaffold(body: _tabsOf(kind)),
      children: [
        NamedRouteDef(
          name: 'FirstTab',
          path: 'first',
          builder: (_, _) => const Center(child: Text('FirstTab')),
        ),
        NamedRouteDef(
          name: 'MailTab',
          path: 'mail',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'InboxRoute',
              path: '',
              builder: (_, _) => const Center(child: Text('InboxRoute')),
            ),
            NamedRouteDef(
              name: 'MessageRoute',
              path: ':id',
              guards: [
                AutoRouteGuard.simple(
                  (resolver, _) => resolver.route.params.getString('id') == '13'
                      ? resolver.reject()
                      : resolver.next(),
                ),
              ],
              builder: (_, data) =>
                  Center(child: Text('Mail ${data.params.getString('id')}')),
            ),
          ],
        ),
      ],
    ),
  ],
);
