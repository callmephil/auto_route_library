import 'dart:collection';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_test_browser.dart';

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
    browser.writerIndex = () => writer.index;
  }

  final Duration landingLimit;
  final browser = TestHistoryBrowser();
  late final HistoryWriter writer;

  // What the app shows, as the entries it last asked for.
  List<UrlState> shown = const [];
  int userMoves = 0;

  void show(String urls) => writer.bringTo(shown = _entries(urls));

  // Lets the writer work until it waits for a landing or has nothing to do.
  // In microtasks, which is all the writer waits for besides a landing: a
  // timer for each step of a test that runs thousands is slow in a browser.
  Future<void> settle() async {
    for (var turn = 0; turn < 40; turn++) {
      await Future<void>.value();
    }
  }

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

  // Steps: start on '/' and show '/', twice; in a second run show '/x'.
  // Native behavior this holds to: Flutter's Router, which reports its
  // first route to the engine as a replace of the entry the app starts on.
  test('The entry the app starts on is written once, over what the browser '
      'holds there', () async {
    final same = _Web()..show('/');
    await same.finish();
    same.show('/');
    await same.finish();
    expect(same.browser.asked, ['replace /']);

    final other = _Web()..show('/x');
    await other.finish();
    expect(other.browser.asked, ['replace /x']);
  });

  // Steps: the browser goes from its first entry to a third one while the
  // writer is paused, as before a Router shows the app; then resume and
  // show '/c'.
  // Was: the writer took the entry the browser stood on when it was made
  // for the app's first, and stepped back under the entry the app started
  // on.
  test('A paused writer starts from the entry the browser stands on when '
      'it resumes, and is idle meanwhile', () async {
    final web = _Web()
      ..writer.pause()
      ..show('/c');
    await web.settle();
    expect(web.writer.isIdle, isTrue);
    expect(web.browser.asked, isEmpty);
    web.browser
      ..entries.addAll([('/a', null), ('/b', null)])
      ..index = 2;
    web.writer.resume();
    await web.finish();
    expect(web.writer.first, 2);
    expect(web.browser.asked, ['replace /c']);
    expect(web.browser.held, '/ /a >/c');
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

  // Steps: on A over Home, with no entry of the app ahead, as when the
  // entry ahead is another site's, which the Navigation API leaves out; a
  // step forward, as navigationHistory.forward() asks, then B.
  //
  // Native behavior this holds to: the HTML History API, where
  // history.forward() goes to the entry ahead whatever its site, and does
  // nothing with none ahead; and the Navigation API, whose canGoForward
  // counts only the entries of the page's own origin (the HTML standard,
  // "getting the navigation API entries" stops at another origin's entry).
  test('A step forward with no entry of the app ahead is still asked, as '
      'the browser may hold another site there, and nothing waits for '
      'it', () async {
    final web = _Web()..show('/ /a');
    await web.finish();
    web.browser.asked.clear();
    web.writer.step(1);
    web.show('/ /a /b');
    await web.settle();
    expect(
      (web.browser.asked.join(', '), web.writer.isIdle),
      ('go 1, push /b', true),
    );
    expect(web.browser.held, '/ /a >/b');
  });

  // Steps: on B over A over Home, show Home; the platform's report of the
  // landing comes before the browser's event, then the other way round.
  // While the second step is on its way, and once the writer is done, the
  // platform hands over a route with no landing behind it.
  test("The platform's report of a step of the writer's own is the "
      "writer's, whether it comes before the browser's event or after "
      'it', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();

    web.show('/ /a');
    await web.settle();
    web.browser.landUntold();
    expect(web.writer.hasNothingToFollow(_entry('/a')), isTrue);
    web.writer.browserLanded();
    await web.settle();
    expect(web.writer.isIdle, isTrue);

    web.show('/');
    await web.settle();
    // The step is on its way, and the Router parses again what its
    // provider holds, the url handed over last: nothing to follow. Then
    // the report of the landing.
    final whileStepping = web.writer.hasNothingToFollow(_entry('/a'));
    web.browser.land();
    expect(
      (whileStepping, web.writer.hasNothingToFollow(_entry('/'))),
      (true, true),
    );
    await web.settle();
    // With nothing left to do and no landing, a route is a link.
    expect(web.writer.hasNothingToFollow(_entry('/a')), isFalse);

    // And so is another url than the provider held, also while a step is
    // on its way.
    web.show('/ /c');
    await web.finish();
    web.show('/');
    await web.settle();
    expect(web.writer.hasNothingToFollow(_entry('/x')), isFalse);
    await web.finish();
    expect(web.userMoves, 0);
    expect(web.browser.held, '>/ /c');
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
    final writer = HistoryWriter(
      web.browser,
      onUserMove: () => web.userMoves++,
    );
    web.browser.writerIndex = () => writer.index;
    writer.bringTo(_entries('/ /a'));
    await web.settle();
    expect(web.browser.held, '/x /y / >/a');

    web.browser.index = 1;
    writer.browserLanded();
    expect(web.userMoves, 1);
    expect(writer.index, 1);
    expect(writer.entryAt(1), isNull);
    // The app's first entry moves there once the app follows.
    expect(writer.first, 2);
    writer
      ..first = 1
      ..bringTo(_entries('/y /b'));
    await web.settle();
    expect(web.browser.held, '/x /y >/b');
  });

  // Steps: the browser opened the app at a url the app keeps out of the
  // address bar; show that page, then B over it, then the page alone again.
  // Native behavior this holds to: the HTML History API; the browser made
  // the entry for the url it opened, and the back button goes to it.
  test("The app's first entry, which the browser made for a url kept out of "
      'the address bar, stays the entry of that page', () async {
    final browser = TestHistoryBrowser()..entries[0] = ('/kept', null);
    final writer = HistoryWriter(browser);
    browser.writerIndex = () => writer.index;
    Future<void> settle() async {
      for (var turn = 0; turn < 40; turn++) {
        await Future<void>.value();
      }
      while (browser.isStepping) {
        browser.land();
        for (var turn = 0; turn < 40; turn++) {
          await Future<void>.value();
        }
      }
    }

    writer.bringTo(_entries('/kept'));
    await settle();
    writer.bringTo(_entries('/kept /b'));
    await settle();
    expect(browser.held, '/kept >/b');
    writer.bringTo(_entries('/kept'));
    await settle();
    expect(browser.held, '>/kept /b');
    writer.dispose();
  });

  // Steps: show a page whose url the app keeps out of the address bar over
  // A, then B over it.
  test(
    'An entry the app keeps out of the address bar is not written',
    () async {
      final web = _Web()..show('/ /a /kept');
      await web.finish();
      expect(web.browser.held, '/ >/a');
      web.show('/ /a /kept /b');
      await web.finish();
      expect(web.browser.held, '/ /a >/b');
    },
  );

  // Steps: with a browser that takes no write, show A, B over Home, then
  // Home alone, then A, B, C.
  // Native behavior this holds to: the HTML History API, where history.go
  // moves through entries whoever wrote them. An app that writes none must
  // not move the tab through the entries of other pages.
  test('A browser that takes no write is never stepped', () async {
    final web = _Web();
    web.browser.losesWrites = true;
    for (final urls in ['/ /a /b', '/', '/ /a /b /c', '/ /a']) {
      web.show(urls);
      await web.finish();
    }
    expect(web.browser.asked.where((ask) => ask.startsWith('go')), isEmpty);
    expect(web.browser.held, '>/');
    expect(web.userMoves, 0);
  });

  // Steps: show A, B over Home; another writer then writes the browser, as
  // the history of a router the app swapped in; restart, show '/login' and
  // resume.
  test('A writer that is restarted starts from the entry the browser '
      'stands on, and writes it first', () async {
    final web = _Web()..show('/ /a /b');
    await web.finish();
    web.browser
      ..entries.add(('/other', null))
      ..index = 3;
    web.writer.restart();
    web.show('/login');
    await web.settle();
    expect(web.writer.isIdle, isTrue);
    web.browser.asked.clear();
    web.writer.resume();
    await web.finish();
    expect(web.browser.asked, ['replace /login']);
    expect(web.browser.held, '/ /a /b >/login');
    expect(web.userMoves, 0);
  });

  // Steps: with a browser that keeps no entries, as in a widget test in
  // Chrome, show Home, push A and B, pop, show the same again, replace A
  // with C as the app reports a replace, then push D and E together, and
  // ask for a step back.
  // Native behavior this holds to: Flutter's Router, which reports the url
  // of each change to the platform: over the last one for its first url and
  // for a change the app reports as a replace, as a new one otherwise, a pop
  // included, and nothing for the url it reported last.
  test('A browser that keeps no entries is told the url of the page on top '
      'as the Router tells it, and is never stepped', () async {
    final web = _Web();
    web.browser
      ..keepsEntries = false
      ..losesWrites = true;
    for (final urls in ['/', '/ /a', '/ /a /b', '/ /a', '/ /a']) {
      web.show(urls);
      await web.finish();
    }
    web.writer.bringTo(_entries('/ /c'), isReplace: true);
    await web.finish();
    web.show('/ /c /d /e');
    await web.finish();
    web.writer.step(-1);
    await web.finish();
    expect(web.browser.asked, [
      'replace /',
      'push /a',
      'push /b',
      'push /a',
      'replace /c',
      'push /e',
    ]);
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
