#!/usr/bin/env bash
# Tests check_test_fails_before_fix.sh on small sample repositories, with a
# stand-in `flutter` on the PATH that passes, fails or fails to compile as
# the sample's library says, so no real test runs. Each verdict must come
# with its exit code: 0 only for "fails before, passes after" and for a
# compile failure the fix explains, 1 for every other verdict.
#
# Usage: test_check_test_fails_before_fix.sh

script="$(cd "$(dirname "$0")" && pwd)/check_test_fails_before_fix.sh"
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
failures=0

# The stand-in flutter: `pub get` passes; `test` reads
# auto_route/lib/outcome.txt in the folder above the current one and passes,
# fails or prints a compile error naming the method `answer`.
mkdir -p "$work/bin"
cat >"$work/bin/flutter" <<'SH'
#!/usr/bin/env bash
[ "$1" = pub ] && exit 0
case "$(cat ../auto_route/lib/outcome.txt 2>/dev/null)" in
  pass) echo "00:00 +1: All tests passed!"; exit 0 ;;
  compile)
    echo "test/sample_test.dart:3:3: Error: Method not found: 'answer'."
    echo "Compilation failed"
    exit 1
    ;;
  *) echo "00:00 +0 -1: sample [E]"; exit 1 ;;
esac
SH
chmod +x "$work/bin/flutter"
export PATH="$work/bin:$PATH"

# Makes a repository whose first commit's library gives [before] and whose
# second commit, which adds a test, gives [after]. With [addsAnswer], the
# second commit's library declares `answer`.
sample() {
  local name=$1 before=$2 after=$3 adds_answer=${4:-}
  local dir=$work/$name
  mkdir -p "$dir/auto_route/lib" "$dir/auto_route/test"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Sample
  echo "$before" >"$dir/auto_route/lib/outcome.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm base
  echo "$after" >"$dir/auto_route/lib/outcome.txt"
  [ -n "$adds_answer" ] && echo 'int answer() => 42;' >"$dir/auto_route/lib/answer.dart"
  if [ "$name" != no_test ]; then
    echo 'void main() {}' >"$dir/auto_route/test/sample_test.dart"
  fi
  git -C "$dir" add -A
  git -C "$dir" commit -qm fix
}

check() {
  local name=$1 want=$2 verdict=$3
  local output status
  output=$(cd "$work/$name" && CHECK_TEST_TIMEOUT=60 "$script" HEAD 2>&1)
  status=$?
  if [ "$status" -ne "$want" ]; then
    echo "FAIL $name: exit $status, wanted $want"
    failures=$((failures + 1))
  elif ! grep -qF -- "VERDICT: $verdict" <<<"$output"; then
    echo "FAIL $name: no verdict '$verdict' in:"
    echo "$output" | tail -3
    failures=$((failures + 1))
  else
    echo "PASS $name"
  fi
}

sample fixed fail pass
sample fails_after fail fail
sample breaks pass fail
sample passes_before pass pass
sample no_test fail pass
sample compile_explained compile pass yes
sample compile_unexplained compile pass

check fixed 0 'fails before, passes after'
check fails_after 1 'fails after'
check breaks 1 'fails after'
check passes_before 1 'passes before: the test proves nothing'
check no_test 1 'no headless test'
check compile_explained 0 'fails to compile before, the fix adds answer'
check compile_unexplained 1 'fails to compile before, the fix does not add'

[ "$failures" -eq 0 ] || exit 1
