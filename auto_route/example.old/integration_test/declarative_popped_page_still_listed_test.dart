import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page of AutoRouter.declarative that back closed shows again when the
// app's list, which still names it, is given again.
// Headless test: auto_route/test/nested_router/declarative_popped_page_still_listed_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('declarative popped page still listed', () {
    // Steps, the README's declarative example as it stands, with no
    // onPopRoute: tap 'Select book 1', go back, tap 'Select book 1' again.
    // Was: the second tap showed nothing.
    // Should: the details of book 1 show again, as Flutter's Navigator shows
    // a popped page that its pages list still holds.
    testWidgets('book 1 opens again after back', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'BooksRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: SafeArea(child: _Books())),
            children: [
              NamedRouteDef(
                name: 'BookListRoute',
                path: '',
                builder: (_, _) => const Material(child: Text('Book list')),
              ),
              NamedRouteDef(
                name: 'BookDetailsRoute',
                path: 'book/:id',
                builder: (_, data) => Material(
                  child: Text('Details of book ${data.params.getInt('id')}'),
                ),
              ),
            ],
          ),
        ],
      );
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

      await tester.tap(find.text('Select book 1'));
      await tester.pumpAndSettle();
      expect(
        (
          detailsAtFirstTap,
          find.text('Details of book 1').evaluate().length,
        ),
        (1, 1),
      );
      await expectBrowserUrl('/book/1');
    });
  });
}

class _Books extends StatefulWidget {
  const new();

  @override
  State<_Books> createState() => _BooksState();
}

class _BooksState extends State<_Books> {
  int? _selectedBook;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => _selectedBook = 1),
          child: const Text('Select book 1'),
        ),
        Expanded(
          child: AutoRouter.declarative(
            routes: (_) => [
              const NamedRoute('BookListRoute'),
              if (_selectedBook != null)
                NamedRoute('BookDetailsRoute', params: {'id': _selectedBook}),
            ],
          ),
        ),
      ],
    );
  }
}
