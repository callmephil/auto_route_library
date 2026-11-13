import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/matcher/route_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

// A link that repeats a query key, such as '/products?page=1&page=2', gives
// int, double, num and bool params its last value, as String params get it in
// repeated_query_key_test.dart.
// Steps: match the link and read each param with its typed getter.
// Was: optInt, optDouble, optNum and optBool parsed the text of the list the
// router keeps for a repeated key. They gave the default, and getInt and the
// other getters threw MissingRequiredParameterError, so a page with a
// required int query param failed to open from such a link.
// Native behavior this holds to: Dart's Uri, whose queryParameters gives the
// last value of a repeated key, as Parameters.optString's doc says. (A
// browser's URLSearchParams.get gives the first; the package chose Dart's.)
void main() {
  final matcher = RouteMatcher(
    RouteCollection.fromList([
      TestRoute('ProductsRoute', path: '/products'),
    ], root: true),
  );
  const link =
      '/products?page=1&page=2&ratio=0.5&ratio=1.5&sale=false&sale=true';
  final params =
      matcher.match(link)?.singleOrNull?.queryParams ?? const Parameters({});

  test('Dart and the String getter give the last value of a repeated key', () {
    expect(Uri.parse(link).queryParameters['page'], '2');
    expect(params.optString('page'), '2');
  });

  test('optInt and getInt give the last value of a repeated key', () {
    expect(params.optInt('page'), 2);
    expect(params.getInt('page'), 2);
  });

  test('optDouble and optNum give the last value of a repeated key', () {
    expect(params.optDouble('ratio'), 1.5);
    expect(params.optNum('ratio'), 1.5);
  });

  test('optBool gives the last value of a repeated key', () {
    expect(params.optBool('sale'), isTrue);
  });
}
