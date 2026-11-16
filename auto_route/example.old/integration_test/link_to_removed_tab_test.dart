import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link or a path to a tab the app has removed from its tabs list is turned
// down. The tab on screen, its url and the dialog the user has open stay,
// and the app's own call hears a RouteNotFoundFailure.
// Headless test:
// auto_route/test/nested_tabs_router/link_to_removed_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Hands [location] to the running app the way the engine does when the
  // platform opens a link.
  Future<void> openLink(WidgetTester tester, String location) async {
    const codec = JSONMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': location,
          'state': null,
        }),
      ),
      null,
    );
    await tester.pumpAndSettle();
  }

  group('link to removed tab', () {
    // Steps: tabs [A, B, C], each with its own stack. Tap 'Push A2' in tab
    // A, then 'Open tab C', then 'Drop tab C', which rebuilds the tabs as
    // [A, B]: tab A shows on A2. The user opens a dialog, and the platform
    // hands the running app a link to '/c'.
    // Was: the link was taken as let in: the dialog closed.
    // Should: A2 and the dialog stay, at the url '/a/2'.
    testWidgets(
      'A link to the removed tab keeps the tab and the dialog',
      (tester) async {
        final failures = ValueNotifier<List<NavigationFailure>>(const []);
        addTearDown(failures.dispose);
        final router = await _openOnA2(tester, failures);
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();

        await openLink(tester, '/c');

        expect(tester.takeException(), isNull);
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('C1'), findsNothing);
        expect(router.urlState.url, '/a/2');
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );

    // Steps: as above, without the dialog; then tap 'Go to tab C', which
    // calls navigatePath('/c') with an onFailure that lists the failure.
    // Was: nothing happened and nobody was told.
    // Should: A2 stays at '/a/2', and the app hears a RouteNotFoundFailure.
    testWidgets(
      "The app's path to the removed tab keeps the tab and reports it",
      (tester) async {
        final failures = ValueNotifier<List<NavigationFailure>>(const []);
        addTearDown(failures.dispose);
        final router = await _openOnA2(tester, failures);

        await tester.tap(find.text('Go to tab C').hitTestable());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('A2').hitTestable(), findsOneWidget);
        expect(find.text('C1'), findsNothing);
        expect(router.urlState.url, '/a/2');
        await expectBrowserUrl('/a/2');
        expect(failures.value.map((failure) => failure.runtimeType), [
          RouteNotFoundFailure,
        ]);
      },
    );
  });
}

// Shows tabs [A, B, C], opens A2 in tab A and then tab C, and drops tab C
// from the list: tab A shows on A2. The app's failures go to [failures].
Future<RootStackRouter> _openOnA2(
  WidgetTester tester,
  ValueNotifier<List<NavigationFailure>> failures,
) async {
  final routes = ValueNotifier<List<PageRouteInfo>>(const [
    NamedRoute('TabA'),
    NamedRoute('TabB'),
    NamedRoute('TabC'),
  ]);
  addTearDown(routes.dispose);
  final router = _buildRouter(routes, failures);
  await pumpRouterAppWithConfig(tester, router);
  await tester.tap(find.text('Push A2').hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open tab C').hitTestable());
  await tester.pumpAndSettle();
  expect(find.text('C1').hitTestable(), findsOneWidget);
  await tester.tap(find.text('Drop tab C').hitTestable());
  await tester.pumpAndSettle();
  expect(find.text('A2').hitTestable(), findsOneWidget);
  expect(router.urlState.url, '/a/2');
  return router;
}

RootStackRouter _buildRouter(
  ValueNotifier<List<PageRouteInfo>> routes,
  ValueNotifier<List<NavigationFailure>> failures,
) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => Scaffold(
        body: ValueListenableBuilder(
          valueListenable: routes,
          builder: (_, value, _) => AutoTabsRouter(routes: value),
        ),
      ),
      children: [
        for (final tab in ['A', 'B', 'C'])
          AutoRoute(
            path: tab.toLowerCase(),
            page: EmptyShellRoute('Tab$tab'),
            children: [
              for (final (path, name) in [('', '${tab}1'), ('2', '${tab}2')])
                NamedRouteDef(
                  name: name,
                  path: path,
                  builder: (context, _) => SafeArea(
                    child: Column(
                      children: [
                        Text(name),
                        TextButton(
                          onPressed: () => unawaited(
                            context.router.push(const NamedRoute('A2')),
                          ),
                          child: const Text('Push A2'),
                        ),
                        TextButton(
                          onPressed: () => context.tabsRouter.setActiveIndex(2),
                          child: const Text('Open tab C'),
                        ),
                        TextButton(
                          onPressed: () => routes.value = const [
                            NamedRoute('TabA'),
                            NamedRoute('TabB'),
                          ],
                          child: const Text('Drop tab C'),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            context.router.root.navigatePath(
                              '/c',
                              onFailure: (failure) =>
                                  failures.value = [...failures.value, failure],
                            ),
                          ),
                          child: const Text('Go to tab C'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  ],
);
