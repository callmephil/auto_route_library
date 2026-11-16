import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

// The sequences of calls the tests of the web history run, with the entries
// each must leave in the browser: see history_entry_list_test.dart for where
// the expected entries come from.
/// A router for the tests of the web history: a Home page at '/', pages A to
/// D, a page whose url stays the same for any args, tabs, a nested router,
/// a page behind a guard that shows a login page, one its guard closes when
/// asked again, one that keeps no history, and one whose url the app keeps
/// out of the address bar. Its history is made by the test.
class HistoryRouter extends RootStackRouter {
  new({required this.isGuarded, required this._history});

  /// Whether each page has a guard that answers at once.
  final bool isGuarded;

  final NavigationHistory Function(StackRouter router) _history;

  /// The resolver of GuardedRoute's guard, while its login page is shown.
  NavigationResolver? loginResolver;

  /// Whether MemberRoute's guard lets its page in, or stay.
  bool isMember = true;

  @override
  late final NavigationHistory navigationHistory = _history(this);

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
    // The browser of these tests keeps a url under '/kept' out of the
    // address bar.
    _page('KeptRoute', '/kept'),
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

/// A call on the router of a sequence.
typedef HistoryCall = void Function(HistoryRouter router);

HistoryCall _push(String name, {Object? args}) =>
    (router) => unawaited(router.push(NamedRoute(name, args: args)));
HistoryCall _replace(String name) =>
    (router) => unawaited(router.replace(NamedRoute(name)));
HistoryCall _popAndPush(String name) =>
    (router) => unawaited(router.popAndPush(NamedRoute(name)));
HistoryCall _navigate(String name) =>
    (router) => unawaited(router.navigate(NamedRoute(name)));
HistoryCall _replaceAll(List<String> names) =>
    (router) => unawaited(
      router.replaceAll([for (final name in names) NamedRoute(name)]),
    );
HistoryCall _pushAll(List<String> names) =>
    (router) =>
        unawaited(router.pushAll([for (final name in names) NamedRoute(name)]));
HistoryCall _pushAndPopUntil(String name, {required String until}) =>
    (router) => unawaited(
      router.pushAndPopUntil(
        NamedRoute(name),
        predicate: (route) => route.settings.name == until,
      ),
    );
HistoryCall _tab(int index) =>
    (router) =>
        router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(index);
HistoryCall _pushMessage(String id) =>
    (router) => unawaited(
      router
          .innerRouterOf<StackRouter>('MailRoute')!
          .push(NamedRoute('MessageRoute', params: {'id': id})),
    );
void _pop(HistoryRouter router) => router.pop();
void _popMessage(HistoryRouter router) =>
    router.innerRouterOf<StackRouter>('MailRoute')!.pop();
void _popUntilRoot(HistoryRouter router) => router.popUntilRoot();
void _removeLast(HistoryRouter router) => router.removeLast();
void _pushPathState(HistoryRouter router) => router.pushPathState('state');
void _logIn(HistoryRouter router) => router.loginResolver!.next();
void _refuseLogin(HistoryRouter router) => router.loginResolver!.reject();
void _signOut(HistoryRouter router) {
  router.isMember = false;
  unawaited(router.reevaluateGuards());
}

/// How far apart the calls of a sequence are made.
enum CallGap {
  /// A frame runs between two calls.
  frame,

  /// The calls follow each other in one turn.
  none,

  /// Only microtasks run between two calls.
  microtasks,
}

const _onA = ['ARoute'];
const _onAB = ['ARoute', 'BRoute'];
const _onABC = ['ARoute', 'BRoute', 'CRoute'];

/// The pages to open over Home a frame apart, the calls, and the urls of the
/// entries they must leave, the app's first entry first.
typedef HistoryRow = (List<String>, List<HistoryCall>, List<String>);

/// Sequences with the entries Chrome held after the calls made a frame
/// apart, as the review's probes of the web history recorded them.
final Map<String, HistoryRow> recordedSequences = {
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
  'on A: replace B, pop': (_onA, [_replace('BRoute'), _pop], ['/']),
  'on A: replace B, push C': (
    _onA,
    [_replace('BRoute'), _push('CRoute')],
    ['/', '/b', '/c'],
  ),
  'on A: replace B, replace C': (
    _onA,
    [_replace('BRoute'), _replace('CRoute')],
    ['/', '/c'],
  ),
  'on A: replace B, push C, pop': (
    _onA,
    [_replace('BRoute'), _push('CRoute'), _pop],
    ['/', '/b'],
  ),
  'on A: replace B, pop, push C': (
    _onA,
    [_replace('BRoute'), _pop, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A: pop, push B': (_onA, [_pop, _push('BRoute')], ['/', '/b']),
  'on A: pop, push A': (_onA, [_pop, _push('ARoute')], ['/', '/a']),
  'on A: pop, replace C': (_onA, [_pop, _replace('CRoute')], ['/c']),
  'on A: push B, pop': (_onA, [_push('BRoute'), _pop], ['/', '/a']),
  'on A: push B, push C, pop': (
    _onA,
    [_push('BRoute'), _push('CRoute'), _pop],
    ['/', '/a', '/b'],
  ),
  'on A: push B, push C, popUntilRoot': (
    _onA,
    [_push('BRoute'), _push('CRoute'), _popUntilRoot],
    ['/'],
  ),
  'on A: push B, popAndPush C': (
    _onA,
    [_push('BRoute'), _popAndPush('CRoute')],
    ['/', '/a', '/c'],
  ),
  'on A: push B, replace C, replace D': (
    _onA,
    [_push('BRoute'), _replace('CRoute'), _replace('DRoute')],
    ['/', '/a', '/d'],
  ),
  'on A: popAndPush B': (_onA, [_popAndPush('BRoute')], ['/', '/b']),
  'on A: popAndPush B, push C': (
    _onA,
    [_popAndPush('BRoute'), _push('CRoute')],
    ['/', '/b', '/c'],
  ),
  'on A: popAndPush B, pop': (_onA, [_popAndPush('BRoute'), _pop], ['/']),
  'on A: popUntilRoot, push B': (
    _onA,
    [_popUntilRoot, _push('BRoute')],
    ['/', '/b'],
  ),
  'on A: pushAndPopUntil of B down to Home': (
    _onA,
    [_pushAndPopUntil('BRoute', until: 'HomeRoute')],
    ['/', '/b'],
  ),
  'on A: replaceAll [Home, B]': (
    _onA,
    [
      _replaceAll(['HomeRoute', 'BRoute']),
    ],
    ['/', '/b'],
  ),
  'on A: replaceAll [Home, B], push C': (
    _onA,
    [
      _replaceAll(['HomeRoute', 'BRoute']),
      _push('CRoute'),
    ],
    ['/', '/b', '/c'],
  ),
  'on A: pushAll [B, C], pop': (
    _onA,
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
  'on A, B: pop, pop': (_onAB, [_pop, _pop], ['/']),
  'on A, B: pop, push C': (_onAB, [_pop, _push('CRoute')], ['/', '/a', '/c']),
  'on A, B: pop, replace C': (_onAB, [_pop, _replace('CRoute')], ['/', '/c']),
  'on A, B: pop, pop, push C': (
    _onAB,
    [_pop, _pop, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A, B: pop, push C, pop': (
    _onAB,
    [_pop, _push('CRoute'), _pop],
    ['/', '/a'],
  ),
  'on A, B: pop, push C, push D': (
    _onAB,
    [_pop, _push('CRoute'), _push('DRoute')],
    ['/', '/a', '/c', '/d'],
  ),
  'on A, B: pop, replace C, push D': (
    _onAB,
    [_pop, _replace('CRoute'), _push('DRoute')],
    ['/', '/c', '/d'],
  ),
  'on A, B: popUntilRoot, push C': (
    _onAB,
    [_popUntilRoot, _push('CRoute')],
    ['/', '/c'],
  ),
  'on A, B: popUntilRoot, push C, push D': (
    _onAB,
    [_popUntilRoot, _push('CRoute'), _push('DRoute')],
    ['/', '/c', '/d'],
  ),
  'on A, B: popAndPush C, popAndPush D': (
    _onAB,
    [_popAndPush('CRoute'), _popAndPush('DRoute')],
    ['/', '/a', '/d'],
  ),
  'on A, B, C: pop, pop, pop': (_onABC, [_pop, _pop, _pop], ['/']),
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

/// The two sequences that ended worse than a frame apart in the web history
/// before its one writer; a frame apart Chrome held these entries.
final Map<String, HistoryRow> onceWorseSequences = {
  'on A, B: pop, pop, push C, push D, pop': (
    _onAB,
    [_pop, _pop, _push('CRoute'), _push('DRoute'), _pop],
    ['/', '/c'],
  ),
  'two pages of one route with the same url, then pop': (
    [],
    [_push('ItemRoute', args: 1), _push('ItemRoute', args: 2), _pop],
    ['/', '/item'],
  ),
};

/// Sequences with the entries as Flutter's Navigator holds them: the
/// entries Chrome held a frame apart kept a page the app had closed, which
/// back then showed again.
final Map<String, HistoryRow> nativeSequences = {
  // navigate to a page underneath is Navigator.popUntil.
  'on A: navigate Home, push B': (
    _onA,
    [_navigate('HomeRoute'), _push('BRoute')],
    ['/', '/b'],
  ),
  'on A, B: navigate A, push C': (
    _onAB,
    [_navigate('ARoute'), _push('CRoute')],
    ['/', '/a', '/c'],
  ),
  'on A: push B, navigate A, push C': (
    _onA,
    [_push('BRoute'), _navigate('ARoute'), _push('CRoute')],
    ['/', '/a', '/c'],
  ),
  'push A, navigate Home': (
    [],
    [_push('ARoute'), _navigate('HomeRoute')],
    ['/'],
  ),
  // removeLast, removeWhere and removeUntil are Navigator.removeRoute.
  'on A: removeLast, push B': (
    _onA,
    [_removeLast, _push('BRoute')],
    ['/', '/b'],
  ),
  'on A, B, C: removeWhere B': (
    _onABC,
    [(router) => router.removeWhere((route) => route.name == 'BRoute')],
    ['/', '/a', '/c'],
  ),
  'on A, B, C: removeUntil A': (
    _onABC,
    [(router) => router.removeUntil((route) => route.name == 'ARoute')],
    ['/', '/a'],
  ),
  // replaceAll is Navigator.pushAndRemoveUntil with no route kept.
  'on A: push B, replaceAll [C]': (
    _onA,
    [
      _push('BRoute'),
      _replaceAll(['CRoute']),
    ],
    ['/c'],
  ),
  'on A: replaceAll [C], push B': (
    _onA,
    [
      _replaceAll(['CRoute']),
      _push('BRoute'),
    ],
    ['/c', '/b'],
  ),
  'on A: replaceAll [C], replaceAll [B]': (
    _onA,
    [
      _replaceAll(['CRoute']),
      _replaceAll(['BRoute']),
    ],
    ['/b'],
  ),
  'on A, B, C: pushAndPopUntil of D down to A': (
    _onABC,
    [_pushAndPopUntil('DRoute', until: 'ARoute')],
    ['/', '/a', '/d'],
  ),
};

/// Sequences where a guard decides, or a page keeps no history. Their calls
/// are a frame apart: the test answers for the guard once its page is shown.
/// Each is one of the router's ways to report a replace.
final Map<String, HistoryRow> replaceSequences = {
  // The guard's page leaves as the guard answers, and the guarded page takes
  // its place: a redirect, as Navigator.pushReplacement.
  'on A: push the guarded page, whose guard shows Login': (
    _onA,
    [_push('GuardedRoute')],
    ['/', '/a', '/login'],
  ),
  'on A: push the guarded page, then log in': (
    _onA,
    [_push('GuardedRoute'), _logIn],
    ['/', '/a', '/g'],
  ),
  'on A: push B, push the guarded page, then log in': (
    _onA,
    [_push('BRoute'), _push('GuardedRoute'), _logIn],
    ['/', '/a', '/b', '/g'],
  ),
  'on A: push the guarded page, then refuse to log in': (
    _onA,
    [_push('GuardedRoute'), _refuseLogin],
    ['/', '/a'],
  ),
  'on A: replace with the guarded page, then log in': (
    _onA,
    [_replace('GuardedRoute'), _logIn],
    ['/', '/g'],
  ),
  // The app's own replaceAll has the pages leave for the guard's page, as
  // after a sign-out, then for the guarded page.
  'on A: replaceAll with the guarded page, whose guard shows Login': (
    _onA,
    [
      _replaceAll(['GuardedRoute']),
    ],
    ['/login'],
  ),
  'on A: replaceAll with the guarded page, then log in': (
    _onA,
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
    _onA,
    [_push('NoHistoryRoute'), _push('BRoute'), _pop],
    ['/', '/a'],
  ),
};
