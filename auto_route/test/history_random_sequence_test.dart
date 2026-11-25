import 'package:flutter_test/flutter_test.dart';

import 'history_random_steps.dart';

// Random steps on the web history, compared step by step with
// native_history_model.dart. Run more seeds with
// --dart-define=HISTORY_SEEDS=2000 and --dart-define=HISTORY_FIRST_SEED=0.
const _seeds = int.fromEnvironment('HISTORY_SEEDS', defaultValue: 200);
const _firstSeed = int.fromEnvironment('HISTORY_FIRST_SEED');

void main() {
  test('The same seed always gives the same steps', () {
    for (var seed = 0; seed < 50; seed++) {
      final steps = historySteps(seed);
      expect(historySteps(seed).join(), steps.join());
      expect(isValidHistory(steps), isTrue);
      expect(steps.length, inInclusiveRange(5, 30));
    }
  });

  for (var seed = _firstSeed; seed < _firstSeed + _seeds; seed++) {
    testWidgets('Seed $seed', (tester) async {
      await expectNativeHistory(tester, historySteps(seed), seed: seed);
    });
  }
}
