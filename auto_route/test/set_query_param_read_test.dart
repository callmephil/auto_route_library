import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A Set given as a query param reads back as its values, as a List does.
// Steps: a page reads its query params from the scoped RouteData, as the
// README shows (`context.routeData.queryParams`), here with
// `queryParams.optList('tags')`. Push the route in code with a Set, a type
// the README lists for a query param, which the generated route passes on as
// it is: `TagsRoute(tags: {'red', 'blue'})`.
// Was: the page showed the one tag '{red, blue}'. Opened from the url the
// same push writes, /tags?tags=red&tags=blue, it showed 'red' and 'blue', as
// a push with a List did: optList, getList and optString knew a List only and
// took any other Iterable's toString(). Found by the second audit (U2-8).
// Native behavior this holds to: a page reads what its url reads; the url
// the router writes for the Set holds both values, and URLSearchParams.getAll
// and Dart's Uri.queryParametersAll give every value of a repeated key.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'TagsRoute',
      path: '/tags',
      builder: (_, data) =>
          Text('Tags ${data.queryParams.optList('tags')?.join(' + ') ?? ''}'),
    ),
  ],
);

// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> _sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

void main() {
  testWidgets('Control: the url with the key twice shows both tags', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await _sendPlatformLink(tester, '/tags?tags=red&tags=blue');
    await tester.pumpAndSettle();
    expect(find.text('Tags red + blue'), findsOneWidget);
  });

  testWidgets('Control: pushed with a List, the page shows both tags', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute(
          'TagsRoute',
          queryParams: {
            'tags': ['red', 'blue'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/tags?tags=red&tags=blue');
    expect(find.text('Tags red + blue'), findsOneWidget);
  });

  testWidgets('Pushed with a Set, the page shows both tags', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute(
          'TagsRoute',
          queryParams: {
            'tags': {'red', 'blue'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/tags?tags=red&tags=blue');
    expect(find.text('Tags red + blue'), findsOneWidget);
  });

  test('optList, getList and optString read a Set as they read a List', () {
    const fromSet = Parameters({
      'tags': {'red', 'blue'},
    });
    const fromList = Parameters({
      'tags': ['red', 'blue'],
    });
    expect(fromSet.optList('tags'), fromList.optList('tags'));
    expect(fromSet.getList('tags'), fromList.getList('tags'));
    expect(fromSet.optString('tags'), fromList.optString('tags'));
  });
}
