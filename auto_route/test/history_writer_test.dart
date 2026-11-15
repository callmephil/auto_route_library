import 'dart:collection';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_writer.dart';
import 'package:flutter_test/flutter_test.dart';

// HistoryWriter brings a browser's history to the entries the app should
// have. These tests give it a browser whose landings the test releases, so
// every order of the app's changes and the browser's landings can be run:
// the browser must end the same in each, the entries ahead included.
//
// Native behavior this holds to: the HTML History API, as Chrome runs it.
// pushState drops the entries ahead and replaceState keeps them; go()
// returns at once and lands later, on the entry counted from where the
// browser stood, or from where a step still on its way was going; a write
// before the landing goes to the entry being left. The canaries in
// test/web/flutter_canary_router_browser_writes_web_test.dart pin the last
// two on the real browser.

// A browser history that lands a step only when the test says so.
class _Browser implements HistoryBrowser {
  // Every entry the browser holds, as its url and state.
  final entries = <(String, Object?)>[('/', null)];

  // What was asked of the browser, in order.
  final asked = <String>[];

  // The entries the steps on their way are going to.
  final _steps = Queue<int>();

  late HistoryWriter writer;

  @override
  int index = 0;

  // Whether a step is lost, as when the browser has no such entry.
  bool losesSteps = false;

  bool get isStepping => _steps.isNotEmpty;

  @override
  String get url => entries.elementAtOrNull(index)?.$1 ?? '';

  @override
  Object? get state => entries.elementAtOrNull(index)?.$2;

  @override
  void write(UrlState entry, {required bool replaces}) {
    // A write goes to the entry the browser stands on. The writer must know
    // which that is: before a step of its own has landed it is still the
    // entry being left.
    expect(
      index,
      writer.index - (replaces ? 0 : 1),
      reason: 'written on an entry the writer did not know it stood on',
    );
    asked.add('${replaces ? 'replace' : 'push'} ${entry.url}');
    if (replaces) {
      entries.removeAt(index);
    } else {
      index++;
      entries.removeRange(index, entries.length);
    }
    entries.insert(index, (entry.url, entry.pathState));
  }

  @override
  Future<void> whenWritten() => .value();

  @override
  void go(int delta) {
    asked.add('go $delta');
    _didStartStep(delta);
  }

  // The user presses the back button; false when no entry is under the one
  // the browser stands on, or is going to.
  bool didPressBack() => _didStartStep(-1);

  bool _didStartStep(int delta) {
    final to = (_steps.lastOrNull ?? index) + delta;
    if (losesSteps || to < 0 || to >= entries.length) return false;
    _steps.add(to);
    return true;
  }

  // The browser lands the oldest step on its way and tells the writer.
  void land() {
    landUntold();
    writer.browserLanded();
  }

  // The browser lands the oldest step on its way; its event is still to
  // come.
  void landUntold() => index = _steps.removeFirst();

  // The urls of every entry, with the one the browser stands on marked.
  String get held => [
    for (final (number, (entryUrl, saved)) in entries.indexed)
      '${number == index ? '>' : ''}$entryUrl${saved == null ? '' : '#$saved'}',
  ].join(' ');
}

UrlState _entry(String url) {
  final [path, ...state] = url.split('#');
  return UrlState(Uri.parse(path), const [], pathState: state.firstOrNull);
}

List<UrlState> _entries(String urls) => [
  for (final url in urls.split(' ')) _entry(url),
];

// The browser with its writer, and an app that follows the browser when
// the user moves it: it then shows what the browser holds up to its entry.
class _Web {
  new({this.landingLimit = const Duration(seconds: 1)}) {
    writer = HistoryWriter(
      browser,
      landingLimit: landingLimit,
      onUserMove: () {
        userMoves++;
        shown = [
          for (var i = writer.first; i <= writer.index; i++)
            writer.entryAt(i) ??
                _entry(browser.entries.elementAtOrNull(i)?.$1 ?? ''),
        ];
        writer.bringTo(shown);
      },
    );
    browser.writer = writer;
  }

  final Duration landingLimit;
  final browser = _Browser();
  late final HistoryWriter writer;

  // What the app shows, as the entries it last asked for.
  List<UrlState> shown = const [];
  int userMoves = 0;

  void show(String urls) => writer.bringTo(shown = _entries(urls));

  // Lets the writer work until it waits for a landing or has nothing to do.
  Future<void> settle() => .delayed(.zero);

  // Lands every step until the writer has nothing left to do; a step the
  // browser lost ends after the limit.
  Future<void> finish() async {
    await settle();
    while (browser.isStepping) {
      browser.land();
      await settle();
    }
    if (!writer.isIdle) {
      await Future<void>.delayed(landingLimit * 2);
      await settle();
    }
    expect(browser.isStepping, isFalse);
    expect(writer.isIdle, isTrue);
  }
}

// When the user presses the back button in a run.
enum _Moment { onceLanded, whileWriterSteps, beforeNextList }

// The lists an app can go through from [start] in [depth] changes: a push, a
// pop, a replace, a pop to the first entry with a push, and a new list.
Iterable<List<String>> _sequences(String start, int depth) sync* {
  var next = 0;
  String fresh() => '/n${next++}';
  Iterable<List<String>> from(List<String> lists, int left) sync* {
    if (left == 0) {
      yield lists;
      return;
    }
    final last = (lists.lastOrNull ?? '').split(' ');
    final changes = [
      [...last, fresh()],
      if (last.length > 1) last.sublist(0, last.length - 1),
      [...last.sublist(0, last.length - 1), fresh()],
      if (last.length > 2) [...last.take(1), fresh()],
      [fresh()],
    ];
    for (final change in changes) {
      yield* from([...lists, change.join(' ')], left - 1);
    }
  }

  yield* from([start], depth);
}

// Runs [lists] through a writer. At each point where a step is on its way
// and the app has more to show, [landsFirst] says whether the step lands
// before the next list is shown; it is asked once for each such point.
Future<_Web> _run(List<String> lists, bool Function() landsFirst) async {
  final web = _Web()..show(lists.firstOrNull ?? '/');
  await web.finish();
  for (final list in lists.skip(1)) {
    web.show(list);
    await web.settle();
    while (web.browser.isStepping && landsFirst()) {
      web.browser.land();
      await web.settle();
    }
  }
  await web.finish();
  return web;
}

void main() {
  // Steps: show each list of a sequence; where a step is on its way when the
  // next list comes, run once with the landing first and once with the list
  // first, for every such point.
  test('The browser ends on the same entries, with the same entries ahead, '
      'in every order of the changes and the landings', () async {
    var orders = 0;
    for (final start in ['/', '/ /a /b']) {
      for (final lists in _sequences(start, 4)) {
        final apart = await _run(lists, () => true);
        expect(
          [
            for (final (url, _) in apart.browser.entries.take(
              apart.browser.index + 1,
            ))
              url,
          ],
          (lists.lastOrNull ?? '').split(' '),
          reason: 'the way back after $lists',
        );

        // Each run takes the choices in [choices], then lets every landing
        // wait; the points it met tell which runs are left.
        final open = Queue<List<bool>>()..add(const []);
        while (open.isNotEmpty) {
          final choices = open.removeFirst();
          var met = 0;
          final web = await _run(
            lists,
            () => choices.elementAtOrNull(met++) ?? false,
          );
          orders++;
          expect(
            web.browser.held,
            apart.browser.held,
            reason: 'after $lists with the landings $choices',
          );
          for (var point = choices.length; point < met; point++) {
            open.add([
              ...choices,
              for (var i = choices.length; i < point; i++) false,
              true,
            ]);
          }
        }
      }
    }
    // Enough orders to mean something.
    expect(orders, greaterThan(1000));
  });

  // Steps: show each list of a sequence, and have the user press the back
  // button once: after a list when everything has landed, while a step of
  // the writer's is on its way, or just before the next list is shown, so
  // that the writer writes while the user's step is on its way.
  test('After the user presses back in the middle, the app and the browser '
      'end on the same entry', () async {
    var runs = 0;
    for (final start in ['/', '/ /a /b']) {
      for (final lists in _sequences(start, 3)) {
        for (var after = 0; after < lists.length; after++) {
          for (final moment in _Moment.values) {
            // A step of the writer's that the browser counts from below
            // its first entry, after the user's, is lost.
            final web = _Web(landingLimit: const Duration(milliseconds: 2))
              ..show(lists.firstOrNull ?? '/');
            await web.finish();
            var didPress = false;
            for (final (place, list) in lists.indexed.skip(1)) {
              if (place == after + 1 && moment == .beforeNextList) {
                didPress = web.browser.didPressBack();
              }
              web.show(list);
              await web.settle();
              if (place != after) continue;
              if (moment == .whileWriterSteps) {
                didPress = web.browser.didPressBack();
              } else if (moment == .onceLanded) {
                await web.finish();
                didPress = web.browser.didPressBack();
                await web.finish();
              }
            }
            await web.finish();
            if (didPress) runs++;
            expect(
              [
                for (final (url, _) in web.browser.entries.take(
                  web.browser.index + 1,
                ))
                  url,
              ],
              [for (final entry in web.shown) entry.url],
              reason: 'after $lists with back ${moment.name} after list $after',
            );
          }
        }
      }
    }
    expect(runs, greaterThan(500));
  });

  // Steps: on A, B over Home, show Home and A, then Home alone, then Home
  // and C, with no landing between.
  test('Steps back that follow each other are one step, and what follows '
      'waits for its landing', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();
    web.browser.asked.clear();
    web
      ..show('/ /a')
      ..show('/')
      ..show('/ /c');
    await web.settle();
    expect(web.browser.asked, ['go -2']);
    await web.finish();
    expect(web.browser.asked, ['go -2', 'push /c']);
    expect(web.browser.held, '/ >/c');
  });

  // Steps: on A over Home, show a page with another url in A's place.
  test('A change of the entry the browser stands on is written over it, '
      'and keeps the entries ahead', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();
    web.show('/ /a');
    await web.finish();
    web.browser.asked.clear();
    web.show('/ /c');
    await web.finish();
    expect(web.browser.asked, ['replace /c']);
    expect(web.browser.held, '/ >/c /b');
  });

  // Steps: on A, B over Home, show Home and C: the entry under the one the
  // browser stands on changes.
  test('A change under the entry the browser stands on steps back under it '
      'and adds from there', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();
    web.browser.asked.clear();
    web.show('/ /c');
    await web.finish();
    expect(web.browser.asked, ['go -2', 'push /c']);
    expect(web.browser.held, '/ >/c');
  });

  // Steps: on A over Home, show C alone, as after replaceAll.
  test("The app's first entry is written over, since nothing is under it "
      'to step back to', () async {
    final web = _Web()..show('/ /a');
    await web.finish();
    web.browser.asked.clear();
    web.show('/c');
    await web.finish();
    expect(web.browser.asked, ['go -1', 'replace /c']);
    expect(web.browser.held, '>/c /a');
  });

  // Steps: start on '/', show '/', then show '/x' in a second run.
  test('The entry the app starts on is written only when the app shows '
      'another url than it holds', () async {
    final same = _Web()..show('/');
    await same.finish();
    expect(same.browser.asked, isEmpty);

    final other = _Web()..show('/x');
    await other.finish();
    expect(other.browser.asked, ['replace /x']);
  });

  // Steps: show the same url with a state of its own, as pushPathState.
  test('An entry with the same url and another state is an entry of its '
      'own', () async {
    final web = _Web()..show('/ /a');
    await web.finish();
    web.show('/ /a /a#s');
    await web.finish();
    expect(web.browser.held, '/ /a >/a#s');
    web.show('/ /a');
    await web.finish();
    expect(web.browser.held, '/ >/a /a#s');
  });

  // Steps: on A, B over Home the user presses back; then again while the
  // writer is stepping back for the app.
  test("A landing the writer did not ask for is the user's: the app "
      'follows, and what was still to do is dropped', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();
    web.browser
      ..go(-1)
      ..land();
    await web.finish();
    expect(web.userMoves, 1);
    expect(web.browser.held, '/ >/a /b');
    expect(web.shown.map((entry) => entry.url), ['/', '/a']);

    // The app asks for C over A while the user's next step back is on its
    // way: the user lands first, and the app follows to Home.
    web.browser.go(-1);
    web.show('/ /a /c');
    web.browser.land();
    await web.finish();
    expect(web.userMoves, 2);
    expect(web.browser.held, '>/ /a /b');
    expect(web.shown.map((entry) => entry.url), ['/']);
  });

  // Steps: on A over Home, ask for a step back, as router.back() does, right
  // after showing B.
  test('A step the app asks for waits behind what is still to do, and the '
      'app follows where it lands', () async {
    final web = _Web()..show('/ /a');
    await web.finish();
    web.browser.asked.clear();
    web.show('/ /a /b');
    web.writer.step(-1);
    await web.finish();
    expect(web.browser.asked, ['push /b', 'go -1']);
    expect(web.userMoves, 1);
    expect(web.browser.held, '/ >/a /b');
  });

  // Steps: on B over A over Home, show Home; the platform's report of the
  // landing comes before the browser's event, then the other way round.
  test("The platform's report of a step of the writer's own is the "
      "writer's, whether it comes before the browser's event or after "
      'it', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();

    web.show('/ /a');
    await web.settle();
    web.browser.landUntold();
    expect(web.writer.isOwnStep(_entry('/a')), isTrue);
    web.writer.browserLanded();
    await web.settle();
    expect(web.writer.isIdle, isTrue);

    web.show('/');
    await web.settle();
    web.browser.land();
    expect(web.writer.isOwnStep(_entry('/')), isTrue);
    // A second report of the same url is a link, not the landing.
    expect(web.writer.isOwnStep(_entry('/')), isFalse);
    await web.settle();
    expect(web.userMoves, 0);
    expect(web.browser.held, '>/ /a /b');
  });

  // Steps: the browser loses a step the writer asks for, as it does when it
  // has no such entry.
  test('A step that never lands ends after the limit, and the writer goes '
      'on', () async {
    final web = _Web(landingLimit: const Duration(milliseconds: 20))
      ..show('/ /a /b');
    await web.finish();
    web.browser.losesSteps = true;
    web.show('/ /a');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(web.writer.isIdle, isTrue);
    expect(web.browser.held, '/ /a >/b');

    web.browser.losesSteps = false;
    web.show('/ /a /b /c');
    await web.finish();
    expect(web.browser.held, '/ /a /b >/c');
  });

  // Steps: the app starts on the third entry, as after a reload; the user
  // presses back.
  test('After a reload the entries under the one the app starts on are the '
      "browser's: a step back to one is the user's", () async {
    final web = _Web();
    web.browser
      ..entries.insertAll(0, [('/x', null), ('/y', null)])
      ..index = 2;
    // The writer was made on the first entry; a new one starts where the
    // browser stands.
    final writer = web.browser.writer = HistoryWriter(
      web.browser,
      onUserMove: () => web.userMoves++,
    );
    expect(writer.first, 2);
    writer.bringTo(_entries('/ /a'));
    await web.settle();
    expect(web.browser.held, '/x /y / >/a');

    web.browser
      ..index = 1
      ..writer.browserLanded();
    expect(web.userMoves, 1);
    expect(writer.first, 1);
    expect(writer.entryAt(1), isNull);
  });

  // Steps: pause the writer, show two lists, resume.
  test(
    'A paused writer keeps what it is asked for until it is resumed',
    () async {
      final web = _Web();
      web.writer.pause();
      web
        ..show('/ /a')
        ..show('/ /a /b');
      await web.settle();
      expect(web.browser.asked, isEmpty);
      web.writer.resume();
      await web.finish();
      expect(web.browser.held, '/ /a >/b');
    },
  );
}
