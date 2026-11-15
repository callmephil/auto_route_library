import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A replaceAll that a guard rejects changes nothing, also inside the pages
// it had set aside for the guard's page: a page that comes back opens the
// pages its nested router had open, as Flutter's Navigator shows the pages
// it is given.
// Headless test: auto_route/test/guards/replace_all_guard_page_nested_pages_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page nested pages', () {
    // Steps: open Home and Shell, a page with a nested router, and push
    // Detail in Shell. The app replaces the pages with Vault, whose guard
    // sends a locked user to a pin page: the pin page shows alone. The user
    // cancels the pin page.
    // Was: Shell was back on its first page, List.
    // Should: Shell shows Detail again, and back from it shows List.
    testWidgets('The pages in the nested router of a page a guard of '
        'replaceAll set aside are back when the guard rejects', (tester) async {
      final locking = <NavigationResolver>[];
      AutoRoute page(
        String name,
        String path, {
        AutoRouteGuard? guard,
        List<AutoRoute>? children,
      }) => .new(
        page: PageInfo(
          name,
          builder: (_) => children == null
              ? Scaffold(
                  appBar: AppBar(leading: const AutoLeadingButton()),
                  body: SafeArea(child: Text(name)),
                )
              : const AutoRouter(),
        ),
        path: path,
        guards: [?guard],
        children: children,
      );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'ShellRoute',
            '/shell',
            children: [page('ListRoute', ''), page('DetailRoute', 'detail')],
          ),
          page(
            'VaultRoute',
            '/vault',
            guard: AutoRouteGuard.simple((resolver, _) {
              locking.add(resolver);
              unawaited(resolver.redirectUntil(const NamedRoute('PinRoute')));
            }),
          ),
          page('PinRoute', '/pin'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('ShellRoute')));
      await tester.pumpAndSettle();
      unawaited(
        router
            .innerRouterOf<StackRouter>('ShellRoute')
            ?.push(const NamedRoute('DetailRoute')),
      );
      await tester.pumpAndSettle();
      final detailsAtFirst = find.text('DetailRoute').evaluate().length;
      final failures = <NavigationFailure>[];
      unawaited(
        router.replaceAll([
          const NamedRoute('VaultRoute'),
        ], onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      expectTopPage(router, 'PinRoute');

      locking.singleOrNull?.reject();
      await tester.pumpAndSettle();

      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'ShellRoute',
      ]);
      expect(
        (detailsAtFirst, find.text('DetailRoute').evaluate().length),
        (1, 1),
      );
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/shell/detail');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('ListRoute'), findsOneWidget);
      await expectBrowserUrl('/shell');
    });
  });
}
