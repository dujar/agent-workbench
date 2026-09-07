#!/usr/bin/env bash
# Deterministic invariant check for .agent-workbench/.
# The agents write prose that other agents parse; every drift is otherwise
# silent. This catches the mechanical half without asking a model anything.
#
# Usage: scripts/check-workbench.sh [workbench-dir]   (default .agent-workbench)
# Exit:  0 clean, 1 problems found.

set -uo pipefail
WB="${1:-.agent-workbench}"
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; FAIL=1; }

[ -d "$WB" ] || { say "no $WB — nothing to check"; exit 0; }

# ---- product -------------------------------------------------------------
if [ -d "$WB/product" ]; then
  say "product/"
  for f in spec.md state.md; do
    [ -f "$WB/product/$f" ] || bad "missing $f"
  done
  if [ -f "$WB/product/state.md" ]; then
    grep -qE '^approved:' "$WB/product/state.md" \
      || bad "state.md has no 'approved:' line — plan-agent's gate cannot be evaluated"
    # loop ceilings are self-counted by the agent; check them from outside
    for a in market-agent judge-agent; do
      n=$(grep -oE "^$a: *([0-9]+) run" "$WB/product/state.md" | grep -oE '[0-9]+' | head -1)
      [ -n "${n:-}" ] && [ "$n" -gt 2 ] && bad "$a ran $n times — ceiling is 2, the loop is not closing"
    done
  fi
  # a screen nobody reaches, or a journey pointing at a screen that is not there
  if [ -d "$WB/product/screens" ] && [ -f "$WB/product/journeys.md" ]; then
    for s in "$WB/product/screens"/*.html; do
      [ -e "$s" ] || continue
      grep -qF "$(basename "$s")" "$WB/product/journeys.md" \
        || bad "screens/$(basename "$s") is reached by no journey"
    done
  fi
fi

# ---- tracker -------------------------------------------------------------
TRACKER="$WB/step-feature-state.md"
shopt -s nullglob
STEPDIRS=("$WB"/step-*/)
shopt -u nullglob

# ---- run log: invocation counts from outside the agents ------------------
LOG="$WB/run-log.md"
if [ -f "$LOG" ]; then
  say "run-log/"
  while read -r count agent; do
    case "$agent" in
      market-agent|judge-agent|plan-judge-agent|audit-agent) ceil=2 ;;
      review-agent) ceil=3 ;;
      *) continue ;;
    esac
    [ "$count" -gt "$ceil" ] \
      && bad "$agent was invoked $count times, ceiling is $ceil — the loop is not closing"
  done < <(awk -F'|' 'NR>2 && NF>3 {gsub(/ /,"",$3); if ($3!="") print $3}' "$LOG" \
           | sort | uniq -c | awk '{print $1, $2}')
fi

if [ ${#STEPDIRS[@]} -eq 0 ]; then
  say "no step directories yet"
  exit $FAIL
fi

say "steps/"
[ -f "$TRACKER" ] || bad "step directories exist but $TRACKER does not"

for d in "${STEPDIRS[@]}"; do
  [ -f "$d/plan.md" ] || bad "${d}plan.md is missing"
  # every Resources path must resolve, relative to the step dir
  if [ -f "$d/plan.md" ]; then
    while read -r rel; do
      [ -e "$d/$rel" ] || bad "${d}plan.md -> $rel does not resolve"
    done < <(sed -n '/^## Resources/,/^## /p' "$d/plan.md" \
             | grep -oE '\.\./[A-Za-z0-9_./-]+' | sort -u)
  fi
done

# duplicate step numbers in directory names
dupes=$(printf '%s\n' "${STEPDIRS[@]}" | sed -E 's#.*/step-([0-9]+)-.*#\1#' | sort | uniq -d)
[ -n "$dupes" ] && bad "duplicate step numbers: $(echo "$dupes" | tr '\n' ' ')"

# ---- tracker rows --------------------------------------------------------
if [ -f "$TRACKER" ]; then
  n=$(grep -oE '^plan-judge: *([0-9]+) run' "$TRACKER" | grep -oE '[0-9]+' | head -1)
  [ -n "${n:-}" ] && [ "$n" -gt 2 ] && bad "plan-judge ran $n times — ceiling is 2"

  rows=$(grep -E '^\| *[0-9]+ *\|' "$TRACKER" || true)
  nums=$(printf '%s\n' "$rows" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -E '^[0-9]+$' || true)

  while IFS='|' read -r _ num _ feat dir status deps _; do
    num=$(echo "$num" | tr -d ' '); [ -n "$num" ] || continue
    dir=$(echo "$dir" | tr -d ' '); status=$(echo "$status" | tr -d ' ')
    deps=$(echo "$deps" | tr -d ' ')

    [ -d "$WB/$dir" ] || bad "row $num names $dir, which does not exist"

    case "$status" in
      planned|done|blocked) ;;
      *) bad "row $num has status '$status' — only planned, done, blocked are ever written" ;;
    esac

    [ "$status" = done ] && [ ! -f "$WB/$dir/findings.md" ] \
      && bad "step $num is done but has no findings.md — reconcile-agent cannot see what it taught"

    # dependencies must exist, point backwards, and not be self-referential
    case "$deps" in ""|"—"|"-") ;; *)
      while read -r dep; do
        [ -n "$dep" ] || continue
        printf '%s\n' "$nums" | grep -qx "$dep" || bad "step $num depends on $dep, which is not a step"
        [ "$dep" = "$num" ] && bad "step $num depends on itself"
        [ "$dep" -gt "$num" ] 2>/dev/null && bad "step $num depends on $dep, which is built later"
        # a done step whose dependency is not done means something merged out of order
        if [ "$status" = done ]; then
          dstat=$(printf '%s\n' "$rows" | awk -F'|' -v d="$dep" '{gsub(/ /,"",$2); if($2==d){gsub(/ /,"",$6); print $6}}')
          [ -n "$dstat" ] && [ "$dstat" != done ] \
            && bad "step $num is done but its dependency $dep is $dstat"
        fi
      done < <(echo "$deps" | tr ',' '\n') ;;
    esac
  done < <(printf '%s\n' "$rows")
fi

[ $FAIL -eq 0 ] && say "clean" || say "problems found"
exit $FAIL
