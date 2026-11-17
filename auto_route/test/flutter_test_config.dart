import 'dart:async';

import 'package:flutter/foundation.dart'
    show ErrorToConsoleDumper, debugPrintSynchronously, kIsWeb;
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Runs every headless test with Flutter's leak tracking, so a disposable
/// object that is created and never disposed fails the test file that made
/// it. Set `LeakTesting.settings =
/// LeakTesting.settings.withCreationStackTrace()` to see where a leaked object
/// was created.
///
/// On the web, Flutter dumps a failed expectation (its "Expected / Actual"
/// lines) to the browser console, which the test runner does not show; every
/// test file there also prints each dump, so it appears in the run's output.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (kIsWeb) {
    ErrorToConsoleDumper.clearWebDumpListeners();
    ErrorToConsoleDumper.addWebDumpListener(debugPrintSynchronously);
  }
  LeakTesting.enable();
  await testMain();
}
