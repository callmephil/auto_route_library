// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import 'browser_history.dart';

// Canaries for how Flutter's Router and its web engine write the browser
// history. The web history of auto_route is the browser's one writer and
// rests on each of them; none is a Flutter bug.
// Setup: a plain Flutter Router with PlatformRouteInformationProvider, no
// auto_route, on the browser's real history.
// If one fails after a Flutter upgrade, Flutter changed that behavior: read
// the comment of the failing test, then rework the part of the web history
// it names (lib/src/router/controller/navigation_history/) and this canary
// together.
class _Delegate extends RouterDelegate<Uri> with ChangeNotifier {
  Uri? _shown;

  // Whether currentConfiguration is null whatever is shown.
  bool isSilent = false;

  void show(Uri uri) {
    _shown = uri;
    notifyListeners();
  }

  @override
  Uri? get currentConfiguration => isSilent ? null : _shown;

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  Future<bool> popRoute() => SynchronousFuture(false);

  @override
  Future<void> setNewRoutePath(Uri configuration) => SynchronousFuture(null);
}

class _Parser extends RouteInformationParser<Uri> {
  const new();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture(routeInformation.uri);

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      .new(uri: configuration);
}

Future<(_Delegate, PlatformRouteInformationProvider)> _pumpRouter(
  WidgetTester tester,
) async {
  final delegate = _Delegate();
  addTearDown(delegate.dispose);
  final provider = PlatformRouteInformationProvider(
    initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
  );
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Router<Uri>(
        routerDelegate: delegate,
        routeInformationParser: const _Parser(),
        routeInformationProvider: provider,
      ),
    ),
  );
  await settleBrowser(tester);
  return (delegate, provider);
}

// Writes [paths] as new entries, the way the Router reports a navigation, and
// waits until the engine has put them in the browser.
Future<void> _write(
  PlatformRouteInformationProvider provider,
  List<String> paths,
) async {
  for (final path in paths) {
    provider.routerReportsNewRouteInformation(
      RouteInformation(uri: Uri.parse(path)),
      type: .navigate,
    );
  }
  await SystemNavigator.selectMultiEntryHistory();
}

// Steps the browser by [delta] entries and waits until it has landed.
Future<void> _go(int delta) async {
  final landed = window.onPopState.first;
  window.history.go(delta);
  await landed;
  await SystemNavigator.selectMultiEntryHistory();
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // The web history silences the Router by returning null from
  // AutoRouterDelegate.currentConfiguration on the web, the way Flutter
  // documents for a delegate that reports no route. If the Router wrote the
  // url anyway, the browser would have two writers again.
  // Steps: show '/x', which the Router writes; then make the configuration
  // null and notify again.
  testWidgets('a Router whose delegate has a null currentConfiguration '
      'writes nothing to the browser', (tester) async {
    final (delegate, _) = await _pumpRouter(tester);
    final first = browserSerialCount;
    delegate.show(Uri.parse('/x'));
    await settleBrowser(tester);
    expect((browserSerialCount - first, browserPath), (1, '/x'));

    delegate
      ..isSilent = true
      ..show(Uri.parse('/y'));
    await settleBrowser(tester);
    await tester.pump(const Duration(milliseconds: 50));
    await settleBrowser(tester);
    expect((browserSerialCount - first, browserPath), (1, '/x'));
  });

  // The web history writes its entries through the Router's route information
  // provider whenever the app navigates, not once a frame, and takes the
  // reply to SystemNavigator.selectMultiEntryHistory as the sign that they
  // are in the browser, since the engine handles navigation messages in
  // order.
  // Steps: report two navigations and a replace with no frame between, and
  // read the browser when selectMultiEntryHistory answers.
  testWidgets('entries reported to the provider are in the browser once '
      'selectMultiEntryHistory answers, with no frame', (tester) async {
    final (_, provider) = await _pumpRouter(tester);
    final first = browserSerialCount;
    await _write(provider, ['/a', '/b']);
    expect((browserSerialCount - first, browserPath), (2, '/b'));

    provider.routerReportsNewRouteInformation(
      RouteInformation(uri: Uri.parse('/c')),
      type: .neglect,
    );
    await SystemNavigator.selectMultiEntryHistory();
    expect((browserSerialCount - first, browserPath), (2, '/c'));
  });

  // The web history never writes while a step back of its own is on its way:
  // history.go returns at once and the browser lands in a later task, so a
  // write sent before the landing goes to the entry being left.
  // Steps: on the second of two entries, step back and report a replace in
  // the same turn; then go forward to the entry that was left.
  testWidgets('a replace reported before a step back has landed is written '
      'on the entry being left', (tester) async {
    final (_, provider) = await _pumpRouter(tester);
    final first = browserSerialCount;
    await _write(provider, ['/a', '/b']);

    final landed = window.onPopState.first;
    window.history.go(-1);
    expect((browserSerialCount - first, browserPath), (2, '/b'));
    provider.routerReportsNewRouteInformation(
      RouteInformation(uri: Uri.parse('/early')),
      type: .neglect,
    );
    await landed;
    await SystemNavigator.selectMultiEntryHistory();
    expect((browserSerialCount - first, browserPath), (1, '/a'));

    await _go(1);
    expect((browserSerialCount - first, browserPath), (2, '/early'));
  });

  // For the same reason the web history holds a new entry back until its
  // step back has landed: the browser still lands where the step pointed
  // when it was called, under the entry written meanwhile, so the app would
  // show the new page with the browser standing under its entry.
  // Steps: on the second of two entries, step back and report a navigation
  // in the same turn; then press forward twice.
  testWidgets('a navigation reported before a step back has landed does '
      'not cancel the step', (tester) async {
    final (_, provider) = await _pumpRouter(tester);
    final first = browserSerialCount;
    await _write(provider, ['/a']);

    final landed = window.onPopState.first;
    window.history.go(-1);
    provider.routerReportsNewRouteInformation(
      RouteInformation(uri: Uri.parse('/late')),
      type: .navigate,
    );
    await landed;
    await SystemNavigator.selectMultiEntryHistory();
    expect((browserSerialCount - first, browserPath), (0, '/'));

    await _go(1);
    expect((browserSerialCount - first, browserPath), (1, '/a'));
    await _go(1);
    expect((browserSerialCount - first, browserPath), (2, '/late'));
  });
}
