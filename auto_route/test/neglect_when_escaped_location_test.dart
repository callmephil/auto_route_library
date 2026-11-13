import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// `neglectWhen` of router.config gets the url of the page as it is, on the
// web as elsewhere: for the page '/books/a%20b?note=x%26y' it gets
// '/books/a%20b?note=x%26y'. On the web it used to get the url with every
// '%' escaped once more, '/books/a%2520b?note=x%2526y', so a callback that
// read the location saw 'x%26y' for the param note, and one that compared it
// with a url holding an escape never matched. Run it on the VM and in Chrome
// (`flutter test --platform chrome`).
//
// Steps: an app with a neglectWhen that records what it is given; push the
// book 'a b' with the query param note 'x&y'.
//
// Native behavior this holds to: Flutter's RouteInformation.uri, the
// location of the app, is the same value on every platform, and the README,
// "Keeping a url out of the address bar", says neglectWhen "gets the
// location, such as `/checkout/confirm` (with its query, if any)", the url
// the address bar shows.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'BookRoute',
      path: '/books/:id',
      builder: (_, _) => const Text('BookRoute'),
    ),
  ],
);

void main() {
  testWidgets('neglectWhen gets the url of the page as it is', (tester) async {
    final router = _router();
    final locations = <String?>[];
    await pumpRouterConfigApp(
      tester,
      router.config(
        neglectWhen: (location) {
          locations.add(location);
          return false;
        },
      ),
    );
    unawaited(
      router.push(
        const NamedRoute(
          'BookRoute',
          params: {'id': 'a b'},
          queryParams: {'note': 'x&y'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.urlState.uri.toString(), '/books/a%20b?note=x%26y');

    // The Chrome runner doesn't print a failed expectation, so say it here.
    final location = locations.lastOrNull ?? 'nothing';
    printOnFailure('neglectWhen was given: $location');
    expect(location, '/books/a%20b?note=x%26y');
    final given = Uri.parse(location);
    expect(given.pathSegments.lastOrNull, 'a b');
    expect(given.queryParameters['note'], 'x&y');
  });
}
