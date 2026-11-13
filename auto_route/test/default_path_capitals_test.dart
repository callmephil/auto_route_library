import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/utils.dart';
import 'package:flutter_test/flutter_test.dart';

// The default path of a route named with capitals in a row stays as it is:
// TVRoute gets '/t-vRoute', UIRoute '/u-iRoute', HTTPRoute '/h-tt-pRoute'.
// Lowering them would be the kebab-case the README describes, but it would
// change the url of every such route in apps that use it, and break links
// to them (bookmarks, links in app manifests). An app that wants another
// path gives the route its own, or overrides RootStackRouter.onGeneratePath.
// Native behavior this holds to: a url that worked keeps working; a web
// server's paths, like Android's and iOS's link patterns, match by case.
void main() {
  test('The README example gets a kebab-case path', () {
    expect(toKebabCase('BookListRoute'), 'book-list-route');
  });

  for (final (name, path) in [
    ('TVRoute', '/t-vRoute'),
    ('UIRoute', '/u-iRoute'),
    ('HTTPRoute', '/h-tt-pRoute'),
  ]) {
    test('The default path of $name stays $path', () {
      final routes = RouteCollection.fromList([TestRoute(name)], root: true);
      expect(routes[name]!.path, path);
    });
  }
}
