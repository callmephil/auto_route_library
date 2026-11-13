import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// RouteType's equality left out the two predictive back fields:
// RouteType.material(enablePredictiveBackGesture: true) was equal to
// RouteType.material(), with the same hash code, and so were two
// RouteType.custom that differed only in them. Found by the audit of
// auto_route/lib at dev 56b73492, an unproven idea of the first round,
// proven in round 2. No app-visible effect was found: the fields only make
// two route types unequal that are not the same.
// Steps: compare route types that differ only in enablePredictiveBackGesture
// or predictiveBackPageTransitionsBuilder, and ones that are the same.
// Should: unequal when a field differs, equal with equal hash codes when none
// does, as a Dart value class compares every field it has and
// CustomRouteType already compares all its others.
Widget _fade(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => FadeTransition(opacity: animation, child: child);

// The flag as a route definition reads it from the app's config, so each
// route type below is built anew rather than shared as a constant.
bool _isEnabled() => true;

// Two route types built alike, as two route definitions are, are equal and
// share a hash code.
void _expectEqualWhenBuiltTwice(RouteType Function() build) {
  expect(build(), build());
  expect(build().hashCode, build().hashCode);
}

void main() {
  test('Material route types differ by their predictive back fields', () {
    expect(
      const RouteType.material(enablePredictiveBackGesture: true),
      isNot(const RouteType.material()),
    );
    expect(
      const RouteType.material(predictiveBackPageTransitionsBuilder: _fade),
      isNot(const RouteType.material()),
    );
    _expectEqualWhenBuiltTwice(
      () => .material(
        enablePredictiveBackGesture: _isEnabled(),
        predictiveBackPageTransitionsBuilder: _fade,
      ),
    );
  });

  test('Adaptive route types differ by their predictive back fields', () {
    expect(
      const RouteType.adaptive(enablePredictiveBackGesture: true),
      isNot(const RouteType.adaptive()),
    );
    expect(
      const RouteType.adaptive(predictiveBackPageTransitionsBuilder: _fade),
      isNot(const RouteType.adaptive()),
    );
    _expectEqualWhenBuiltTwice(
      () => .adaptive(enablePredictiveBackGesture: _isEnabled()),
    );
  });

  test('Custom route types differ by their predictive back fields', () {
    expect(
      RouteType.custom(enablePredictiveBackGesture: true),
      isNot(RouteType.custom()),
    );
    expect(
      RouteType.custom(predictiveBackPageTransitionsBuilder: _fade),
      isNot(RouteType.custom()),
    );
    _expectEqualWhenBuiltTwice(
      () => .custom(
        transitionsBuilder: _fade,
        enablePredictiveBackGesture: _isEnabled(),
        predictiveBackPageTransitionsBuilder: _fade,
      ),
    );
  });
}
