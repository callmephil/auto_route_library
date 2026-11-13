import 'package:auto_route/auto_route.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';

// The navigation bar of a Cupertino page updated in place shows the new
// page's title.
// Headless test: auto_route/test/transitions/cupertino_title_after_page_update_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('cupertino title after page update', () {
    // Steps: '/books/:id' is a Cupertino route titled 'Book <id>'. Tap 'Open
    // book 1', then 'Next book', which navigates to book 2 and updates the
    // page in place.
    // Was: the body showed book 2 under a bar that said 'Book 1'.
    // Should: the bar says 'Book 2', as Flutter's own page-based Cupertino
    // route reads the title of the page it holds now.
    testWidgets('the bar shows the title of book 2', (tester) async {
      final router = RootStackRouter.build(
        defaultRouteType: const RouteType.cupertino(),
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (context, _) => CupertinoPageScaffold(
              child: SafeArea(
                child: CupertinoButton(
                  onPressed: () => context.router.push(
                    const NamedRoute('BookRoute', params: {'id': 1}),
                  ),
                  child: const Text('Open book 1'),
                ),
              ),
            ),
          ),
          NamedRouteDef(
            name: 'BookRoute',
            path: '/books/:id',
            title: (_, data) => 'Book ${data.params.getInt('id')}',
            builder: (context, data) {
              final id = data.params.getInt('id');
              return CupertinoPageScaffold(
                navigationBar: CupertinoNavigationBar(trailing: Text('#$id')),
                child: SafeArea(
                  child: CupertinoButton(
                    onPressed: () => context.router.navigate(
                      NamedRoute('BookRoute', params: {'id': id + 1}),
                    ),
                    child: Text('Next book after $id'),
                  ),
                ),
              );
            },
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.tap(find.text('Open book 1'));
      await tester.pumpAndSettle();
      expect(find.text('Book 1'), findsOneWidget);

      await tester.tap(find.text('Next book after 1'));
      await tester.pumpAndSettle();
      expect(find.text('Next book after 2'), findsOneWidget);
      expect(router.stack, hasLength(2));
      expect(find.text('Book 1'), findsNothing);
      expect(find.text('Book 2'), findsOneWidget);
      await expectBrowserUrl('/books/2');
    });
  });
}
