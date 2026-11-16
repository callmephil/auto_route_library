import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the links chat, proven in batch 2; on dev too, no upstream issue.
// The app's own navigate or navigatePath to a page inside another tab, which
// that page's guard rejects, still switched to that tab and closed the
// dialog over the tabs: the tabs router showed the tab once the tab's own
// guards had answered, and only then asked the tab's nested router. A link
// waited already. The tab now shows once the guards of its nested router let
// the navigation in, when that router is built, as for a tab opened before.
// A tab never opened has no nested router yet: it shows first, and its
// router asks its guards once it is in.
// Steps: TabsRoute at '/tabs' with tabs [FirstTab, MailTab]; MailTab holds a
// nested router with InboxRoute ('') and MessageRoute (':id'), whose guard
// rejects 13, lets 14 in, and asks about 77 and waits for the test's
// answer. MailTab was opened before; the app shows FirstTab with a dialog
// open. The app navigates to a message in MailTab.
// Native behavior this holds to: a navigation that is refused changes
// nothing. A UITabBarController keeps its selected tab when the app doesn't
// move to the screen asked for, and an Android activity that ignores a
// navigation keeps its selected tab and its dialogs; on the web a canceled
// navigation keeps the document. A guard that asks the user to sign in shows
// its page where the user can answer it: the tab shows with the sign-in page,
// and a cancel leaves it on screen, as a tab bar keeps the tab it shows.
void main() {
  Completer<bool>? slowAnswer;

  setUp(() => slowAnswer = null);

  for (final kind in _TabsKind.values) {
    group(kind.name, () {
      for (final isPath in [false, true]) {
        final how = isPath ? 'navigatePath' : 'navigate';

        Future<(RootStackRouter, TabsRouter)> openFirstTab(
          WidgetTester tester,
        ) async {
          final router = _buildRouter(kind, () {
            final answer = slowAnswer = Completer<bool>();
            return answer.future;
          });
          await pumpRouterConfigApp(tester, router.config());
          final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
            ..setActiveIndex(1);
          await tester.pumpAndSettle();
          tabs.setActiveIndex(0);
          await tester.pumpAndSettle();
          showDialog<void>(
            context: router.navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
          );
          await tester.pumpAndSettle();
          expect(tabs.current.name, 'FirstTab');
          return (router, tabs);
        }

        void go(RootStackRouter router, String id) => unawaited(
          isPath
              ? router.navigatePath('/tabs/mail/$id')
              : router.navigate(
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

        testWidgets('$how to a page in another tab that its guard rejects at '
            'once keeps the tab and the dialog', (tester) async {
          final (router, tabs) = await openFirstTab(tester);

          go(router, '13');
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(tabs.current.name, 'FirstTab');
          expect(find.text('Unsaved draft'), findsOneWidget);
          expect(router.currentUrl, '/tabs/first');
        });

        testWidgets('$how to a page in another tab that its guard lets in at '
            'once shows the tab and closes the dialog', (tester) async {
          final (router, tabs) = await openFirstTab(tester);

          go(router, '14');
          await tester.pumpAndSettle();

          expect(tabs.current.name, 'MailTab');
          expect(find.text('Mail 14'), findsOneWidget);
          expect(find.text('Unsaved draft'), findsNothing);
          expect(router.currentUrl, '/tabs/mail/14');
        });

        for (final isLetIn in [false, true]) {
          testWidgets('$how to a page in another tab whose guard answers '
              'later keeps the tab while it decides, and '
              '${isLetIn ? 'shows the tab once let in' : 'after it rejects'}', (
            tester,
          ) async {
            final (router, tabs) = await openFirstTab(tester);

            go(router, '77');
            await tester.pumpAndSettle();
            expect(tabs.current.name, 'FirstTab');
            expect(find.text('Unsaved draft'), findsOneWidget);

            slowAnswer!.complete(isLetIn);
            await tester.pumpAndSettle();

            expect(tabs.current.name, isLetIn ? 'MailTab' : 'FirstTab');
            expect(
              find.text('Unsaved draft'),
              isLetIn ? findsNothing : findsOneWidget,
            );
            expect(
              router.currentUrl,
              isLetIn ? '/tabs/mail/77' : '/tabs/first',
            );
          });
        }
      }

      // A guard in the tab that shows its own sign-in page there while it
      // waits for the user: the tab shows with it, as the user has to see it
      // to answer it. Signing in shows the message; canceling leaves the tab
      // on screen, on the page under the sign-in page.
      for (final how in ['navigate', 'navigatePath', 'a link']) {
        for (final isSignedIn in [true, false]) {
          testWidgets(
            "$how to a page whose guard shows the tab's own sign-in "
            'page shows the tab with it, and '
            '${isSignedIn ? 'the page once signed in' : 'keeps the tab when canceled'}',
            (tester) async {
              final router = _buildRouter(kind, () {
                final answer = slowAnswer = Completer<bool>();
                return answer.future;
              });
              await pumpRouterConfigApp(tester, router.config());
              final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
                ..setActiveIndex(1);
              await tester.pumpAndSettle();
              tabs.setActiveIndex(0);
              await tester.pumpAndSettle();

              switch (how) {
                case 'navigate':
                  unawaited(
                    router.navigate(
                      const NamedRoute(
                        'TabsRoute',
                        children: [
                          NamedRoute(
                            'MailTab',
                            children: [
                              NamedRoute('MessageRoute', params: {'id': '88'}),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                case 'navigatePath':
                  unawaited(router.navigatePath('/tabs/mail/88'));
                default:
                  await tester.binding.handlePushRoute('/tabs/mail/88');
              }
              await tester.pumpAndSettle();
              expect(tabs.current.name, 'MailTab');
              expect(find.text('MailLoginRoute').hitTestable(), findsOneWidget);

              slowAnswer!.complete(isSignedIn);
              await tester.pumpAndSettle();

              expect(tester.takeException(), isNull);
              // The tab stays on screen either way.
              expect(tabs.activeIndex, 1);
              expect(find.text('MailLoginRoute'), findsNothing);
              if (isSignedIn) {
                expect(find.text('Mail 88'), findsOneWidget);
                expect(router.currentUrl, '/tabs/mail/88');
              } else {
                expect(find.text('InboxRoute'), findsOneWidget);
                expect(router.currentUrl, '/tabs/mail');
              }
            },
          );
        }
      }
    });
  }
}

enum _TabsKind { indexedStack, pageView, tabBar, builder }

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

// [slowAnswer] gives the answer for message 77, and for 88 once its guard
// has shown Mail's own sign-in page.
RootStackRouter _buildRouter(
  _TabsKind kind,
  Future<bool> Function() slowAnswer,
) => .build(
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
              name: 'MailLoginRoute',
              path: 'login',
              builder: (_, _) => const Center(child: Text('MailLoginRoute')),
            ),
            NamedRouteDef(
              name: 'MessageRoute',
              path: ':id',
              guards: [
                AutoRouteGuard.simple((resolver, router) async {
                  switch (resolver.route.params.getString('id')) {
                    case '13':
                      return resolver.reject();
                    case '77':
                      return await slowAnswer()
                          ? resolver.next()
                          : resolver.reject();
                    case '88':
                      // Mail's own sign-in page, on Mail's router.
                      unawaited(
                        router.push(const NamedRoute('MailLoginRoute')),
                      );
                      final isSignedIn = await slowAnswer();
                      router.removeWhere(
                        (data) => data.name == 'MailLoginRoute',
                      );
                      return isSignedIn ? resolver.next() : resolver.reject();
                  }
                  resolver.next();
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
