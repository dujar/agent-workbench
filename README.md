# agent-workbench

Ten subagents for [Claude Code](https://claude.com/claude-code) that carry a
product from a vague idea to merged code — with a judge at every handoff.

Every agent starts with no memory of your conversation. Everything they know
comes from `.agent-workbench/`, which is the whole point: the work survives
compaction, a closed laptop, and a colleague picking it up on Monday.

## Install

```
/plugin marketplace add dujar/agent-workbench
/plugin install agent-workbench
```

Or from a local clone — which is what you want while editing the agents, since
a directory source picks up your changes on the next session instead of needing
a push and a `marketplace update`:

```
claude plugin marketplace add /path/to/this/repo
claude plugin install agent-workbench@agent-workbench --yes
```

Either way, **restart the session**: agent definitions load at startup.
`claude --continue` resumes the conversation with them available.

`claude plugin details agent-workbench` shows the component inventory and what
it costs — roughly 1.2k tokens always-on for the ten descriptions, and 1.3k–5.3k
per agent invocation. `claude plugin disable agent-workbench` turns it off for
projects that do not need it.

## The flow

```
  product-agent ──> market-agent ──> judge-agent ──> audit-agent ×3
       │  (asks you one question at a time, with options)
       ▼
   ★ your approval  ──────────────────────────────────────────
       │
       ▼
   plan-agent ──> plan-judge-agent
       │  (phases of steps, one directory per feature)
       ▼
   implement-agent ──> verify-agent ──> review-agent ──> merge
       │  (one per step, in parallel worktrees)
       ▼
   reconcile-agent   (folds each step's findings back into the plans that follow)
```

### 1. Specify — `product-agent`

Grills you until the idea is buildable, in six phases, in this order:

| Phase | What |
|---|---|
| 1 | The problem: who hurts, what they do today instead, why now |
| 2 | `market-agent` — who already solves this, and what people complain about |
| 3 | `judge-agent` — adversarial holes in the idea |
| 4 | Stack |
| 5 | User journeys and HTML mockups |
| 6 | `audit-agent` ×3 in parallel — spec, journeys, screens |

It asks **one question at a time, with options**, recommended answer first, so
you approve rather than compose. Phases 2 and 3 are loops, capped at two passes
each — a spec that dies in research never ships.

It returns `READY` and stops. Nothing gets planned until you say yes.

### 2. Approve

Approval is a line on disk, not a sentence in chat:

```
# .agent-workbench/product/state.md
approved: 2026-09-08
```

`plan-agent` reads it and refuses to run without it. An approval nobody wrote
down is an approval that gets re-litigated after the plan exists.

### 3. Plan — `plan-agent`

Splits the spec into **phases** of **steps**, one directory per feature:

```
.agent-workbench/
  step-feature-state.md        the tracker
  step-1-repo-setup/plan.md
  step-3-auth/plan.md
```

| Phase | Steps |
|---|---|
| 1 — foundation | repo scaffold, test harness, CI, a deploy that ships hello-world on day one, theme and components as real code, the data layer |
| 2 — the product | one step per user goal, each carrying its own unit and integration tests |
| 3 — launch | e2e per journey, observability, production deploy |
| 4+ | only what `spec.md` itself defers to v2 |

Then `plan-judge-agent` checks the set as a set: does every spec goal have a
step, do the dependencies form a real order, does anything fall between two
steps, is the product actually finished when the last one lands.

### 4. Build — `implement-agent`

One agent per step, on its own branch. Before building it runs `verify-agent`
against the current code, because the codebase has moved since the plan was
written. Then it builds, loops with `review-agent` until approved, rebases,
reruns the tests, and merges.

A step whose dependencies are not all `done` is never spawned — the builder
refuses anyway, but the caller should not offer. Steps with **no dependency
between them** run at the same time:

```
Agent(subagent_type: "implement-agent", isolation: "worktree",
      prompt: "Build .agent-workbench/step-3-auth/")
Agent(subagent_type: "implement-agent", isolation: "worktree",
      prompt: "Build .agent-workbench/step-4-project-list/")
```

### 5. Reconcile — `reconcile-agent`

Every step writes a `findings.md`: what was built, **where the plan was wrong**,
what the next step inherits, what it left broken on purpose.

A findings file counts as reconciled only when its `reconciled:` header carries
a **date**. The line is written empty as a placeholder, so empty means pending —
testing for the line's presence instead of its value deadlocks the pipeline:
`reconcile-agent` skips every file and `implement-agent` blocks forever waiting
for it.

`reconcile-agent` reads the unreconciled ones and works out what they change for
the steps not yet built — a stale path, a helper others should now reuse, an
assumption that no longer holds — updates those plans, has `plan-judge-agent`
check the result, and commits.

Run it **from your main session, alone**, before spawning the next round of
builders.

## Who orchestrates what

You (or the main agent) drive the outer loop. The subagents cannot talk to you
and cannot see each other.

1. Any `findings.md` without a `reconciled:` line → run `reconcile-agent` once,
   with no builders running.
2. Spawn one `implement-agent` per ready step, in parallel, `isolation: "worktree"`.
3. A builder returning `READY TO MERGE` has a rebased, reviewed branch. **Merge
   those one at a time** — git refuses to update a branch checked out in another
   worktree, and two merges at once is how a green build disappears.
4. Set that row's status in `step-feature-state.md` to `done`, or `blocked`.
   Loop back to 1.

`plan-agent` prints exactly this list, with your step numbers filled in.

## The agents

| Agent | Model | Does | Writes |
|---|---|---|---|
| `product-agent` | opus / high | Grills the idea into a spec, in six phases | `product/spec.md`, `journeys.md`, `state.md`, `screens/*.html` |
| `market-agent` | sonnet / high | Web research: competitors, metrics, complaints | `product/market.md` |
| `judge-agent` | opus / high | Adversarial holes in the idea | `product/judgment.md` |
| `audit-agent` | sonnet / medium | One scope of thoroughness — `spec`, `journeys`, or `screens` | `product/audit-<scope>.md` |
| `plan-agent` | **opus / max** | Phases and steps, one plan per feature | `step-*/plan.md`, the tracker |
| `plan-judge-agent` | opus / high | Does the plan set reach a finished product, and can its parallel steps actually run in parallel? | `plan-judgment.md` |
| `verify-agent` | opus / high | Does one plan survive contact with the code? | `step-*/verify.md` |
| `implement-agent` | opus / high | Builds one step on a branch | code, `step-*/findings.md` |
| `review-agent` | opus / high | Reviews one branch against its plan | `step-*/review.md` |
| `reconcile-agent` | opus / high | Folds findings into the plans that follow | edits `step-*/plan.md`, `reconciliation.md` |

Plus `scripts/check-workbench.sh` — no model, just invariants. See below.

## Conventions the agents share

**Mockups are HTML you can open.** Every screen links `../theme.css` and never
hardcodes a color — retheming is one file, not twelve. Components live in
`components.html`; a screen copies that markup rather than inventing a second
button. Real content, never lorem ipsum, because lorem hides exactly the layout
problems a mockup exists to find.

**Default stack**, proposed and confirmable, never mandated: Rust for backend,
React for web, Dart/Flutter for mobile, Cloudflare for deploy. **An existing
project's stack always wins** — no agent proposes a rewrite you did not ask for.

**Write as little as possible.** `implement-agent` climbs a ladder before
writing anything: does this need to exist → is it already in this repo → stdlib
→ native platform feature → a dependency already installed → one line → the
minimum that works. Deliberate shortcuts get a `ponytail:` comment naming the
ceiling and the upgrade path.

**Two steps that touch the same file depend on each other**, even when neither
needs the other's behavior. Undeclared, they get built in parallel on separate
branches and land as a merge conflict rather than an error. `plan-agent`
declares those dependencies from the plans' *Scope* sections, and
`plan-judge-agent` re-checks every parallel pair for a file in both.

**Every loop has a ceiling.** Market and judgment: two passes. Audit: two. Plan
judgment: two. Review: three. Then it reports what is still open and moves on. A
loop with no exit is how work dies in review instead of shipping.

**The files are the output; the message is a receipt.** Every agent writes its
work to `.agent-workbench/` and returns only a `VERDICT:` line and the paths it
wrote. Nothing restates its findings in the reply. Two reasons: the caller has
Read, so a summary is a second copy that drifts from the first — and a pipeline
where ten agents each narrate into the orchestrator's context fills it with
prose nobody reads. Open the file.

**Verdicts are labelled, not positional.** Every agent another agent acts on
emits a line starting `VERDICT:` — `VERDICT: GREEN — screens`,
`VERDICT: 2 blocking, 1 non-blocking`, `VERDICT: MERGED step-3-auth` — and
callers grep for that line rather than reading the first one. This started as a
first-line rule and was changed after testing: agents kept opening with a line
of throat-clearing and pushing a perfectly good verdict to line three. Position
is not a contract a language model reliably honours; a label is one it can
satisfy while still being chatty.

**Reasoning is tiered, not uniform.** The agents that hold a whole set in their
head at once — planning, judging, verifying, reviewing, implementing — run on
Opus at high effort, and `plan-agent` runs at `max`, because a bad plan is
copied into every step that follows it. The two doing legwork rather than
judgement, `market-agent` and `audit-agent`, run on Sonnet. Change either in the
agent's frontmatter if that balance is wrong for you.

**Green is a real answer.** Every judge and auditor is told to pass cleanly when
the work holds. One that always finds something teaches everyone to ignore it.

## Running on a non-Anthropic backend

The pipeline works on any Claude Code backend — GLM/Z.ai, a local model, an
OpenAI-compatible proxy — because subagents, parallel worktrees and the
`.agent-workbench/` state model are harness features, not model-API features.
Two things need attention:

**Model aliases.** Agent frontmatter accepts `opus`, `sonnet`, `haiku` or
`inherit`, never a raw model id, so the tiering above is only real if those
aliases map to different models. Point them somewhere distinct:

```json
"ANTHROPIC_DEFAULT_OPUS_MODEL":   "<your strong model>",
"ANTHROPIC_DEFAULT_SONNET_MODEL": "<your fast model>"
```

Map both to the same id and every agent runs identically — which works, but the
tiering is doing nothing.

**Web search.** `market-agent` prefers `WebSearch`, which executes on the model
provider's side and may not exist off Anthropic. It falls back to `WebFetch`
(client-side, universal), then to any web-search MCP tool present, and returns
`NO SOURCES` rather than writing a competitive landscape from memory. A failed
search and an empty market are opposite findings; the agent will not conflate
them.

## Checking the workbench

The agents write markdown that other agents parse, so drift is otherwise
silent. One script catches the mechanical half, with no model involved:

```
scripts/check-workbench.sh            # or: scripts/check-workbench.sh path/to/.agent-workbench
```

It fails loudly on: a tracker row whose directory is missing, a dependency on a
step that does not exist or is built later, a status nothing ever writes, a
`done` step with no `findings.md`, a *Resources* path that no longer resolves,
a screen no journey reaches, a missing `approved:` line, and a loop that has
run past its ceiling. Exit 0 clean, 1 on problems.

Run it between stages — after planning, and after each merge. It is free and
instant, and every one of those failures is invisible until something builds
against it.

## The run log

After each agent returns, the caller records what it said:

```
scripts/wb-log.sh audit-agent "spec: 6 gaps" "round 1"
scripts/wb-log.sh implement-agent "MERGED" "step-3-auth"
```

That appends to `.agent-workbench/run-log.md`, which is append-only — a verdict
that keeps repeating is the thing you want to see. It is also the evidence
`check-workbench.sh` uses to catch a loop that is not closing, which matters
because the alternative is an agent counting its own rounds in a file it wrote
itself. That is not a control.

## What it costs

Measured on real runs, not estimated. One build step through the full chain —
`verify-agent`, build, `review-agent` twice, merge — took **13 minutes and
~55k tokens**. A `product-agent` round is 38–75k depending on whether
`market-agent` runs inside it.

Where those tokens go, for one 54.8k build step:

| | tokens | share |
|---|---|---|
| Agent prompts (its own plus nested) | ~6k | 11% |
| Files it wrote | ~6.2k | 11% |
| Tool results replayed across 37 turns | ~42k | 78% |

So the prompts are not the lever — trimming them costs correctness to save a
tenth. **Turns are the lever**, because every tool call re-sends everything
before it, which makes cost roughly quadratic in call count. Each agent carries
a `## Cost` section about batching calls, never re-reading a file, and grepping
instead of reading whole files.

Output is the second lever. `market.md` once came out at 9,076 tokens for
sixteen competitors — 570 each, where a table row is 60. Every agent now has a
stated length budget, and the append-forever files collapse earlier rounds to
one line.

The third lever is the model, and it was settled by testing rather than
argument. The four grading agents were moved to Sonnet and one was moved back.

`review-agent` reviewed a diff Opus had blocked, and returned `APPROVED`. It
followed the procedure correctly — it even mutation-tested the suite by
reverting the rounding term — but accepted `assert apply_tax(101, 5000) ==
152` as pinning half-up. 151.5 rounds to 152 under half-up *and* under
banker's rounding, so the assertion excludes floor and nothing else. Opus
caught that and changed it to `103 → 155`, where the two rules disagree. A
review that follows every step and misses the thing inside it is worse than a
shallow one, because it reads as thorough.

`verify-agent` on Sonnet went the other way in its own test: it caught a plan
that returned floats against a codebase pinned to integer cents, found the
convention by reading an earlier step's `findings.md` unprompted, and traced
the consequence into the step that would consume it. So it stayed on Sonnet.

The rule that came out of this is not "judgement needs Opus" — it is that
reasoning about *numerical or semantic edge cases inside code* needs Opus,
while reading documents for what is missing does not.

Formerly: eight of ten agents ran on Opus. Moving the
judgement-heavy ones to Sonnet is roughly a 5× cost cut, and it is a real
trade — under test, `review-agent` on Opus mutation-tested a suite and caught a
half-up assertion that did not actually discriminate. Try it and compare before
deciding.

## Should you commit `.agent-workbench/`?

Usually yes. The plans, findings, and mockups are review material, and
`reconcile-agent` commits plan edits as it goes. Add it to `.gitignore` only if
you want the workbench private to your machine — but then reconciliation stops
working for anyone else.

## Using an agent on its own

Nothing forces the whole pipeline. Each agent works alone:

- `verify-agent` on any plan you wrote yourself, before you build it.
- `judge-agent` on a spec from anywhere.
- `market-agent` when you just want to know who else is in the space.

## License

MIT.
