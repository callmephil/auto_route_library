import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'restoration_test_utils.dart';

// After state restoration, a nested page that takes a path param from its
// parent route (`@PathParam.inherit`) was left out. Found by the audit of
// auto_route/lib at dev 56b73492 (finding W2).
// Cause: _buildableMatches (routes_restoration.dart) built each restored page
// once with route data that had no parent, so the inherited param was
// missing, the page threw MissingRequiredParameterError, and it was dropped
// as a page that can't be built without the args it was opened with.
// Setup, as the README's "Inherited Path Parameters" has it: '/product/:id'
// holds a nested router with an overview page at '' and a review page at
// 'review'. The review page reads 'id' from data.inheritedPathParams, as the
// generator writes it for `@PathParam.inherit('id') required int id`.
// Steps: open /product/5/review, let the platform end the app, restore it.
// Was: the review page was gone; the product showed its overview.
// Should: the review page comes back, as the README's State Restoration says:
// "auto_route saves every page of every stack and tab, with their path and
// query params, so the user lands on the same page". On Android and iOS a
// restored screen gets the arguments it was saved with, and Flutter's own
// restoration brings back every route whose data it saved
// (Navigator.restorablePush).
void main() {
  RootStackRouter buildRouter({bool doesReadInherited = true}) => .build(
    routes: [
      AutoRoute(path: '/', page: page('HomeRoute'), initial: true),
      AutoRoute(
        path: '/product/:id',
        page: PageInfo('ProductRoute', builder: (_) => const AutoRouter()),
        children: [
          AutoRoute(path: '', page: page('ProductOverviewRoute')),
          AutoRoute(
            path: 'review',
            page: PageInfo(
              'ProductReviewRoute',
              builder: (data) {
                // As the generator writes it for an inherited path param.
                final pathParams = data.inheritedPathParams;
                if (!doesReadInherited) return const Text('Review');
                return Text('Review of ${pathParams.getInt('id')}');
              },
            ),
          ),
        ],
      ),
    ],
  );

  testWidgets(
    'A nested page that inherits a path param comes back after restoration',
    (tester) async {
      await tester.pumpWidget(RestorableRouterApp(buildRouter));
      await tester.pumpAndSettle();
      unawaited(RestorableRouterApp.router.pushPath('/product/5'));
      await tester.pumpAndSettle();
      unawaited(RestorableRouterApp.router.pushPath('/product/5/review'));
      await tester.pumpAndSettle();
      final reviewsBefore = find.text('Review of 5').evaluate().length;
      final nestedBefore = RestorableRouterApp.router
          .innerRouterOf<StackRouter>('ProductRoute')!
          .stack
          .map((page) => page.name)
          .toList();

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final router = RestorableRouterApp.router;
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'ProductRoute',
      ]);
      expect(
        router
            .innerRouterOf<StackRouter>('ProductRoute')!
            .stack
            .map((page) => page.name),
        nestedBefore,
      );
      expect(
        (reviewsBefore, find.text('Review of 5').evaluate().length),
        (1, 1),
      );
    },
    skip: kIsWeb,
  );

  // Control: the same page comes back when it doesn't read the inherited
  // param, so the page is dropped for that read alone.
  testWidgets(
    'Control: the nested page comes back when it reads no inherited param',
    (tester) async {
      await tester.pumpWidget(
        RestorableRouterApp(() => buildRouter(doesReadInherited: false)),
      );
      await tester.pumpAndSettle();
      unawaited(RestorableRouterApp.router.pushPath('/product/5'));
      await tester.pumpAndSettle();
      unawaited(RestorableRouterApp.router.pushPath('/product/5/review'));
      await tester.pumpAndSettle();
      final reviewsBefore = find.text('Review').evaluate().length;

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(
        RestorableRouterApp.router
            .innerRouterOf<StackRouter>('ProductRoute')!
            .stack
            .map((page) => page.name),
        ['ProductOverviewRoute', 'ProductReviewRoute'],
      );
      expect((reviewsBefore, find.text('Review').evaluate().length), (1, 1));
    },
    skip: kIsWeb,
  );
}
