import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// DeepLink.prefixStripper('/app') is the shipped transformer for links whose
// path starts with a prefix, such as an Android App Link filtered by
// pathPrefix. It checked that uri.path started with the prefix, but then
// removed the first occurrence of the prefix's text from the whole url string.
// The platform hands the router the whole link, scheme and host included (see
// custom_scheme_host_link_test), so when the host began with the same text,
// as in 'https://app.example.com/app/books/1', the text was cut out of '//app'
// and the link became 'https:/.example.com/app/books/1', which no route
// matches. It also cut '/app' out of '/application'. It now cuts the prefix
// from the path alone, as whole segments.
//
// Native behavior this holds to: the doc comment of prefixStripper, "Helper function to remove the
// prefix path of a [Uri]", and the README's own transformer next to it, which
// does `uri.replace(path: uri.path.replaceFirst('/prefix', ''))`: the prefix
// is part of the path, and Dart's Uri.path of that link is '/app/books/1'.
// Android's pathPrefix is matched against the path alone, too.
// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

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
      builder: (_, data) => Text('Book ${data.params.getString('id')}'),
    ),
  ],
);

void main() {
  test('prefixStripper strips the prefix of a path-only link', () async {
    final strip = DeepLink.prefixStripper('/app');
    expect((await strip(Uri.parse('/app/books/1'))).path, '/books/1');
  });

  test('prefixStripper strips the path, not a host that starts with the '
      "prefix's text", () async {
    final strip = DeepLink.prefixStripper('/app');
    final link = Uri.parse('https://app.example.com/app/books/1');
    expect(link.path, '/app/books/1');
    final stripped = await strip(link);
    expect(stripped.path, '/books/1');
    expect(stripped.host, 'app.example.com');
  });

  // The README called the helper without the leading '/',
  // `DeepLink.prefixStripper('prefix')`, which stripped nothing, since a path
  // starts with '/'. The prefix is now taken with or without it.
  test(
    "prefixStripper('prefix'), as the README calls it, strips '/prefix'",
    () async {
      final strip = DeepLink.prefixStripper('prefix');
      expect((await strip(Uri.parse('/prefix/books/1'))).path, '/books/1');
    },
  );

  test('prefixStripper cuts whole segments only', () async {
    final strip = DeepLink.prefixStripper('/app');
    for (final (link, path) in [
      ('https://example.com/application/1', '/application/1'),
      ('https://example.com/app', '/'),
      ('https://example.com/app/', '/'),
      ('https://example.com/books/app/1', '/books/app/1'),
    ]) {
      expect((await strip(Uri.parse(link))).path, path, reason: link);
    }
  });

  test('prefixStripper keeps the query and the fragment', () async {
    final strip = DeepLink.prefixStripper('/app/');
    final stripped = await strip(
      Uri.parse('https://example.com/app/home?next=/app/x#top'),
    );
    expect(stripped.toString(), 'https://example.com/home?next=/app/x#top');
  });

  // Steps: the app, which strips the prefix '/app' from its links, runs on
  // '/' when the platform hands it 'https://app.example.com/app/books/1'.
  // Should: the book page opens, the same as for the link from the host
  // www.example.com.
  for (final host in ['www.example.com', 'app.example.com']) {
    testWidgets('A link to $host under the prefix opens its page', (
      tester,
    ) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(deepLinkTransformer: DeepLink.prefixStripper('/app')),
      );
      await sendPlatformLink(tester, 'https://$host/app/books/1');
      await tester.pumpAndSettle();
      expect(find.text('Book 1'), findsOneWidget);
    });
  }
}
