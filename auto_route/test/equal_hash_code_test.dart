import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/matcher/route_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

// Objects equal by == have the same hash code, so a Set or a Map keyed by
// them holds one entry and finds an equal one.
// Steps: build two equal objects of each class and compare their hash codes.
// Was: three classes broke the rule.
// 1. Parameters hashed list values by identity while == compared them
//    deeply; a repeated query key is a list, so two matches of
//    '/search?tag=a&tag=b' were equal and hashed apart, and with them
//    RouteMatch and UrlState.
// 2. PageRouteInfo with `argsEquality: false`, which the generator writes for
//    `@AutoRouterConfig(argsEquality: false)`: == skipped args, hashCode
//    mixed them in.
// 3. AutoRouteInformation: == compared uri and state, hashCode was
//    `replace.hashCode`.
// Native behavior this holds to: Dart's contract for Object.hashCode, "Hash
// codes must be the same for objects that are equal to each other according
// to operator ==", which Flutter's own classes keep.
void main() {
  test('Equal Parameters holding lists have the same hash code', () {
    // Two lists built at run time, so they are equal but not identical.
    final a = Parameters({
      'tag': List.of(const ['a', 'b']),
    });
    final b = Parameters({
      'tag': List.of(const ['a', 'b']),
    });
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('Two matches of a url that repeats a query key have the same hash '
      'code', () {
    final matcher = RouteMatcher(
      RouteCollection.fromList([
        TestRoute('SearchRoute', path: '/search'),
      ], root: true),
    );
    final [a, b] = [
      for (var i = 0; i < 2; i++)
        matcher.match('/search?tag=a&tag=b')?.singleOrNull,
    ];
    expect(a, isNotNull);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a, b}, hasLength(1));
  });

  test('Routes equal without their args have the same hash code', () {
    const a = PageRouteInfo('BookRoute', args: 1, argsEquality: false);
    const b = PageRouteInfo('BookRoute', args: 2, argsEquality: false);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('Equal AutoRouteInformation have the same hash code', () {
    final a = AutoRouteInformation(uri: Uri.parse('/a'));
    final b = AutoRouteInformation(uri: Uri.parse('/a'), replace: false);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
