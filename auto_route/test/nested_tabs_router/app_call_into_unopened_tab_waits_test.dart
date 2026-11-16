import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The app's own navigate or navigatePath into a tab never opened, to a page
// whose guard says no, switched to that tab, which stayed on its first page.
// A link already waited off the screen for the guard and kept the user's
// tab.
// Setup: the tabs at /tabs show FirstTab. MailTab holds a nested router
// with Inbox as its first page and Message by id. The guard of Message
// rejects message 13 at once, and decides about message 77 only when the
// test answers. Each kind of tabs widget.
// Steps: the app calls navigatePath or navigate to a message in MailTab.
// MailTab was never opened.
// Was: MailTab on Inbox, at its url, for the indexed stack, the page view
// and the tab bar.
// Should: FirstTab stays on screen, at its url, while the guard decides
// and after a no. A yes shows the message in MailTab.
// Native behavior this holds to: UITabBarController changes its tab when
// selectedViewController or selectedIndex is assigned (Apple docs); that a
// link or a refused call leaves the tab as it is, on iOS and in an Android
// bottom bar, is this package's own rule, since no source covers it. On the
// web a canceled navigation leaves the document on screen (HTML standard,
// navigate event).
enum _Tabs { indexedStack, pageView, tabBar, builder }

enum _Way { navigatePath, navigate }

enum _Answer { rejectsAtOnce, waitsThenNo, waitsThenYes }

Completer<bool>? _slow;

Widget _tabsOf(_Tabs kind) {
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

RootStackRouter _build(_Tabs kind) => .build(
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
                AutoRouteGuard.simple((resolver, _) async {
                  if (resolver.route.params.getString('id') == '13') {
                    return resolver.reject();
                  }
                  final answer = _slow = Completer<bool>();
                  await answer.future ? resolver.next() : resolver.reject();
                }),
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

String _shown() => [
  for (final name in ['FirstTab', 'InboxRoute', 'Mail 13', 'Mail 77'])
    if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
].join(',');

void main() {
  setUp(() => _slow = null);

  for (final kind in _Tabs.values) {
    for (final way in _Way.values) {
      for (final answer in _Answer.values) {
        final id = answer == .rejectsAtOnce ? '13' : '77';
        testWidgets('${kind.name}, ${way.name} to message $id in the tab '
            'never opened, ${answer.name}', (tester) async {
          final router = _build(kind);
          await pumpRouterConfigApp(tester, router.config());
          final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;

          switch (way) {
            case .navigatePath:
              unawaited(router.navigatePath('/tabs/mail/$id'));
            case .navigate:
              unawaited(
                router.navigate(
                  NamedRoute(
                    'TabsRoute',
                    children: [
                      NamedRoute(
                        'MailTab',
                        children: [
                          NamedRoute('MessageRoute', params: {'id': id}),
                        ],
                      ),
                    ],
                  ),
                ),
              );
          }
          await tester.pumpAndSettle();
          if (answer != .rejectsAtOnce) {
            expect(_slow?.isCompleted, isFalse, reason: 'the guard waits');
            expect(
              (tabs.current.name, _shown(), router.currentUrl),
              ('FirstTab', 'FirstTab', '/tabs/first'),
              reason: 'while it decides',
            );
            _slow!.complete(answer == .waitsThenYes);
            await tester.pumpAndSettle();
          }

          expect(tester.takeException(), isNull);
          if (answer == .waitsThenYes) {
            expect(tabs.current.name, 'MailTab');
            expect(_shown(), 'Mail 77');
            expect(router.currentUrl, '/tabs/mail/77');
            return;
          }
          expect(find.text('Mail 13', skipOffstage: false), findsNothing);
          expect(tabs.current.name, 'FirstTab');
          expect(_shown(), 'FirstTab');
          expect(router.currentUrl, '/tabs/first');
        });
      }
    }
  }
}
