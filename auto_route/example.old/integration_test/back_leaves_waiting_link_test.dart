import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, back() while the guard of a link still decides leaves the
// link: the guard's answer then changes nothing. Before, back() dropped the
// link's entry but did not call the link off, so the guard's yes showed the
// link's page anyway (callmephil/auto_route_library#32).
// Headless test: auto_route/test/back_leaves_waiting_link_test.dart.
//
// Native behavior this holds to: Android's back finishes the activity a link
// started, and it does not come back; in the HTML standard, a traversal
// aborts the ongoing navigation. Off the web only: on the web, back() is the
// browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back() while the guard of a link decides', () {
    // Steps: on Home, open Tabs on tab One, or open A. The platform hands
    // the app a link to tab Two, or to Detail, whose guard waits. Call
    // back(), then let the guard say yes or no.
    // Was: after the yes, tab Two or Detail showed anyway.
    // Should: One, or A, stays on screen, and back() goes on to Home.
    for (final (opened, link, shown, url) in [
      ('Tabs', '/tabs/two', 'One', '/tabs/one'),
      ('A', '/detail', 'A', '/a'),
    ]) {
      for (final saysYes in [true, false]) {
        testWidgets(
          'back() leaves the link to $link, and a '
          '${saysYes ? 'yes' : 'no'} then changes nothing',
          (tester) async {
            final answers = <Completer<bool>>[];
            final router = _router(answers);
            await pumpRouterConfigApp(tester, router.config());
            unawaited(router.push(NamedRoute<Object?>(opened)));
            await tester.pumpAndSettle();
            unawaited(tester.binding.handlePushRoute(link));
            await tester.pumpAndSettle();

            router.back();
            await tester.pumpAndSettle();
            final afterBack = '${router.topRoute.name} ${router.currentUrl}';
            expect(answers, hasLength(1), reason: 'the guard was asked once');
            answers.lastOrNull?.complete(saysYes);
            await tester.pumpAndSettle();

            expect(
              (afterBack, '${router.topRoute.name} ${router.currentUrl}'),
              ('$shown $url', '$shown $url'),
            );
            router.back();
            await tester.pumpAndSettle();
            expect(router.currentUrl, '/');
          },
          skip: kIsWeb,
        );
      }
    }
  });
}

NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Text(name),
);

// Home, A, Detail, and Tabs with the tabs One and Two. Detail and Two have
// a guard that waits for the next of [answers].
RootStackRouter _router(List<Completer<bool>> answers) {
  final guard = AutoRouteGuard.simple((resolver, _) async {
    final answer = Completer<bool>();
    answers.add(answer);
    if (await answer.future) {
      resolver.next();
    } else {
      resolver.reject();
    }
  });
  return .build(
    routes: [
      _page('Home', '/'),
      _page('A', '/a'),
      _page('Detail', '/detail', guard: guard),
      NamedRouteDef(
        name: 'Tabs',
        path: '/tabs',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [NamedRoute<Object?>('One'), NamedRoute<Object?>('Two')],
          ),
        ),
        children: [
          _page('One', 'one'),
          _page('Two', 'two', guard: guard),
        ],
      ),
    ],
  );
}
