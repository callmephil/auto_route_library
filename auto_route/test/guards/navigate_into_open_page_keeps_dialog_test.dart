import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the links chat while fixing a link turned down inside another
// tab. On dev too, with no upstream issue.
// The app's own navigate or navigatePath into a page already open closed the
// dialogs over that page before the guards of its nested router had
// answered: the root closed them as soon as it had reached the page, and the
// nested router asked its guards after. So a navigation those guards
// rejected still closed the dialog, such as an unsaved draft, and while a
// slow guard decided the dialog was already gone. A link's dialogs wait
// already. The dialogs now close once the nested guards let the navigation
// in, also two routers deep. A nested router not built yet asks its guards
// only once its page is in, so there the dialogs still close first.
// Steps: Mail is open on message 42, with a dialog over it. The app calls
// navigate or navigatePath to a message whose guard rejects it or lets it
// in, at once or after a request. The same one router deeper: Mail's folder,
// itself a nested router, holds the messages.
// Native behavior this holds to: a navigation that is refused changes
// nothing, as on the web a canceled navigation keeps the document, an open
// <dialog> included, and as on iOS and Android a screen that isn't shown
// leaves the one presented on top.
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

      // navigatePath reaches the deepest stack router at once, so it closes
      // no dialog of the root's, let in or not; it is here for the
      // rejections only.
      if (!isPath) {
        testWidgets('$how $where to a page a guard lets in at once closes the '
            'dialog', (tester) async {
          final router = await openWithDialog(tester);

          go(router, '14');
          await tester.pumpAndSettle();

          expect(find.text('Unsaved draft'), findsNothing);
          expect(find.text('Mail 14'), findsOneWidget);
          expect(router.currentUrl, '$prefix/14');
        });
      }

      for (final isLetIn in [false, if (!isPath) true]) {
        testWidgets('$how $where to a page whose guard answers later keeps the '
            'dialog while it decides, and '
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
          expect(find.text('Mail 77'), isLetIn ? findsOneWidget : findsNothing);
        });
      }
    }
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
}
