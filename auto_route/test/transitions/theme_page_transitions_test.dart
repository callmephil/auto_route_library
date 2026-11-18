import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // https://github.com/Milad-Akarie/auto_route_library/issues/2340
  // Reported: since 11.2.0 pages no longer use the transitions of the app's
  // Theme.pageTransitionsTheme, they use the fallback of the Android theme.
  // Setup: a MaterialApp.router whose theme names its own page transitions
  // builder, and a page pushed on top of the first one.
  // Should: the builder of the theme runs for the pushed page.
  //
  // The pages are built with package:material_ui and read its Theme. The
  // reporter's app has its MaterialApp from Flutter's built-in material
  // library, deprecated since Flutter 3.50.0, whose Theme is another class;
  // auto_route no longer reads that one.
  for (final (label, type) in [
    ('RouteType.material()', const RouteType.material()),
    ('RouteType.adaptive()', const RouteType.adaptive()),
  ]) {
    testWidgets(
      'A page of $label uses the Theme pageTransitionsTheme',
      (tester) async {
        final builder = _RecordingTransitionsBuilder();
        final router = RootStackRouter.build(
          defaultRouteType: type,
          routes: [
            AutoRoute(page: _HomeRoute.page, path: '/'),
            AutoRoute(page: _DetailsRoute.page, path: '/details'),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: ThemeData(
              pageTransitionsTheme: PageTransitionsTheme(
                builders: {
                  for (final platform in TargetPlatform.values)
                    platform: builder,
                },
              ),
            ),
            routerConfig: router.config(),
          ),
        );
        await tester.pumpAndSettle();
        builder.calls = 0;

        unawaited(router.push(const _DetailsRoute()));
        await tester.pumpAndSettle();

        expect(find.text('Details'), findsOneWidget);
        expect(builder.calls, greaterThan(0));
      },
      // an adaptive route has no transition on web
      skip: kIsWeb && type is AdaptiveRouteType,
    );
  }

  // A page of package:material_ui pushed over a page takes nothing from it:
  // both routes share the delegated transition of material_ui's theme.
  testWidgets(
    'A page keeps its own transition under a MaterialPageRoute of material_ui',
    (tester) async {
      final router = RootStackRouter.build(
        routes: [AutoRoute(page: _HomeRoute.page, path: '/')],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router.config()),
      );
      await tester.pumpAndSettle();

      router.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Pageless')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pageless'), findsOneWidget);
      final homeRoute = ModalRoute.of(
        tester.element(find.text('Home', skipOffstage: false)),
      )!;
      expect(homeRoute.receivedTransition, isNull);
    },
  );
}

class _RecordingTransitionsBuilder extends PageTransitionsBuilder {
  int calls = 0;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    calls++;
    return child;
  }
}

abstract final class _HomeRoute {
  static const String name = 'HomeRoute';
  static final PageInfo page = PageInfo(
    name,
    builder: (_) => const Scaffold(body: Text('Home')),
  );
}

class _DetailsRoute extends PageRouteInfo<void> {
  const new() : super(name);

  static const String name = 'DetailsRoute';
  static final PageInfo page = PageInfo(
    name,
    builder: (_) => const Scaffold(body: Text('Details')),
  );
}
