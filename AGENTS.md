# AGENTS.md

Guidance for any agent editing this repository. The README documents the
plugin for its users; this file is for whoever changes it.

## What this repo is

A Claude Code plugin whose entire runtime is prose:

- `agents/*.md` — the subagent definitions. The frontmatter registers them;
  the body is the behavior. There is no other code.
- `bin/check-workbench`, `bin/wb-log` — the only executable logic: a
  deterministic invariant checker and a run-log appender.
- `skills/workbench/` — the `/workbench` dispatcher skill for flattened
  orchestration (platforms that strip spawn tools from subagents).
- `.claude-plugin/plugin.json` — name, **version**, description.
- `README.md` — the protocol's spec. The definitions implement it.

## The cache trap — read before editing anything in `agents/`

An installed session does **not** load these files. Install copies the plugin
into a version-keyed cache and the session loads that snapshot. Editing
`agents/*.md` changes nothing anywhere until you bump `plugin.json`'s
version, update the plugin, and restart. Skip the bump and the update is a
no-op that reports success.

So: **bump the version in the same commit as any change to `agents/`,
`bin/`, or `skills/`.** To see what a session is actually running, diff the
cache against the repo:

```
diff -rq ~/.claude/plugins/cache/agent-workbench/agent-workbench/*/agents agents
```

`marketplace.json` carries no version — only `plugin.json` matters.

## The parse contracts

Files under `.agent-workbench/` are written by one agent and parsed by
another, or by `check-workbench`. These formats are API. Change them only
with their readers, never unilaterally:

- **`VERDICT:` lines.** Every agent another agent acts on returns a line
  starting `VERDICT:`; callers grep for it ("Find the verdict, do not read
  for it"). Each definition's Report section owns one grammar. A grammar
  change ripples to every caller's find-the-verdict section, to the caller's
  handling of a missing verdict, and to the examples in the README.
- **`reconciled:`** — empty means pending, a date means reconciled. The
  *value* is the signal; testing for the line's presence deadlocks the
  pipeline. Parsed by `implement-agent`, `reconcile-agent`, and
  `check-workbench` (which strips `#` comments before judging emptiness).
- **`approved:`** — `pending` is not an approval; only a date passes
  `check-workbench`. `plan-agent` refuses without one.
- **`blocks:`** — every queued question in `state.md`'s *Open* section carries
  `blocks <Q-numbers>` or `blocks none`. `product-agent` writes it, the
  orchestrator batches on it: a run of `none` goes through one picker call,
  anything else is asked alone. A missing field means "ask alone", so dropping
  it is safe but silently restores the serial question queue.
- **`knows:` and `knowledge/*.md`** — `knows:` is a Resources line listing the
  knowledge files a step's code would contradict without; it resolves like
  every other Resources path, so `check-workbench` already validates it.
  Each file carries a `checked:` **date** and at least one source URL, both
  checked. The load-bearing part is not the format but the rule wired into
  `implement-agent`, `verify-agent` and `review-agent`: a knowledge file
  outranks the agent's own memory. That is what makes `knowledge-agent`'s
  `NO SOURCES` path non-negotiable — an unverified claim in here is enforced
  by review rather than caught by it.
- **Tracker statuses** — `planned`, `done`, `blocked`, nothing else, because
  nothing else is ever written. The status column belongs to the
  orchestrator; builders never commit `step-feature-state.md`.
- **Run-log loop identities** — `check-workbench` counts invocations grouped
  by `(agent, loop)` with `awk -F'|'`. The identities are documented in the
  README's run-log section and are the ceiling's unit. `wb-log` replaces `|`
  with `/` on purpose: an escaped pipe shifts every column after it and
  splits one loop's count in two. Do not "fix" that escaping back.
- **Ceilings** — market/judge/audit/plan-judge: 2, review: 3, per *loop*.
  Enforced twice: self-counted by the agents, and counted from outside by
  `check-workbench` (run-log rows + the counters in `state.md` and the
  tracker header). The tracker's `plan-judge:` counter is the *planning*
  loop only; reconciliation runs log under `reconcile-<date>`.

## Editing a definition

- Frontmatter models are aliases (`opus`, `sonnet`, `haiku`, `inherit`),
  never raw ids — the tiering only works where aliases map to distinct
  models. Keep the tiering rationale in the README's cost section true if
  you move a model.
- Every definition carries the same skeleton: Briefing contract, the work,
  Cost, Report. The Cost section is shared boilerplate with a measured
  statistic — update the measurement if you change what a run costs, not
  the prose around it.
- Loops must keep all three paths intact: resume-by-send with an
  `agentId`, fresh-spawn fallback when the send fails, and the "If you have
  no spawn tool" flattened section. Removing any one breaks a platform.
- Length budgets ("six lines per hole", one-page plans) are load-bearing —
  they exist because output replay is the second cost driver. Do not soften
  them into suggestions.
- Reports are receipts: verdict + `wrote:` paths, nothing else. The files
  are the output. If you add prose to a Report section, you are adding
  tokens to every run.

## Editing the scripts

POSIX-ish bash, no dependencies, run standalone from any directory. Keep it
that way.

- `check-workbench` exit contract: 0 clean, 1 problems. Its failure list is
  documented in the README — a new check must be added to that list in the
  same commit. The `plan shape:` report is deliberately outside that contract:
  a serial plan is a smell, not a broken invariant, and failing on it would
  block a build that is merely slow.
- The run-log parser splits on `|`. Column alignment is the contract.
- Test changes against a scratch workbench dir (each fixture is a directory
  you pass as `$1` or via `WB=`), expected vs actual per case. The e2e
  battery that found the last round of bugs ran ~27 such cases; rebuild
  fixtures from the failure list rather than trusting a single clean
  workbench to prove anything.

## Testing definition changes

Definitions are prose and need a driven scenario: a sandbox git repo, a
seeded `.agent-workbench/`, a scripted user, and one agent role-playing the
definition literally while logging every invocation through `wb-log` and
staging through `check-workbench`. The bar for a pass: the scenario
completes, every checkpoint holds, and `check-workbench` exits 0 at every
stage it should. Green is a real answer — a checker that always finds
something is a bug, not thoroughness.

When a change touches a contract, grep the definitions for every reader of
it before calling the change done. The definitions quote each other's
verdict strings and parse each other's files; the drift is otherwise
silent.
