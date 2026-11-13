import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// In AutoRouter.declarative, a page that back popped couldn't be opened again
// while the app's list still named it. Found by the audit of auto_route/lib at
// dev 56b73492 (finding W5).
// Cause: the declarative router kept the last list the routes callback
// returned and updated the router only when the callback returned a
// different one. A pop took the page off the router but left that list, so
// the same list, returned again, counted as unchanged.
// Setup, the README's "Declarative Navigation" example as it stands: the
// routes are [BookListRoute, if (selectedBook != null) BookDetailsRoute], and
// the app passes no onPopRoute.
// Steps: tap book 1, press back, tap book 1 again.
// Was: the second tap showed nothing; the list page stayed, though the app's
// list named the details page.
// Should: the details page shows again. Flutter's Navigator, which the
// declarative router wraps, says so for its own pages (widgets/navigator.dart,
// Navigator.onDidRemovePage): the next time the pages list is updated, a
// popped page still present "will be interpreted as a new page to display".
// The list is the truth, so the same holds for any rebuild of the host, as
// the README says; an app that wants the page to stay closed takes it out of
// the list in onPopRoute, as the README's example does.
class _BooksHost extends StatefulWidget {
  const new({required this.clearsOnPop});

  final bool clearsOnPop;

  @override
  State<_BooksHost> createState() => _BooksHostState();
}

class _BooksHostState extends State<_BooksHost> {
  int? _selectedBook;
  // A state of the host's own, which has nothing to do with the books.
  var _refreshes = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => _selectedBook = 1),
          child: const Text('Select book 1'),
        ),
        TextButton(
          onPressed: () => setState(() => _refreshes++),
          child: Text('Refreshed $_refreshes times'),
        ),
        Expanded(
          child: AutoRouter.declarative(
            routes: (_) => [
              const NamedRoute('BookListRoute'),
              if (_selectedBook != null)
                NamedRoute('BookDetailsRoute', params: {'id': _selectedBook}),
            ],
            onPopRoute: widget.clearsOnPop
                ? (_, _) => setState(() => _selectedBook = null)
                : null,
          ),
        ),
      ],
    );
  }
}

RootStackRouter _booksRouter({required bool clearsOnPop}) => .build(
  routes: [
    NamedRouteDef(
      name: 'BooksRoute',
      path: '/',
      builder: (_, _) => Scaffold(body: _BooksHost(clearsOnPop: clearsOnPop)),
      children: [
        NamedRouteDef(
          name: 'BookListRoute',
          path: '',
          builder: (_, _) => const Text('Book list'),
        ),
        NamedRouteDef(
          name: 'BookDetailsRoute',
          path: 'book/:id',
          builder: (_, data) =>
              Text('Details of book ${data.params.getInt('id')}'),
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets(
    'A declarative page that back popped shows again when the list that '
    'still names it is rebuilt',
    (tester) async {
      final router = _booksRouter(clearsOnPop: false);
      await pumpRouterApp(tester, router);
      final listsAtStart = find.text('Book list').evaluate().length;

      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();
      final detailsAtFirstTap = find
          .text('Details of book 1')
          .evaluate()
          .length;

      await systemBack(tester);
      expect(find.text('Details of book 1'), findsNothing);
      expect((listsAtStart, find.text('Book list').evaluate().length), (1, 1));

      // The app's state still names book 1, so its list is the same as
      // before the pop.
      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();
      expect(
        (detailsAtFirstTap, find.text('Details of book 1').evaluate().length),
        (1, 1),
      );
    },
  );

  // The list is the truth: a rebuild of the host for a reason of its own
  // gives the router the list again, and a page it still names comes back,
  // as with Flutter's Navigator and its pages. Pinned after the review of the
  // fix: on dev the page stayed closed until the list changed.
  testWidgets(
    'A page back closed comes back at the next rebuild while the list still '
    'names it',
    (tester) async {
      final router = _booksRouter(clearsOnPop: false);
      await pumpRouterApp(tester, router);
      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();

      await systemBack(tester);
      final detailsAfterBack = find.text('Details of book 1').evaluate().length;

      await tester.tap(find.text('Refreshed 0 times'));
      await tester.pumpAndSettle();
      expect(
        (detailsAfterBack, find.text('Details of book 1').evaluate().length),
        (0, 1),
      );
      expect(router.currentUrl, '/book/1');
    },
  );

  // The README's way: onPopRoute takes the page out of the list, so it stays
  // closed through other rebuilds and opens when it is chosen again.
  testWidgets(
    'A page back closed stays closed through a rebuild once onPopRoute takes '
    'it out of the list',
    (tester) async {
      final router = _booksRouter(clearsOnPop: true);
      await pumpRouterApp(tester, router);
      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();

      await systemBack(tester);
      await tester.tap(find.text('Refreshed 0 times'));
      await tester.pumpAndSettle();
      final detailsAfterRefresh = find
          .text('Details of book 1')
          .evaluate()
          .length;
      final urlAfterRefresh = router.currentUrl;

      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();
      expect(
        (detailsAfterRefresh, find.text('Details of book 1').evaluate().length),
        (0, 1),
      );
      expect((urlAfterRefresh, router.currentUrl), ('/', '/book/1'));
    },
  );
}
