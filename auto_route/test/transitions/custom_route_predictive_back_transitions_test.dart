import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// What enablePredictiveBackGesture does to the transitions of a CustomRoute
// on Android, as the doc of PredictiveBackGestureMixin and the README's
// "Android Predictive Back" say. Pinned after the audit of auto_route/lib at
// dev 56b73492 (finding W8), set aside as not worth fixing: without a
// predictiveBackPageTransitionsBuilder, the route hands all its transitions
// to Flutter's PredictiveBackPageTransitionsBuilder, whose fallback outside
// the gesture is FadeForwardsPageTransitionsBuilder, so a push doesn't play
// the route's own transitionsBuilder. With a builder for the gesture, the
// route's own transition plays at every other time.
// Steps: an Android app pushes a CustomRoute that has its own transitions
// builder, and counts how often that builder runs.
// Flutter's builder says of itself: "Only do a predictive back transition
// when the user is performing a pop gesture"; outside it, it plays its own
// fallback, not the route's.
void main() {
  Future<int> pushAndCountTransitions(
    WidgetTester tester, {
    required bool enablePredictiveBackGesture,
    RouteTransitionsBuilder? predictiveBackPageTransitionsBuilder,
  }) async {
    var transitionBuilds = 0;
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        NamedRouteDef(
          name: 'DetailsRoute',
          path: '/details',
          type: RouteType.custom(
            enablePredictiveBackGesture: enablePredictiveBackGesture,
            predictiveBackPageTransitionsBuilder:
                predictiveBackPageTransitionsBuilder,
            transitionsBuilder: (_, animation, _, child) {
              transitionBuilds++;
              return FadeTransition(opacity: animation, child: child);
            },
          ),
          builder: (_, _) => const Scaffold(body: Text('Details')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(platform: .android),
        routerConfig: router.config(),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    return transitionBuilds;
  }

  testWidgets('Without predictive back, the route runs its '
      'transitionsBuilder', (tester) async {
    final builds = await pushAndCountTransitions(
      tester,
      enablePredictiveBackGesture: false,
    );
    expect(builds, greaterThan(0));
  });

  testWidgets('With predictive back and a builder of its own for the '
      'gesture, the route runs its transitionsBuilder on push', (tester) async {
    final builds = await pushAndCountTransitions(
      tester,
      enablePredictiveBackGesture: true,
      predictiveBackPageTransitionsBuilder: (_, _, _, child) => child,
    );
    expect(builds, greaterThan(0));
  });

  testWidgets('With predictive back and no builder for the gesture, a push '
      "plays Flutter's predictive back builder, not the route's own", (
    tester,
  ) async {
    final builds = await pushAndCountTransitions(
      tester,
      enablePredictiveBackGesture: true,
    );
    expect(builds, 0);
  });
}
