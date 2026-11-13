import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/matcher/route_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

// A RedirectRoute whose redirectTo ends in a fragment keeps it.
// Steps: match '/help' against RedirectRoute(path: '/help', redirectTo:
// '/docs#faq'), and the url it ends on.
// Was: '/docs': the redirect always took the fragment of the url being
// redirected, also when that url had none.
// Native behavior this holds to: a redirect on the web (RFC 9110 section
// 10.2.2, and the Fetch standard's "location URL") uses the target's own
// fragment, and inherits the request's only when the target has none.
void main() {
  final matcher = RouteMatcher(
    RouteCollection.fromList([
      TestRoute('HomeRoute', path: '/'),
      TestRoute('DocsRoute', path: '/docs'),
      RedirectRoute(path: '/help', redirectTo: '/docs#faq'),
      RedirectRoute(path: '/help-tab', redirectTo: '/docs?tab=faq'),
      RedirectRoute(path: '/manual', redirectTo: '/docs'),
    ], root: true),
  );

  String urlOf(String link) =>
      UrlState.fromSegments(matcher.match(link)!).uri.toString();

  test('A redirect keeps the query of its redirectTo', () {
    expect(urlOf('/help-tab'), '/docs?tab=faq');
  });

  test('A redirect without a fragment hands on the fragment of the url', () {
    expect(urlOf('/manual#install'), '/docs#install');
  });

  test('A redirect keeps the fragment of its redirectTo', () {
    expect(urlOf('/help'), '/docs#faq');
  });
}
