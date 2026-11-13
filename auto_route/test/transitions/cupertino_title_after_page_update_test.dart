import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

// A Cupertino page kept the title of the page its route was created for,
// after the page was updated in place. Found by the audit of auto_route/lib
// at dev 56b73492 (finding W7).
// Cause: AutoRoutePage.onCreateRoute read routeData.title(context) once and
// handed it to _PageBasedCupertinoPageRoute as a final field, so the route
// never saw the title of a later page.
// Setup: '/books/:id' is a Cupertino route with `title: (_, data) => 'Book
// <id>'`; its page shows a CupertinoNavigationBar, which takes its title from
// the route.
// Steps: push book 1, then navigate to book 2, which updates the page in
// place (README, "One page per path").
// Was: the page showed book 2 under a navigation bar that said 'Book 1'.
// Should: the bar says 'Book 2'. Flutter's own page-based Cupertino route
// reads the title from the page it holds now (cupertino_ui
// lib/src/route.dart, _PageBasedCupertinoPageRoute: `String? get title =>
// _page.title;`), and on iOS a view controller's navigation item follows its
// `title` when it is set again.
void main() {
  testWidgets(
    'The navigation bar of a Cupertino page updated in place shows the new '
    "page's title",
    (tester) async {
      final router = RootStackRouter.build(
        defaultRouteType: const RouteType.cupertino(),
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const CupertinoPageScaffold(child: Text('Home')),
          ),
          NamedRouteDef(
            name: 'BookRoute',
            path: '/books/:id',
            title: (_, data) => 'Book ${data.params.getString('id')}',
            builder: (_, data) => CupertinoPageScaffold(
              // Built again with each page, as its trailing id changes, so it
              // reads the route's title again. A const bar keeps the title it
              // first read, with Flutter's own CupertinoPage too.
              navigationBar: CupertinoNavigationBar(
                trailing: Text('#${data.params.getString('id')}'),
              ),
              child: Center(
                child: Text('Body of book ${data.params.getString('id')}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        CupertinoApp.router(routerConfig: router.config()),
      );
      await tester.pumpAndSettle();

      unawaited(
        router.push(const NamedRoute('BookRoute', params: {'id': '1'})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Body of book 1'), findsOneWidget);
      expect(find.text('Book 1'), findsOneWidget);
      final bookElement = tester.element(find.byType(CupertinoNavigationBar));

      unawaited(
        router.navigate(const NamedRoute('BookRoute', params: {'id': '2'})),
      );
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.routeData.match), [
        '/',
        '/books/2',
      ]);
      // The page is updated in place, not replaced by a new one.
      expect(tester.element(find.byType(CupertinoNavigationBar)), bookElement);
      expect(find.text('Body of book 2'), findsOneWidget);
      expect(router.current.title(bookElement), 'Book 2');
      expect(find.text('Book 1'), findsNothing);
      expect(find.text('Book 2'), findsOneWidget);
    },
  );
}
