import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// The entries the browser's history should hold after calls on a router,
// as HistoryEntryList keeps them from the url states the router reports, with
// no browser: the list is the web history's account of what back must walk.
//
// Each row is a sequence of calls and the urls of the entries it must leave,
// the app's first entry first. The expected entries are not taken from the
// list: they are the entries Chrome held after the same calls made a frame
// apart, as the review's probes of the web history recorded them, or, in the
// rows marked native, what Flutter's Navigator holds, where the recorded
// entries kept a page the app had closed. Every row runs a frame apart, in
// one turn and microtasks apart, and must leave the same entries each way.
//
// Native behavior this holds to: Flutter's Navigator, which Android's system
// back and the iOS back gesture walk. Back closes the page on top; a page
// that was popped, replaced or removed never comes back; pushReplacement
// leaves the page under as the way back; pushAndRemoveUntil leaves only the
// routes it kept. An entry of its own for each tab shown and for
// history.pushState is the web's, the HTML History API.
class _ListHistory extends NavigationHistory {
  new(this.router);

  @override
  final StackRouter router;

  late final list = HistoryEntryList(
    isPageOpen: (pageId) => controllerOfPage(pageId) != null,
  );

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    final shown = list.show(newState);
    super.onNewUrlState(
      shown.copyWith(shouldReplace: newState.shouldReplace),
      notify: notify,
    );
  }

  @override
  void pushPathState(Object? state) {
    final newState = UrlState(
      urlState.uri,
      urlState.segments,
      pathState: state,
    );
    if (newState == urlState) return;
    list.add(newState);
    super.onNewUrlState(newState);
  }

  @override
  Object? get pathState => urlState.pathState;

  @override
  bool get canNavigateBack => length > 1;

  @override
  int get length => list.entries.length;

  @override
  void back() => throw UnimplementedError();

  @override
  void forward() => throw UnimplementedError();
}

class _Router extends RootStackRouter {
  new({required this.isGuarded});

  final bool isGuarded;

  // The resolver of GuardedRoute's guard, while its login page is shown.
  NavigationResolver? loginResolver;

  // Whether MemberRoute's guard lets its page in, or stay.
  bool isMember = true;

  @override
  late final _ListHistory navigationHistory = .new(this);

  NamedRouteDef _page(String name, String path) => .new(
    name: name,
    path: path,
    guards: [
      if (isGuarded) AutoRouteGuard.simple((resolver, _) => resolver.next()),
    ],
    builder: (_, data) => Text('$name ${data.args ?? ''}'),
  );

  @override
  late final List<AutoRoute> routes = [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    _page('ARoute', '/a'),
    _page('BRoute', '/b'),
    _page('CRoute', '/c'),
    _page('DRoute', '/d'),
    _page('ItemRoute', '/item'),
    _page('LoginRoute', '/login'),
    NamedRouteDef(
      name: 'GuardedRoute',
      path: '/g',
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          loginResolver = resolver;
          unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
        }),
      ],
      builder: (_, _) => const Text('GuardedRoute'),
    ),
    NamedRouteDef(
      name: 'MemberRoute',
      path: '/m',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => isMember ? resolver.next() : resolver.reject(),
        ),
      ],
      builder: (_, _) => const Text('MemberRoute'),
    ),
    NamedRouteDef(
      name: 'NoHistoryRoute',
      path: '/k',
      keepHistory: false,
      builder: (_, _) => const Text('NoHistoryRoute'),
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => const AutoTabsRouter(
        routes: [NamedRoute('FirstTab'), NamedRoute('SecondTab')],
      ),
      children: [_page('FirstTab', 'first'), _page('SecondTab', 'second')],
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const AutoRouter(),
      children: [_page('InboxRoute', ''), _page('MessageRoute', ':id')],
    ),
  ];
}

typedef _Call = void Function(_Router router);

_Call _push(String name, {Object? args}) =>
    (router) => unawaited(router.push(NamedRoute(name, args: args)));
_Call _replace(String name) =>
    (router) => unawaited(router.replace(NamedRoute(name)));
_Call _popAndPush(String name) =>
    (router) => unawaited(router.popAndPush(NamedRoute(name)));
_Call _navigate(String name) =>
    (router) => unawaited(router.navigate(NamedRoute(name)));
_Call _replaceAll(List<String> names) =>
    (router) => unawaited(
      router.replaceAll([for (final name in names) NamedRoute(name)]),
    );
_Call _pushAll(List<String> names) =>
    (router) =>
        unawaited(router.pushAll([for (final name in names) NamedRoute(name)]));
_Call _pushAndPopUntil(String name, {required String until}) =>
    (router) => unawaited(
      router.pushAndPopUntil(
        NamedRoute(name),
        predicate: (route) => route.settings.name == until,
      ),
    );
_Call _tab(int index) =>
    (router) =>
        router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(index);
_Call _pushMessage(String id) =>
    (router) => unawaited(
      router
          .innerRouterOf<StackRouter>('MailRoute')!
          .push(NamedRoute('MessageRoute', params: {'id': id})),
    );
void _pop(_Router router) => router.pop();
void _popMessage(_Router router) =>
    router.innerRouterOf<StackRouter>('MailRoute')!.pop();
void _popUntilRoot(_Router router) => router.popUntilRoot();
void _removeLast(_Router router) => router.removeLast();
void _pushPathState(_Router router) => router.pushPathState('state');
void _logIn(_Router router) => router.loginResolver!.next();
void _refuseLogin(_Router router) => router.loginResolver!.reject();
void _signOut(_Router router) {
  router.isMember = false;
  unawaited(router.reevaluateGuards());
}

enum _Gap { frame, none, microtasks }

const _a = ['ARoute'];
const _ab = ['ARoute', 'BRoute'];
const _abc = ['ARoute', 'BRoute', 'CRoute'];

// The pages to open over Home a frame apart, the calls, and the urls of the
// entries they must leave.
typedef _Row = (List<String>, List<_Call>, List<String>);

// As Chrome held them after the calls made a frame apart.
final Map<String, _Row> _recorded = {
  'push A, push B': ([], [_push('ARoute'), _push('BRoute')], ['/', '/a', '/b']),
  'push A, push B, push C': (
    [],
    [_push('ARoute'), _push('BRoute'), _push('CRoute')],
    ['/', '/a', '/b', '/c'],
  ),
  'push A, pop': ([], [_push('ARoute'), _pop], ['/']),
  'push A, pop, push B': (
    [],
    [_push('ARoute'), _pop, _push('BRoute')],
    ['/', '/b'],
  ),
  'push A, replace B': ([], [_push('ARoute'), _replace('BRoute')], ['/', '/b']),
  'push A, replace B, push C': (
    [],
    [_push('ARoute'), _replace('BRoute'), _push('CRoute')],
    ['/', '/b', '/c'],
  ),
  'push A, push B, replace C, pop': (
    [],
    [_push('ARoute'), _push('BRoute'), _replace('CRoute'), _pop],
    ['/', '/a'],
  ),
  'on A: replace B, pop': (_a, [_replace('BRoute'), _pop], ['/']),
  'on A: replace B, push C': (
    _a,
    [_replace('BRoute'), _push('CRoute')],
    ['/', '/b', '/c'],
  ),
  'on A: replace B, replace C': (
    _a,
    [_replace('BRoute'), _replace('CRoute')],
    ['/', '/c'],
  ),
  'on A: replace B, push C, pop': (
    _a,
    [_replace('BRoute'), _push('CRoute'), _pop],
    ['/', '/b'],
  ),
  'on A: replace B, pop, push C': (
    _a,
    [_replace('BRoute'), _pop, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A: pop, push B': (_a, [_pop, _push('BRoute')], ['/', '/b']),
  'on A: pop, push A': (_a, [_pop, _push('ARoute')], ['/', '/a']),
  'on A: pop, replace C': (_a, [_pop, _replace('CRoute')], ['/c']),
  'on A: push B, pop': (_a, [_push('BRoute'), _pop], ['/', '/a']),
  'on A: push B, push C, pop': (
    _a,
    [_push('BRoute'), _push('CRoute'), _pop],
    ['/', '/a', '/b'],
  ),
  'on A: push B, push C, popUntilRoot': (
    _a,
    [_push('BRoute'), _push('CRoute'), _popUntilRoot],
    ['/'],
  ),
  'on A: push B, popAndPush C': (
    _a,
    [_push('BRoute'), _popAndPush('CRoute')],
    ['/', '/a', '/c'],
  ),
  'on A: push B, replace C, replace D': (
    _a,
    [_push('BRoute'), _replace('CRoute'), _replace('DRoute')],
    ['/', '/a', '/d'],
  ),
  'on A: popAndPush B': (_a, [_popAndPush('BRoute')], ['/', '/b']),
  'on A: popAndPush B, push C': (
    _a,
    [_popAndPush('BRoute'), _push('CRoute')],
    ['/', '/b', '/c'],
  ),
  'on A: popAndPush B, pop': (_a, [_popAndPush('BRoute'), _pop], ['/']),
  'on A: popUntilRoot, push B': (
    _a,
    [_popUntilRoot, _push('BRoute')],
    ['/', '/b'],
  ),
  'on A: pushAndPopUntil of B down to Home': (
    _a,
    [_pushAndPopUntil('BRoute', until: 'HomeRoute')],
    ['/', '/b'],
  ),
  'on A: replaceAll [Home, B]': (
    _a,
    [
      _replaceAll(['HomeRoute', 'BRoute']),
    ],
    ['/', '/b'],
  ),
  'on A: replaceAll [Home, B], push C': (
    _a,
    [
      _replaceAll(['HomeRoute', 'BRoute']),
      _push('CRoute'),
    ],
    ['/', '/b', '/c'],
  ),
  'on A: pushAll [B, C], pop': (
    _a,
    [
      _pushAll(['BRoute', 'CRoute']),
      _pop,
    ],
    ['/', '/a', '/b'],
  ),
  'push A, pushAndPopUntil of B down to Home': (
    [],
    [_push('ARoute'), _pushAndPopUntil('BRoute', until: 'HomeRoute')],
    ['/', '/b'],
  ),
  'on A, B: pop, pop': (_ab, [_pop, _pop], ['/']),
  'on A, B: pop, push C': (_ab, [_pop, _push('CRoute')], ['/', '/a', '/c']),
  'on A, B: pop, replace C': (_ab, [_pop, _replace('CRoute')], ['/', '/c']),
  'on A, B: pop, pop, push C': (
    _ab,
    [_pop, _pop, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A, B: pop, push C, pop': (
    _ab,
    [_pop, _push('CRoute'), _pop],
    ['/', '/a'],
  ),
  'on A, B: pop, push C, push D': (
    _ab,
    [_pop, _push('CRoute'), _push('DRoute')],
    ['/', '/a', '/c', '/d'],
  ),
  'on A, B: pop, replace C, push D': (
    _ab,
    [_pop, _replace('CRoute'), _push('DRoute')],
    ['/', '/c', '/d'],
  ),
  'on A, B: popUntilRoot, push C': (
    _ab,
    [_popUntilRoot, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A, B: popUntilRoot, push C, push D': (
    _ab,
    [_popUntilRoot, _push('CRoute'), _push('DRoute')],
    ['/', '/c', '/d'],
  ),
  'on A, B: popAndPush C, popAndPush D': (
    _ab,
    [_popAndPush('CRoute'), _popAndPush('DRoute')],
    ['/', '/a', '/d'],
  ),
  'on A, B, C: pop, pop, pop': (_abc, [_pop, _pop, _pop], ['/']),
  'two pages of one route, with other args and the same url': (
    [],
    [_push('ItemRoute', args: 1), _push('ItemRoute', args: 2)],
    ['/', '/item', '/item'],
  ),
  'push B, then pushPathState': (
    [],
    [_push('BRoute'), _pushPathState],
    ['/', '/b', '/b'],
  ),
  'on Tabs: second tab, push A': (
    ['TabsRoute'],
    [_tab(1), _push('ARoute')],
    ['/', '/tabs/first', '/tabs/second', '/a'],
  ),
  'on Tabs: second tab, first tab': (
    ['TabsRoute'],
    [_tab(1), _tab(0)],
    ['/', '/tabs/first', '/tabs/second', '/tabs/first'],
  ),
  'on Mail: nested push of a message, root push A': (
    ['MailRoute'],
    [_pushMessage('1'), _push('ARoute')],
    ['/', '/mail', '/mail/1', '/a'],
  ),
  'on Mail: root push A, pop, nested push of a message': (
    ['MailRoute'],
    [_push('ARoute'), _pop, _pushMessage('1')],
    ['/', '/mail', '/mail/1'],
  ),
  'on Mail with a message: nested pop, root push A': (
    ['MailRoute'],
    [_pushMessage('1'), _popMessage, _push('ARoute')],
    ['/', '/mail', '/a'],
  ),
};

// The two sequences that ended worse than a frame apart in the web history
// this list replaces; a frame apart Chrome held these entries.
final Map<String, _Row> _onceWorse = {
  'on A, B: pop, pop, push C, push D, pop': (
    _ab,
    [_pop, _pop, _push('CRoute'), _push('DRoute'), _pop],
    ['/', '/c'],
  ),
  'two pages of one route with the same url, then pop': (
    [],
    [_push('ItemRoute', args: 1), _push('ItemRoute', args: 2), _pop],
    ['/', '/item'],
  ),
};

// As Flutter's Navigator holds them: the entries Chrome held a frame apart
// kept a page the app had closed, which back then showed again.
final Map<String, _Row> _native = {
  // navigate to a page underneath is Navigator.popUntil.
  'on A: navigate Home, push B': (
    _a,
    [_navigate('HomeRoute'), _push('BRoute')],
    ['/', '/b'],
  ),
  'on A, B: navigate A, push C': (
    _ab,
    [_navigate('ARoute'), _push('CRoute')],
    ['/', '/a', '/c'],
  ),
  'on A: push B, navigate A, push C': (
    _a,
    [_push('BRoute'), _navigate('ARoute'), _push('CRoute')],
    ['/', '/a', '/c'],
  ),
  'push A, navigate Home': (
    [],
    [_push('ARoute'), _navigate('HomeRoute')],
    ['/'],
  ),
  // removeLast, removeWhere and removeUntil are Navigator.removeRoute.
  'on A: removeLast, push B': (_a, [_removeLast, _push('BRoute')], ['/', '/b']),
  'on A, B, C: removeWhere B': (
    _abc,
    [(router) => router.removeWhere((route) => route.name == 'BRoute')],
    ['/', '/a', '/c'],
  ),
  'on A, B, C: removeUntil A': (
    _abc,
    [(router) => router.removeUntil((route) => route.name == 'ARoute')],
    ['/', '/a'],
  ),
  // replaceAll is Navigator.pushAndRemoveUntil with no route kept.
  'on A: push B, replaceAll [C]': (
    _a,
    [
      _push('BRoute'),
      _replaceAll(['CRoute']),
    ],
    ['/c'],
  ),
  'on A: replaceAll [C], push B': (
    _a,
    [
      _replaceAll(['CRoute']),
      _push('BRoute'),
    ],
    ['/c', '/b'],
  ),
  'on A: replaceAll [C], replaceAll [B]': (
    _a,
    [
      _replaceAll(['CRoute']),
      _replaceAll(['BRoute']),
    ],
    ['/b'],
  ),
  'on A, B, C: pushAndPopUntil of D down to A': (
    _abc,
    [_pushAndPopUntil('DRoute', until: 'ARoute')],
    ['/', '/a', '/d'],
  ),
};

// Sequences where a guard decides, or a page keeps no history. Their calls
// are a frame apart: the test answers for the guard once its page is shown.
// Each is one of the router's ways to report a replace.
final Map<String, _Row> _replaces = {
  // The guard's page leaves as the guard answers, and the guarded page takes
  // its place: a redirect, as Navigator.pushReplacement.
  'on A: push the guarded page, whose guard shows Login': (
    _a,
    [_push('GuardedRoute')],
    ['/', '/a', '/login'],
  ),
  'on A: push the guarded page, then log in': (
    _a,
    [_push('GuardedRoute'), _logIn],
    ['/', '/a', '/g'],
  ),
  'on A: push B, push the guarded page, then log in': (
    _a,
    [_push('BRoute'), _push('GuardedRoute'), _logIn],
    ['/', '/a', '/b', '/g'],
  ),
  'on A: push the guarded page, then refuse to log in': (
    _a,
    [_push('GuardedRoute'), _refuseLogin],
    ['/', '/a'],
  ),
  'on A: replace with the guarded page, then log in': (
    _a,
    [_replace('GuardedRoute'), _logIn],
    ['/', '/g'],
  ),
  // The app's own replaceAll has the pages leave for the guard's page, as
  // after a sign-out, then for the guarded page.
  'on A: replaceAll with the guarded page, whose guard shows Login': (
    _a,
    [
      _replaceAll(['GuardedRoute']),
    ],
    ['/login'],
  ),
  'on A: replaceAll with the guarded page, then log in': (
    _a,
    [
      _replaceAll(['GuardedRoute']),
      _logIn,
    ],
    ['/g'],
  ),
  // A page its guard closes when asked again leaves as a pop does.
  'on the member page: the guard closes it when asked again': (
    ['MemberRoute'],
    [_signOut],
    ['/'],
  ),
  'on A, the member page: the guard closes it when asked again': (
    ['ARoute', 'MemberRoute'],
    [_signOut],
    ['/', '/a'],
  ),
  // A page that keeps no history leaves as a page goes on above it.
  'push the page that keeps no history, push B': (
    [],
    [_push('NoHistoryRoute'), _push('BRoute')],
    ['/', '/b'],
  ),
  'on A: push the page that keeps no history, push B, pop': (
    _a,
    [_push('NoHistoryRoute'), _push('BRoute'), _pop],
    ['/', '/a'],
  ),
};

Future<List<String>> _entriesAfter(
  WidgetTester tester,
  _Row row,
  _Gap gap, {
  required bool isGuarded,
}) async {
  final (opens, calls, _) = row;
  final router = _Router(isGuarded: isGuarded);
  addTearDown(router.navigationHistory.dispose);
  await pumpRouterApp(tester, router);
  for (final name in opens) {
    unawaited(router.push(NamedRoute(name)));
    await tester.pumpAndSettle();
  }
  for (final (index, call) in calls.indexed) {
    call(router);
    if (index == calls.length - 1) break;
    switch (gap) {
      case .frame:
        await tester.pumpAndSettle();
      case .none:
        break;
      case .microtasks:
        for (var i = 0; i < 30; i++) {
          await Future<void>.value();
        }
    }
  }
  await tester.pumpAndSettle();
  return [
    for (final entry in router.navigationHistory.list.entries)
      if (entry.url.isEmpty) '/' else entry.url,
  ];
}

void main() {
  for (final (source, rows) in [
    ('as Chrome held them a frame apart', _recorded),
    ('once worse than a frame apart', _onceWorse),
    ('as the Navigator holds them', _native),
  ]) {
    group('The entries $source:', () {
      for (final MapEntry(key: name, value: row) in rows.entries) {
        for (final (label, gap) in [
          ('a frame apart', _Gap.frame),
          ('in one turn', _Gap.none),
          ('microtasks apart', _Gap.microtasks),
        ]) {
          testWidgets('$name, $label', (tester) async {
            expect(
              await _entriesAfter(tester, row, gap, isGuarded: false),
              row.$3,
            );
          });
        }
        testWidgets('$name, in one turn, with guards that answer at once', (
          tester,
        ) async {
          expect(
            await _entriesAfter(tester, row, .none, isGuarded: true),
            row.$3,
          );
        });
      }
    });
  }

  group('The entries where the router reports a replace:', () {
    for (final MapEntry(key: name, value: row) in _replaces.entries) {
      testWidgets(name, (tester) async {
        expect(
          await _entriesAfter(tester, row, .frame, isGuarded: false),
          row.$3,
        );
      });
    }
  });
}
