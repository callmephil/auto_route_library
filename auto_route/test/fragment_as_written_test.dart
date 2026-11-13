import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A url fragment reads as the url has it, not decoded: audit finding U11,
// documented on the fragment of RouteMatch, RouteData and PageRouteInfo.
// Steps: open /callback#<params> as a link, as a sign-in provider sends an app
// back, and parse the fragment as a query string; open a fragment whose '%'
// is escaped and read the url the app writes; push a fragment already encoded
// and open its url again, as a reload does.
// Kept: a page that parses its own fragment reads each value whole, and the
// app writes the url it opened unchanged. A decode on reading broke both.
// Native behavior this holds to: Dart's Uri.fragment, the browser's
// location.hash and iOS's NSURL.fragment all keep a fragment's escapes, and
// Android's Uri offers both, getFragment and getEncodedFragment.
String? _lastFragment;

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'CallbackRoute',
      path: '/callback',
      builder: (_, data) {
        _lastFragment = data.fragment;
        return Text('Callback ${data.fragment}');
      },
    ),
  ],
);

Future<void> _handLink(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _lastFragment = null);

  testWidgets('A page that parses its fragment as a query string reads each '
      'value whole', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await _handLink(
      tester,
      '/callback#token=a%2Bb%3D%3D&next=%2Fhome%3Fx%3D1%26y%3D2',
    );
    expect(find.textContaining('Callback'), findsOneWidget);
    final params = Uri.splitQueryString(_lastFragment ?? '');
    expect(params, {'token': 'a+b==', 'next': '/home?x=1&y=2'});
  });

  testWidgets('The url the app writes keeps the fragment of the link it '
      'opened', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    // The fragment stands for the text 'a%20b': its '%' is escaped.
    await _handLink(tester, '/callback#a%2520b');
    expect(
      (_lastFragment, router.urlState.uri.toString()),
      ('a%2520b', '/callback#a%2520b'),
    );
  });

  testWidgets('A fragment pushed already encoded reads the same after a '
      'reload', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(const NamedRoute('CallbackRoute', fragment: 'my%20section')),
    );
    await tester.pumpAndSettle();
    final afterPush = _lastFragment;
    final url = router.urlState.uri.toString();

    await tester.pumpWidget(const SizedBox());
    await pumpRouterApp(tester, _router(), initialLink: url);
    expect(
      (afterPush, url, _lastFragment),
      ('my%20section', '/callback#my%20section', 'my%20section'),
    );
  });
}
