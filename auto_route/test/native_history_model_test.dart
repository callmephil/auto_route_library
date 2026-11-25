import 'package:flutter_test/flutter_test.dart';

import 'native_history_model.dart';

// The reference model of native browser session history that the random
// sequence test compares the web history with.
//
// Native behavior this holds to: the HTML Living Standard, session history
// (§7.2): pushState removes the entries ahead, replaceState changes the
// current entry, and back, forward and go(n) keep every entry. Flutter's
// Navigator: pop and popUntil close the pages on top.
void main() {
  test('A push adds an entry and removes the entries ahead', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..push('/b')
      ..go(-2)
      ..push('/c');
    expect(model.held, '/ >/c');
    expect(model.stack, ['/', '/c']);
  });

  test('A replace changes the current entry only', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..push('/b')
      ..go(-1)
      ..replace('/c');
    expect(model.held, '/ >/c /b');
    expect(model.stack, ['/', '/c']);
  });

  test('Back, forward and go(n) move the index and keep every entry', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..push('/b')
      ..push('/c');
    expect(model.canGo(1), isFalse);
    expect(model.canGo(-4), isFalse);
    model.go(-3);
    expect(model.held, '>/ /a /b /c');
    model.go(1);
    expect(model.shown, '/a');
    model.go(2);
    expect(model.held, '/ /a /b >/c');
    expect(model.stack, ['/', '/a', '/b', '/c']);
  });

  test('A pop goes back one entry and keeps the popped entry ahead', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..push('/b');
    expect(model.canPop, isTrue);
    model.pop();
    expect(model.held, '/ >/a /b');
    expect(model.stack, ['/', '/a']);
  });

  test('popUntil goes back over every page it closes at once', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..push('/b')
      ..push('/c')
      ..popTo(1);
    expect(model.held, '>/ /a /b /c');
    expect(model.canPop, isFalse);
  });

  test('A pop from a tab the user changed to goes back over the tab '
      'changes', () {
    final model = NativeHistoryModel()
      ..push('/tabs/first')
      ..changeTop('/tabs/second');
    expect(model.held, '/ /tabs/first >/tabs/second');
    model.pop();
    expect(model.held, '>/ /tabs/first /tabs/second');
  });

  test('A replace of a page drops the entries of its tab changes', () {
    final model = NativeHistoryModel()
      ..push('/tabs/first')
      ..changeTop('/tabs/second')
      ..replace('/b');
    expect(model.held, '/ >/b');
    expect(model.stack, ['/', '/b']);
  });

  test('A pop after a replace goes to the entry of the page under', () {
    final model = NativeHistoryModel()
      ..push('/a')
      ..replace('/b')
      ..pop();
    expect(model.held, '>/ /b');
  });
}
