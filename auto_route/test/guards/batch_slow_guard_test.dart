import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/held_guard.dart';

// A batch showed its first pages while a later guard was still deciding, and
// they left again when that guard rejected the batch. Found by the audit of
// auto_route/lib at dev 56b73492 (finding C12).
// Steps: open Home. pushAll([ListRoute, CheckoutRoute]), where
// CheckoutRoute's async guard waits. The widget above MaterialApp.router
// rebuilds meanwhile, as on a theme change. The guard rejects, or accepts.
// Was: router.stack was [Home, List] while the guard decided, and the rebuild
// showed List, which then left again on the rejection. The batch put each
// page on the stack as its own guard accepted and took them off again when a
// later guard rejected.
// Should: the stack and the screen stay as they are until every guard has
// answered; then the batch goes in as one step, or not at all. Flutter's
// Navigator takes a new list of pages as one update, and Android applies a
// fragment transaction as one atomic set of operations. A batch on an empty
// stack, as when the app starts at a link, still opens the pages below a
// rejected one (see batch_rejected_keeps_stack_test.dart).
void main() {
  late RootStackRouter router;
  late HeldGuard guard;

  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => page(name),
  );

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  // Shows the router under a widget that can rebuild the whole app. Returns
  // the function that rebuilds it. The guard is made
  // here, inside the test.
  Future<VoidCallback> pumpRebuildableApp(WidgetTester tester) async {
    guard = HeldGuard();
    router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute('OtherRoute', '/other'),
        plainRoute('ListRoute', '/list'),
        plainRoute('CheckoutRoute', '/list/checkout', guards: [guard]),
      ],
    );
    final config = router.config();
    addTearDown(router.dispose);
    var brightness = Brightness.light;
    late StateSetter setAppState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setAppState = setState;
          return MaterialApp.router(
            theme: ThemeData(brightness: brightness),
            routerConfig: config,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    return () =>
        setAppState(() => brightness = brightness == .light ? .dark : .light);
  }

  // Rebuilds the app while the guard waits, and lets a second pass.
  Future<void> rebuildWhileDeciding(
    WidgetTester tester,
    VoidCallback rebuildApp,
  ) async {
    await tester.pump();
    rebuildApp();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  const listAndCheckout = [
    NamedRoute('ListRoute'),
    NamedRoute('CheckoutRoute'),
  ];

  testWidgets('The pages of a batch stay off the stack and the screen while '
      'a later guard decides, and when it rejects', (tester) async {
    final rebuildApp = await pumpRebuildableApp(tester);

    unawaited(router.pushAll(listAndCheckout));
    await rebuildWhileDeciding(tester, rebuildApp);

    final stackWhileDeciding = stackNames();
    final homeShownWhileDeciding = find.text('HomeRoute').evaluate().length;
    expect(router.current.name, 'HomeRoute');
    expect(find.text('ListRoute'), findsNothing);

    await guard.last.reject();
    await tester.pumpAndSettle();

    expect(router.activeGuardObserver.guardInProgress, isFalse);
    expect(stackWhileDeciding, ['HomeRoute']);
    expect(stackNames(), ['HomeRoute']);
    expect(
      (homeShownWhileDeciding, find.text('HomeRoute').evaluate().length),
      (1, 1),
    );
  });

  testWidgets('The pages of a batch go on together once the last guard lets '
      'its route through', (tester) async {
    final rebuildApp = await pumpRebuildableApp(tester);

    unawaited(router.pushAll(listAndCheckout));
    await rebuildWhileDeciding(tester, rebuildApp);

    expect(stackNames(), ['HomeRoute']);

    await guard.last.allow();
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'ListRoute', 'CheckoutRoute']);
    expect(find.text('CheckoutRoute'), findsOneWidget);
  });

  // A link with the pages below its own: the page above the pages it keeps
  // leaves only with the batch.
  testWidgets('The page a link would take off stays on screen while a later '
      'guard of the link decides', (tester) async {
    final rebuildApp = await pumpRebuildableApp(tester);
    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();

    unawaited(
      router.navigatePath('/list/checkout', includePrefixMatches: true),
    );
    await rebuildWhileDeciding(tester, rebuildApp);

    expect(stackNames(), ['HomeRoute', 'OtherRoute']);
    expect(find.text('OtherRoute'), findsOneWidget);

    await guard.last.allow();
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'ListRoute', 'CheckoutRoute']);
    expect(find.text('CheckoutRoute'), findsOneWidget);
  });
}
