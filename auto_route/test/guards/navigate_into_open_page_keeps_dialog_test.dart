import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the links chat while fixing a link turned down inside another
// tab. On dev too, with no upstream issue.
// The app's own navigate into a page already open closed the dialogs over
// that page before the guards of its nested router had answered: the root
// closed them as soon as it had reached the page, and the nested router
// asked its guards after. So a navigation those guards rejected still closed
// the dialog, such as an unsaved draft, and while a slow guard decided the
// dialog was already gone. A link's dialogs wait already. The dialogs now
// close once the nested guards let the navigation in, also two routers deep.
// A nested router not built yet asks its guards only once its page is in, so
// there the dialogs still close first. navigatePath with an absolute path
// goes straight to the nested router and leaves the dialogs over the page
// open, let in or not, as on dev: an app closes them itself, as a dialog's
// button that navigates and then pops its dialog does.
// Steps: Mail is open on message 42, with a dialog over it. The app calls
// navigate or navigatePath to a message whose guard rejects it or lets it
// in, at once or after a request. The same one router deeper: Mail's folder,
// itself a nested router, holds the messages.
// Native behavior this holds to: a navigation that is refused changes
// nothing, as on the web a canceled navigation keeps the document, an open
// <dialog> included, and as on iOS and Android a screen that isn't shown
// leaves the one presented on top. One let in pops until its page, as
// Flutter's Navigator.popUntil pops the dialogs above the route it stops at.
void main() {
  Completer<bool>? slowAnswer;

  // Rejects 13 and lets 14 in, both at once; asks about 77 and lets the test
  // answer.
  final messageGuard = AutoRouteGuard.simple((resolver, _) async {
    switch (resolver.route.params.getString('id')) {
      case '13':
        return resolver.reject();
      case '77':
        final answer = slowAnswer = Completer<bool>();
        return await answer.future ? resolver.next() : resolver.reject();
    }
    resolver.next();
  });

  NamedRouteDef message(String name) => .new(
    name: name,
    path: ':id',
    guards: [messageGuard],
    builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
  );

  RootStackRouter build() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
      ),
      NamedRouteDef(
        name: 'SettingsRoute',
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('SettingsRoute')),
      ),
      NamedRouteDef(
        name: 'MailRoute',
        path: '/mail',
        builder: (_, _) => const Scaffold(body: AutoRouter()),
        children: [
          NamedRouteDef(
            name: 'FolderRoute',
            path: 'folder',
            builder: (_, _) => const AutoRouter(),
            children: [message('FolderMessageRoute')],
          ),
          message('MessageRoute'),
        ],
      ),
    ],
  );

  setUp(() => slowAnswer = null);

  for (final isDeeper in [false, true]) {
    final where = isDeeper ? 'in a nested router' : 'in a stack';
    final prefix = isDeeper ? '/mail/folder' : '/mail';

    PageRouteInfo<Object?> routeTo(String id) {
      final page = NamedRoute(
        isDeeper ? 'FolderMessageRoute' : 'MessageRoute',
        params: {'id': id},
      );
      return NamedRoute(
        'MailRoute',
        children: [
          if (isDeeper) NamedRoute('FolderRoute', children: [page]) else page,
        ],
      );
    }

    for (final isPath in [false, true]) {
      final how = isPath ? 'navigatePath' : 'navigate';

      Future<RootStackRouter> openWithDialog(WidgetTester tester) async {
        final router = build();
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.navigatePath('$prefix/42'));
        await tester.pumpAndSettle();
        expect(find.text('Mail 42'), findsOneWidget);
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unsaved draft'), findsOneWidget);
        return router;
      }

      void go(RootStackRouter router, String id) => unawaited(
        isPath
            ? router.navigatePath('$prefix/$id')
            : router.navigate(routeTo(id)),
      );

      testWidgets('$how $where to a page a guard rejects at once keeps the '
          'dialog', (tester) async {
        final router = await openWithDialog(tester);

        go(router, '13');
        await tester.pumpAndSettle();

        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('Mail 13'), findsNothing);
        expect(router.currentUrl, '$prefix/42');
      });

      testWidgets('$how $where to a page a guard lets in at once '
          '${isPath ? 'leaves the dialog open' : 'closes the dialog'}', (
        tester,
      ) async {
        final router = await openWithDialog(tester);

        go(router, '14');
        await tester.pumpAndSettle();

        expect(
          find.text('Unsaved draft'),
          isPath ? findsOneWidget : findsNothing,
        );
        expect(find.text('Mail 14', skipOffstage: false), findsOneWidget);
        expect(router.currentUrl, '$prefix/14');
      });

      // The dialog's own button navigates and then pops its dialog, in one
      // handler: the pop closes the dialog, not the page under it.
      testWidgets('$how $where from a dialog that then pops itself ends on '
          'the page it opened', (tester) async {
        final router = await openWithDialog(tester);
        final dialog = tester.element(find.text('Unsaved draft'));

        go(router, '14');
        Navigator.of(dialog).pop();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.stack.map((page) => page.routeData.name), [
          'HomeRoute',
          'MailRoute',
        ]);
        expect(find.text('Unsaved draft'), findsNothing);
        expect(find.text('Mail 14'), findsOneWidget);
      });

      for (final isLetIn in [false, true]) {
        final keeps = isLetIn && isPath;
        testWidgets(
          '$how $where to a page whose guard answers later keeps the '
          'dialog while it decides, and '
          '${isLetIn ? (keeps ? 'after it lets the page in' : 'closes it once let in') : 'after it rejects'}',
          (tester) async {
            final router = await openWithDialog(tester);

            go(router, '77');
            await tester.pumpAndSettle();
            expect(find.text('Unsaved draft'), findsOneWidget);

            slowAnswer!.complete(isLetIn);
            await tester.pumpAndSettle();

            expect(
              find.text('Unsaved draft'),
              isLetIn && !keeps ? findsNothing : findsOneWidget,
            );
            expect(
              find.text('Mail 77', skipOffstage: false),
              isLetIn ? findsOneWidget : findsNothing,
            );
          },
        );
      }
    }
  }

  // Found by the review of batch 2: the closing waits for the nested
  // guards, and it closed the dialogs over whatever page was on top by then.
  // Steps: Mail is open on message 42. The app calls navigate or
  // navigatePath to message 77, or a link to it comes, and its guard takes
  // its time. Meanwhile the app pushes Settings and shows a dialog over it.
  // The guard lets 77 in.
  // Should: the dialog over Settings stays: the navigation closes only what
  // was over the page it reached.
  for (final how in ['navigate', 'navigatePath', 'a link']) {
    testWidgets('$how let in after a page and a dialog opened over the page it '
        'reached keeps that dialog', (tester) async {
      final router = build();
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.navigatePath('/mail/42'));
      await tester.pumpAndSettle();

      switch (how) {
        case 'navigate':
          unawaited(
            router.navigate(
              const NamedRoute(
                'MailRoute',
                children: [
                  NamedRoute('MessageRoute', params: {'id': '77'}),
                ],
              ),
            ),
          );
        case 'navigatePath':
          unawaited(router.navigatePath('/mail/77'));
        default:
          await tester.binding.handlePushRoute('/mail/77');
      }
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Leave settings?')),
      );
      await tester.pumpAndSettle();

      slowAnswer!.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('Leave settings?'), findsOneWidget);
      expect(router.topRoute.name, 'SettingsRoute');
    });
  }

  testWidgets('navigate to the open page with no children closes the dialog '
      'at once', (tester) async {
    final router = build();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.navigatePath('/mail/42'));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
    );
    await tester.pumpAndSettle();

    unawaited(router.navigate(const NamedRoute('MailRoute')));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved draft'), findsNothing);
  });

  // Into a page of a tab's nested router, with the dialog over the tabs page
  // at the root, and one router deeper. An absolute path stops at the tabs
  // router on its way down, so the root navigates, as for navigate. The
  // dialog over the tabs closes once the guards inside the tab let the
  // navigation in.
  group('in a tab', () {
    RootStackRouter buildTabs() => .build(
      routes: [
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/tabs',
          initial: true,
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [NamedRoute('FirstTab'), NamedRoute('MailTab')],
            ),
          ),
          children: [
            NamedRouteDef(
              name: 'FirstTab',
              path: 'first',
              builder: (_, _) => const Text('FirstTab'),
            ),
            NamedRouteDef(
              name: 'MailTab',
              path: 'mail',
              builder: (_, _) => const AutoRouter(),
              children: [
                NamedRouteDef(
                  name: 'FolderRoute',
                  path: 'folder',
                  builder: (_, _) => const AutoRouter(),
                  children: [message('FolderMessageRoute')],
                ),
                message('MessageRoute'),
              ],
            ),
          ],
        ),
      ],
    );

    for (final isDeeper in [false, true]) {
      final prefix = isDeeper ? '/tabs/mail/folder' : '/tabs/mail';
      for (final isPath in [false, true]) {
        final how = isPath ? 'navigatePath' : 'navigate';
        final inTab =
            'a page of the tab${isDeeper ? ' one router deeper' : ''}';

        Future<RootStackRouter> openWithDialog(WidgetTester tester) async {
          final router = buildTabs();
          await pumpRouterConfigApp(tester, router.config());
          unawaited(router.navigatePath('$prefix/42'));
          await tester.pumpAndSettle();
          showDialog<void>(
            context: router.navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
          );
          await tester.pumpAndSettle();
          return router;
        }

        void go(RootStackRouter router, String id) {
          final page = NamedRoute(
            isDeeper ? 'FolderMessageRoute' : 'MessageRoute',
            params: {'id': id},
          );
          unawaited(
            isPath
                ? router.navigatePath('$prefix/$id')
                : router.navigate(
                    NamedRoute(
                      'TabsRoute',
                      children: [
                        NamedRoute(
                          'MailTab',
                          children: [
                            if (isDeeper)
                              NamedRoute('FolderRoute', children: [page])
                            else
                              page,
                          ],
                        ),
                      ],
                    ),
                  ),
          );
        }

        testWidgets('$how to $inTab that a guard lets in closes the dialog '
            'over the tabs', (tester) async {
          final router = await openWithDialog(tester);

          go(router, '14');
          await tester.pumpAndSettle();

          expect(find.text('Unsaved draft'), findsNothing);
          expect(find.text('Mail 14'), findsOneWidget);
          expect(router.currentUrl, '$prefix/14');
        });

        testWidgets('$how to $inTab that a guard rejects keeps the dialog '
            'over the tabs', (tester) async {
          final router = await openWithDialog(tester);

          go(router, '13');
          await tester.pumpAndSettle();

          expect(find.text('Unsaved draft'), findsOneWidget);
          expect(find.text('Mail 42'), findsOneWidget);
          expect(router.currentUrl, '$prefix/42');
        });

        for (final isLetIn in [false, true]) {
          testWidgets('$how to $inTab whose guard answers later keeps the '
              'dialog over the tabs while it decides, and '
              '${isLetIn ? 'closes it once let in' : 'after it rejects'}', (
            tester,
          ) async {
            final router = await openWithDialog(tester);

            go(router, '77');
            await tester.pumpAndSettle();
            expect(find.text('Unsaved draft'), findsOneWidget);

            slowAnswer!.complete(isLetIn);
            await tester.pumpAndSettle();

            expect(
              find.text('Unsaved draft'),
              isLetIn ? findsNothing : findsOneWidget,
            );
            expect(
              find.text('Mail 77'),
              isLetIn ? findsOneWidget : findsNothing,
            );
          });
        }
      }
    }
  });
}
