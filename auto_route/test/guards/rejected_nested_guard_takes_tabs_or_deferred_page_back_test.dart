import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// callmephil/auto_route_library#6: a new page that holds tabs, or that
// builds its nested router in a DeferredWidget, stayed open when a guard
// of its nested router said no. A new page whose nested router is a plain
// stack router was taken back off already.
// Setup: Home at '/', A at '/a'. TabMail at '/tabmail' holds the tabs Inbox
// and Message; either Message has a guard, or it holds a stack router with
// a first page and the guarded page Gx. Mail at '/mail' builds its stack
// router in a DeferredWidget, with Inbox as its first page and the guarded
// page Message by id. The test answers each guard.
// Steps: push A over Home, or open a dialog over Home. Go to the guarded
// page with navigatePath, navigate or a link. The guard says no or yes.
// Was: after a no, TabMail stayed on its first tab or on Message's first
// page, and Mail on its inbox, once its library loaded; a link from Home,
// A closed A, and the dialog closed. onFailure heard nothing.
// Should: after a no, the stack, the url and the dialog are as before the
// navigation, and onFailure hears the rejection once. After a yes, the page
// shows with the guarded tab or page.
// Off the web a link brings the pages below its own, and closes A once the
// guards let it in. On the web it brings its own page alone, over A.
// Native behavior this holds to: on the web a canceled navigation leaves the
// document and its url on screen: the HTML standard aborts the navigation
// when its navigate event is canceled. Android's conditional navigation pops
// back from a destination whose check fails.
final _guard = HeldGuard();

NamedRouteDef _page(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(body: Text(name)),
);

enum _Call { navigatePath, navigate, link }

enum _Kind { tabGuard, guardInTab, deferred }

late Completer<void> _library;

RootStackRouter _router() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('ARoute', '/a'),
    NamedRouteDef(
      name: 'TabMailRoute',
      path: '/tabmail',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute('InboxTab'), NamedRoute('MessageTab')],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'InboxTab',
          path: 'inbox',
          builder: (_, _) => const Text('InboxTab'),
        ),
        NamedRouteDef(
          name: 'MessageTab',
          path: 'message',
          guards: [_guard],
          builder: (_, _) => const Text('MessageTab'),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'StackTabsRoute',
      path: '/stacktabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute('FirstTab'), NamedRoute('ThreadTab')],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'FirstTab',
          path: 'first',
          builder: (_, _) => const Text('FirstTab'),
        ),
        NamedRouteDef(
          name: 'ThreadTab',
          path: 'thread',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'ThreadListRoute',
              path: '',
              builder: (_, _) => const Text('ThreadList'),
            ),
            NamedRouteDef(
              name: 'GxRoute',
              path: 'gx',
              guards: [_guard],
              builder: (_, _) => const Text('Gx'),
            ),
          ],
        ),
      ],
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => DeferredWidget(
        () => _library.future,
        () => const Scaffold(body: AutoRouter()),
      ),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('Inbox'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: ':id',
          guards: [_guard],
          builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
        ),
      ],
    ),
  ],
);

String _path(_Kind kind) => switch (kind) {
  .tabGuard => '/tabmail/message',
  .guardInTab => '/stacktabs/thread/gx',
  .deferred => '/mail/77',
};

PageRouteInfo _route(_Kind kind) => switch (kind) {
  .tabGuard => const NamedRoute(
    'TabMailRoute',
    children: [NamedRoute('MessageTab')],
  ),
  .guardInTab => const NamedRoute(
    'StackTabsRoute',
    children: [
      NamedRoute('ThreadTab', children: [NamedRoute('GxRoute')]),
    ],
  ),
  .deferred => const NamedRoute(
    'MailRoute',
    children: [
      NamedRoute('MessageRoute', params: {'id': '77'}),
    ],
  ),
};

String _shown(_Kind kind) => switch (kind) {
  .tabGuard => 'MessageTab',
  .guardInTab => 'Gx',
  .deferred => 'Mail 77',
};

List<String> _names(StackRouter router) => [
  for (final page in router.stack) page.routeData.name,
];

String _dialog() {
  if (find.text('Draft').hitTestable().evaluate().isNotEmpty) return 'shown';
  if (find.text('Draft', skipOffstage: false).evaluate().isNotEmpty) {
    return 'open';
  }
  return 'closed';
}

void main() {
  for (final kind in _Kind.values) {
    for (final fromA in [true, false]) {
      for (final call in _Call.values) {
        for (final isYes in [false, true]) {
          testWidgets('${kind.name}, from ${fromA ? 'Home, A' : 'a dialog '
                        'over Home'}, ${call.name}, the guard says '
              '${isYes ? 'yes' : 'no'}', (tester) async {
            _guard
              ..clear()
              ..holdCall();
            _library = Completer<void>();
            final router = _router();
            await pumpRouterConfigApp(tester, router.config());
            if (fromA) {
              unawaited(router.push(const NamedRoute('ARoute')));
            } else {
              showDialog<void>(
                context: router.navigatorKey.currentContext!,
                builder: (_) => const AlertDialog(title: Text('Draft')),
              );
            }
            await tester.pumpAndSettle();
            final stackBefore = _names(router);
            final urlBefore = router.currentUrl;
            final failures = <NavigationFailure>[];

            switch (call) {
              case .navigatePath:
                unawaited(
                  router.navigatePath(_path(kind), onFailure: failures.add),
                );
              case .navigate:
                unawaited(
                  router.navigate(_route(kind), onFailure: failures.add),
                );
              case .link:
                unawaited(tester.binding.handlePushRoute(_path(kind)));
            }
            if (kind != .deferred) await tester.pumpAndSettle();
            if (kind == .deferred) {
              // The placeholder spins while the library loads.
              for (var i = 0; i < 5; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(_guard.askCount, 0, reason: 'the library loads');
              _library.complete();
              await tester.pumpAndSettle();
            }
            expect(_guard.askCount, 1);
            if (!fromA) {
              expect(_dialog(), isNot('closed'), reason: 'while deciding');
            }

            if (isYes) {
              await _guard.last.allow();
            } else {
              await _guard.last.reject();
            }
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            // Off the web a link brings Home below its own page.
            final isLinkAlone = call == .link && kIsWeb;
            if (!isYes) {
              expect(_names(router), stackBefore);
              expect(router.currentUrl, urlBefore);
              if (!fromA) expect(_dialog(), 'shown');
              expect(failures, hasLength(call == .link ? 0 : 1));
              if (failures.isNotEmpty) {
                expect(failures.single, isA<RejectedByGuardFailure>());
              }
              return;
            }
            expect(find.text(_shown(kind)), findsOneWidget);
            expect(router.currentUrl, _path(kind));
            expect(router.currentUrl, isNot(urlBefore));
            expect(_names(router), isNot(stackBefore));
            expect(failures, isEmpty);
            if (fromA && call == .link && !isLinkAlone) {
              expect(_names(router), ['HomeRoute', _route(kind).routeName]);
            }
            if (!fromA && call == .link) expect(_dialog(), 'closed');
          });
        }
      }
    }
  }
}
