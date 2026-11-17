import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Canary for Flutter bug https://github.com/flutter/flutter/issues/111137:
// a page taken out of a Navigator's pages right after its dialog pops
// vanishes at once and cuts the dialog's animation short. Flutter's own
// imperative Navigator.pop, called twice, animates both out; so do iOS's
// dismiss(animated:) followed by popViewController(animated:).
// Setup, without auto_route: the reporter's app, a Navigator with pages in
// MaterialApp.builder, so it is the root Navigator and showDialog pushes
// onto it. SecondScreen awaits showDialog; when the dialog returns true it
// removes its own page.
// Steps: open SecondScreen, open the dialog, tap 'Yes', and look at
// SecondScreen's route 100 ms later.
// Today, on Flutter 3.50.0 (and 3.47.9): SecondScreen's route is removed
// without its exit animation while the dialog is still animating out. The
// dialog's pop already decided its own exit, yet `DefaultTransitionDelegate`
// still completes, rather than pops, a leaving page with pageless routes
// above it: `resolve` in flutter lib/src/widgets/navigator.dart:1225.
// Flutter's thread keeps it open as a framework bug.
// auto_route gives its Navigator its own delegate,
// `_PoppedPagelessTransitionDelegate` in
// lib/src/router/widgets/auto_route_navigator.dart, which pops that page when
// every pageless route above it is already leaving. If this test fails after
// a Flutter upgrade, Flutter fixed the bug: drop that delegate, check that
// test/dialog_then_page_animates_test.dart still passes, and drop this
// canary.
void main() {
  // Opens SecondScreen and its dialog, taps 'Yes', and returns
  // SecondScreen's route 100 ms later. SecondScreen then leaves by taking its
  // page out of the pages, or with Navigator.pop when [isPagesRemoval] is
  // false.
  Future<ModalRoute<Object?>> answerYes(
    WidgetTester tester, {
    required bool isPagesRemoval,
  }) async {
    final pages = <Page<void>>[];
    late StateSetter setPages;
    // SecondScreen's button: asks in a dialog, and on 'Yes' leaves.
    Future<void> askThenLeave(BuildContext context) async {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (!(shouldExit ?? false) || !context.mounted) return;
      if (isPagesRemoval) {
        setPages(pages.removeLast);
      } else {
        Navigator.pop(context);
      }
    }

    Widget secondScreen(BuildContext context) => Scaffold(
      body: ElevatedButton(
        onPressed: () => unawaited(askThenLeave(context)),
        child: const Text('AlertDialog'),
      ),
    );
    final firstScreen = MaterialPage<void>(
      child: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => isPagesRemoval
                ? setPages(
                    () => pages.add(
                      MaterialPage<void>(child: Builder(builder: secondScreen)),
                    ),
                  )
                : Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: secondScreen)),
            child: const Text('SecondScreen'),
          ),
        ),
      ),
    );
    pages.add(firstScreen);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, _) => StatefulBuilder(
          builder: (context, setState) {
            setPages = setState;
            return Navigator(
              pages: List.of(pages),
              onDidRemovePage: pages.remove,
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('SecondScreen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AlertDialog'));
    await tester.pumpAndSettle();
    final secondRoute = ModalRoute.of(
      tester.element(find.text('AlertDialog')),
    )!;

    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Yes'), findsOneWidget, reason: 'the dialog animates');
    return secondRoute;
  }

  testWidgets(
    'a page removed from the pages right after its dialog pops leaves with '
    'no animation, until Flutter fixes flutter/flutter#111137',
    (tester) async {
      final secondRoute = await answerYes(tester, isPagesRemoval: true);

      expect(secondRoute.animation!.status, AnimationStatus.completed);
      expect(secondRoute.isActive, isFalse);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the control: Navigator.pop right after the dialog pops '
      'animates the page out', (tester) async {
    final secondRoute = await answerYes(tester, isPagesRemoval: false);

    expect(secondRoute.animation!.status, AnimationStatus.reverse);
    expect(secondRoute.animation!.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });
}
