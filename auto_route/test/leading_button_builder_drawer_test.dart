import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// On a page that can pop and whose Scaffold has a drawer,
// AutoLeadingButton(builder:) is told LeadingType.drawer, the button the
// default AutoLeadingButton shows there (control).
// Steps: Home, push a page with a drawer; look at its leading button.
// Before the fix the builder was told LeadingType.back, with an action that
// popped: it returned from the can-pop branch before the drawer was looked
// at, while the default button fell through and the drawer button replaced
// the back button.
// Native behavior this holds to: Flutter's AppBar shows the DrawerButton on
// a page with a drawer, and the back button only otherwise
// (material/app_bar.dart, `if (hasDrawer) ... else if
// (parentRoute?.impliesAppBarDismissal ?? false)`).
void main() {
  RootStackRouter buildRouter(Widget leading) => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      NamedRouteDef(
        name: 'DrawerRoute',
        path: '/drawer',
        builder: (_, _) => Scaffold(
          appBar: AppBar(leading: leading),
          drawer: const Drawer(child: Text('Drawer content')),
          body: const Text('Page with a drawer'),
        ),
      ),
    ],
  );

  testWidgets(
    'Control: the default button shows the drawer button on a page that can '
    'pop',
    (tester) async {
      final router = buildRouter(const AutoLeadingButton());
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('DrawerRoute')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Drawer content'), findsOneWidget);
    },
  );

  testWidgets(
    'The builder is told drawer on a page that can pop and has a drawer',
    (tester) async {
      final types = <LeadingType>[];
      final router = buildRouter(
        AutoLeadingButton(
          builder: (context, type, action) {
            types.add(type);
            return IconButton(
              onPressed: action,
              icon: Text('leading: ${type.name}'),
            );
          },
        ),
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('DrawerRoute')));
      await tester.pumpAndSettle();

      expect(types.lastOrNull, LeadingType.drawer);
      await tester.tap(find.textContaining('leading:'));
      await tester.pumpAndSettle();
      expect(find.text('Drawer content'), findsOneWidget);
    },
  );
}
