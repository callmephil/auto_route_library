import 'package:auto_route/auto_route.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// An AutoRouter whose first page has a guard, built and dropped in the same
// frame, threw "Null check operator used on a null value" after the frame.
// Found by the audit of auto_route/lib at dev 56b73492, an unproven idea of
// the first round, proven in round 2.
// Cause: AutoRouterState.didChangeDependencies defers the setup of a guarded
// first page to after the frame, and that callback read `_controller!`,
// which dispose had cleared. The callback beside it, for a first page with no
// guard, already read `_controller?`.
// Setup: a host page lays its child out twice in one frame, first narrow and
// then at its own size, as a scrolling viewport does after a scroll offset
// correction. A LayoutBuilder shows the nested router only at the narrow
// width, so the router is built and then dropped within the frame.
// Should: nothing is thrown, and the router that left sets nothing up. A
// widget that leaves the tree before a callback it scheduled runs is skipped
// by that callback, as Flutter's own widgets check `mounted`.
class _LaysOutTwice extends SingleChildRenderObjectWidget {
  const new({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLaysOutTwice();
}

class _RenderLaysOutTwice extends RenderProxyBox {
  @override
  void performLayout() {
    child!
      ..layout(const BoxConstraints.tightFor(width: _kNarrow, height: 100))
      ..layout(constraints, parentUsesSize: true);
    size = child!.size;
  }
}

const _kNarrow = 123.0;

class _AllowGuard extends AutoRouteGuard {
  const new();

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    resolver.next();
  }
}

void main() {
  testWidgets(
    'A nested router with a guarded first page, dropped in the frame that '
    'built it, throws nothing',
    (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => _LaysOutTwice(
              child: LayoutBuilder(
                builder: (_, constraints) => constraints.maxWidth == _kNarrow
                    ? const AutoRouter()
                    : const Text('Host'),
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'InnerRoute',
                path: '',
                guards: const [_AllowGuard()],
                builder: (_, _) => const Text('Inner'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      expect(tester.takeException(), isNull);
      expect(find.text('Host'), findsOneWidget);
      expect(router.innerRouterOf<StackRouter>('HostRoute'), isNull);
    },
  );
}
