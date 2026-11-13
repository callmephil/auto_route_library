import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A relative path whose first segment holds a ':' opens the page it names.
// Steps: call pushPath with the id user:5, or 12:30, in the nested router of
// the root, whose children are the empty path and the param path id.
// Was: 'user:5' opened the item '5', and '12:30' threw a FormatException
// ("Scheme not starting with alphabetic character"): RouteMatcher.match
// handed the path to Uri.parse, which reads the text before the ':' as a url
// scheme (RFC 3986 section 4.2). The absolute '/tag/a:1' already worked, as
// colon_in_url_test.dart shows.
// Native behavior this holds to: Flutter's Navigator.pushNamed takes any
// text as a route name, and a path given to pushPath is a path, as the same
// segment in an absolute path is.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'ItemsRoute',
      path: '/',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'ListRoute',
          path: '',
          builder: (_, _) => const Text('ListRoute'),
        ),
        NamedRouteDef(
          name: 'ItemRoute',
          path: ':id',
          builder: (_, data) => Text('Item ${data.params.getString('id')}'),
        ),
      ],
    ),
  ],
);

void main() {
  // Steps: in the nested router of '/', pushPath a relative path.
  for (final id in ['ab', 'user:5', '12:30']) {
    testWidgets('pushPath("$id") in a nested router opens the item "$id"', (
      tester,
    ) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      final nested = router.innerRouterOf<StackRouter>('ItemsRoute')!;
      unawaited(nested.pushPath(id));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Item $id'), findsOneWidget);
    });
  }

  test('A url with a scheme and a path from the root still reads as a url', () {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'ReportRoute',
          path: '/report',
          builder: (_, _) => const Text('ReportRoute'),
        ),
      ],
    );
    expect(
      router.matcher.match('myapp:/report')?.singleOrNull?.name,
      'ReportRoute',
    );
    expect(
      router.matcher.match('https://example.com/report')?.singleOrNull?.name,
      'ReportRoute',
    );
  });
}
