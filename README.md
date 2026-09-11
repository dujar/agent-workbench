# agent-workbench

Twelve subagents for [Claude Code](https://claude.com/claude-code) that carry
a product from a vague idea — or no idea at all — to merged code, with a judge
at every handoff.

Every agent starts with no memory of your conversation. Everything they know
comes from `.agent-workbench/`, which is the whole point: the work survives
compaction, a closed laptop, and a colleague picking it up on Monday.

## Install

```
/plugin marketplace add dujar/agent-workbench
/plugin install agent-workbench
```

Or from a local clone:

```
claude plugin marketplace add /path/to/this/repo
claude plugin install agent-workbench@agent-workbench --yes
```

Either way, **restart the session**: agent definitions load at startup.
`claude --continue` resumes the conversation with them available.

### Editing the agents

A directory source does **not** hand your working copy to the session. Install
copies the plugin into a version-keyed cache
(`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) and the session
loads that. Edit `agents/*.md`, restart, and you get the snapshot from install
day — silently, with no warning that the file you just changed is not the file
running.

`claude plugin update` does not rescue you either: it compares versions, and an
unchanged `plugin.json` means "already at the latest version". So the loop is
**bump, update, restart**:

```
# edit agents/*.md, then:
$EDITOR .claude-plugin/plugin.json     # bump "version"
claude plugin update agent-workbench   # copies the new version into the cache
# restart the session
```

Skip the bump and the update is a no-op. To check what is actually loaded,
diff the cache against the repo:

```
diff -rq ~/.claude/plugins/cache/agent-workbench/agent-workbench/*/agents agents
```

Changing a definition is more than editing prose: the definitions parse each
other's files and grep each other's verdict lines, so a format change ripples.
[AGENTS.md](AGENTS.md) lists the parse contracts and their readers — read it
before changing anything under `agents/`, `bin/`, or `skills/`.

`claude plugin details agent-workbench` shows the component inventory and what
it costs — roughly 1.4k tokens always-on for the twelve descriptions, and
1.7k–8.2k per agent invocation. `claude plugin disable agent-workbench` turns it off for
projects that do not need it.

### Running under ZCode

ZCode installs this plugin and registers all twelve agents, but spawned
agents there get no spawn tool — the `Agent(...)` requests in the frontmatter
are recorded and then stripped — so the agent-to-agent delegation the
definitions describe cannot run from inside an agent. The fix is flattened
orchestration, and the plugin ships it as a skill: **`/workbench`** is the
dispatcher protocol for exactly this. Invoke it when a run starts or resumes
and it drives every inner dispatch from your session — the only place the
spawn tool lives.

- `product-agent` marks the delegated passes `pending dispatch` and returns a
  spawn list; you run `market-agent`, then `judge-agent`, then the three
  `audit-agent` scopes, and re-invoke it. The artefacts land in the same
  files, so nothing else changes.
- `implement-agent` stops and asks for `verify-agent` / `review-agent`
  dispatches; each review round is a fresh spawn — there is no
  resume-by-send — with what changed since the last round in your dispatch
  prompt.
- `reconcile-agent` edits the plans and hands the `plan-judge-agent` dispatch
  back to you before anything is committed.

The rule that survives every platform: a judge never runs inline. If a pass
cannot be dispatched, it waits — an unsourced market pass or a self-review
poisons everything downstream of it.

Install: **Settings → Plugin Management → Discover → `+`**, add this repo as
a marketplace (GitHub URL or local directory), and install `agent-workbench`.
The cache is version-keyed the same way, so the bump–update–restart loop
applies too; the plugin UI's update button replaces `claude plugin update`.

## The flow

```
  scout-agent   (only if you do not have an idea yet — candidates, with metrics)
       │
       ▼
  product-agent ──> market-agent ──> judge-agent ──> audit-agent ×3
       │  (asks you up to four questions at a time, with options)
       ▼
   ★ your approval  ──────────────────────────────────────────
       │
       ▼
   knowledge-agent   (what is actually true about the stack, right now)
       │
       ▼
   plan-agent ──> plan-judge-agent
       │  (phases of steps, one directory per feature)
       ▼
   implement-agent ──> verify-agent ──> review-agent ──> merge
       │  (one per step, in parallel worktrees)
       ▼
   reconcile-agent   (folds each step's findings back into the plans that follow)
       │
       ▼
   shipped — spec.md is now frozen
       │
       ╰──> a new feature request re-enters at product-agent, as an epic
            instead of new-product discovery — see *Evolving a shipped
            product* below, then the loop above repeats for just that epic
```

### 0. Scout — `scout-agent`, only if you need it

Skip this if you know what you are building. If you do not, `scout-agent` is
the entry point: it asks what you do all day and what you already work around,
searches where people complain in public, and comes back with five to eight
candidate **problems** — each with a demand number and its source, the
incumbent who serves it badly, **why that incumbent has not fixed it**, where
you would find the first hundred users, the shape (web, desktop, mobile, CLI),
and whether one build cycle can ship it.

Two invocations at most: one to ask, one to deliver. It returns `NO SOURCES`
rather than writing a trend list from memory.

What it writes is a **seed, not a spec**. You pick a candidate and
`product-agent` still grills you from zero — which matters most for a candidate
marked `cold`, meaning it came from search rather than from your own working
life. `judge-agent` asks *"who have you actually watched hit this problem?"* in
phase 3, and a cold pick has no answer.

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

It asks **in batches of up to four, with options**, recommended answer first,
so you approve rather than compose. Every question declares what it blocks;
independent ones go through the picker together, and a question whose answer
could retire a later one is asked alone. Phases 2 and 3 are loops, capped at
two passes each — a spec that dies in research never ships.

It returns `READY` and stops. Nothing gets planned until you say yes.

Once `spec.md` is approved, it is frozen — this same six-phase grilling runs
again for any later feature request, but scoped to a new epic file instead of
reopening `spec.md`. See *Evolving a shipped product*.

### 2. Approve

Approval is a line on disk, not a sentence in chat:

```
# .agent-workbench/product/state.md
approved: 2026-09-08
```

`plan-agent` reads it and refuses to run without it. An approval nobody wrote
down is an approval that gets re-litigated after the plan exists.

### 3. Learn the stack — `knowledge-agent`

Of the twelve agents, exactly two could reach the internet before this one:
`scout-agent` and `market-agent` — and neither ever touches code. Everything
that plans, writes, verifies and reviews works from training memory, and
because they share a cutoff they agree with each other about a library that
moved eighteen months ago. Nothing in the loop catches it: the reviewer is as
out of date as the implementer, so a dead API passes review on the reviewer's
authority.

`knowledge-agent` is the correction. It resolves what `spec.md` left as
"latest stable" into a real version, reads the changelog between what a model
remembers and what shipped, and writes one file per topic to
`.agent-workbench/knowledge/`.

Each file is a **diff against what a model already believes**, never
documentation — the version that is actually current, the export that got
renamed, the argument that became required, the two dependencies that need a
specific pairing. If reading the docs confirms what it would have assumed
anyway, it writes one line saying so and stops. Forty lines is the ceiling and
every claim carries the URL it came from.

`plan-agent` then links the relevant files on each plan's `knows:` line, and
`implement-agent`, `verify-agent` and `review-agent` are all told the same
thing: **a knowledge file outranks your memory — that is what it is for.**
Which is exactly why it returns `NO SOURCES` and writes nothing rather than
guessing. A file that gets trusted over everyone's recollection is the worst
possible place for a remembered API shape; silence leaves every agent as
well-informed as it already was, and a confident wrong file makes them worse
without anyone finding out.

`NOTHING SURPRISING` is a real verdict and a common one. Run it again when a
new dependency appears that nothing in `knowledge/` covers.

### 4. Plan — `plan-agent`

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

### 5. Build — `implement-agent`

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

### 6. Reconcile — `reconcile-agent`

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

## Evolving a shipped product

`spec.md` is a record of what shipped, not a living document — once it is
`approved`, it is frozen, the same rule a `done` step's `plan.md` already
follows. A later request to add, change, or extend the product is a new
**epic**, never a reopening of `spec.md`.

Invoke `product-agent` the same way. It notices `spec.md` is already
`approved` and treats the request as an epic instead of new-product discovery:

```
.agent-workbench/product/
  epics/
    epic-2-notifications.md   one file per post-v1 change
  epics-state.md               the ledger — every epic and its status
```

The same six phases run, scoped to the epic file instead of `spec.md` —
`state.md` tracks which one via a `target:` line, and `market-agent`,
`judge-agent`, and `audit-agent` all read whatever it names. Several phases
shrink for an epic and say so rather than re-running at full weight: stack is
almost always "existing, unchanged," market research only reruns if the epic
opens genuinely new competitive ground, journeys and screens usually **add**
rather than replace. `judge-agent` never shrinks — "is this actually needed"
applies to a five-line epic exactly as to a whole product.

Once an epic is `ready` and the user approves it in `epics-state.md`,
`plan-agent` recognizes it as the next thing to plan — continuing step and
phase numbering from wherever the tracker already stood, never restarting at
1. Every step it plans for that epic links the epic file from its own
`Resources` block, the same way every step already links `spec.md`, so tracing
a step back to why it exists is a grep, not a separate index to keep in sync.

## Who orchestrates what

You (or the main agent) drive the outer loop. The subagents cannot talk to you
and cannot see each other. The protocol below ships as a skill — invoke
`/workbench` (or let the session load it when a run starts) rather than
holding it in your head; it also covers the dispatch requests the flattened
loops on ZCode produce.

1. Any `findings.md` whose `reconciled:` line carries no date → run
   `reconcile-agent` once, with no builders running. The value, never the line.
2. Spawn one `implement-agent` per ready step, in parallel, `isolation: "worktree"`.
3. A builder returning `READY TO MERGE` has a rebased, reviewed branch. **Merge
   those one at a time** — git refuses to update a branch checked out in another
   worktree, and two merges at once is how a green build disappears. After each
   merge, run the suite on the base branch before merging the next.
   **If a merge conflicts**, the undeclared-collision plan-judge missed has
   arrived. Resolve it yourself, keeping both sides' *intent* (both
   registrations, both calls — not picking one branch's file wholesale), run
   the suite, and record the collision in the surviving steps' `findings.md`;
   if the conflict is too tangled to resolve with confidence, reset the merge
   (`git merge --abort`), and re-spawn the second builder to rebase onto the
   new base itself. Two builders each wrote their half against the same file;
   the merge is the only place anyone sees both halves together.
4. Set that row's status in `step-feature-state.md` to `done`, or `blocked`.
   A `STOPPED` builder is neither — it never branched, so it wrote no
   `findings.md` and changed nothing. Leave the row `planned`, clear what it
   named, and re-spawn it. Marking it `blocked` strands every step that
   depends on it, for a step that has not been attempted.
   On `BLOCKED`, salvage the lessons: copy the step's `findings.md` from the
   branch into `.agent-workbench/` on the base branch before the worktree is
   cleaned up — a blocked branch never merges, so `reconcile-agent` can
   never see what the attempt taught unless you copy it out.
   Loop back to 1.

`plan-agent` prints exactly this list, with your step numbers filled in.

## The agents

| Agent | Model | Does | Writes |
|---|---|---|---|
| `scout-agent` | sonnet / medium | Finds candidate problems with demand metrics, when you do not have an idea | `product/scout.md` |
| `product-agent` | opus / high | Grills the idea into a spec or a post-v1 epic, in six phases | `product/spec.md` or `product/epics/*.md`, `journeys.md`, `state.md`, `screens/*.html` |
| `market-agent` | sonnet / medium | Web research on whatever `target` names: competitors, metrics, complaints | `product/market.md` |
| `judge-agent` | sonnet / high | Adversarial holes in whatever `target` names | `product/judgment.md` |
| `audit-agent` | sonnet / medium | One scope of thoroughness against `target` — `spec`, `journeys`, or `screens` | `product/audit-<scope>.md`, or `-epic-<n>` for an epic |
| `knowledge-agent` | sonnet / medium | What the building agents do not know: real versions, APIs that moved since the cutoff, footguns in this stack | `knowledge/*.md` |
| `plan-agent` | **opus / max** | Phases and steps, one plan per feature — v1 or the next approved epic | `step-*/plan.md`, the tracker |
| `plan-judge-agent` | sonnet / high | Does the plan set reach a finished product, and can its parallel steps actually run in parallel? | `plan-judgment.md` |
| `verify-agent` | sonnet / high | Does one plan survive contact with the code? | `step-*/verify.md` |
| `implement-agent` | opus / high | Builds one step on a branch | code, `step-*/findings.md` |
| `review-agent` | opus / high | Reviews one branch against its plan | `step-*/review.md` |
| `reconcile-agent` | opus / high | Folds findings into the plans that follow | edits `step-*/plan.md`, `reconciliation.md` |

Plus `check-workbench` — no model, just invariants. See below.

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

**A dependency is behavior, not a file.** Step B depends on step A when it
reads a route, a column, a helper or a contract A creates — that is the only
edge worth serializing a build for. Shared append points are not dependencies:
a route table, a `migrations/` directory, a module list, a config binding block
collects a line from every feature, and chaining every feature because they all
append turns a plan set with no real order into a straight line that builds one
step at a time. Those land as a three-line merge conflict, which is exactly
what merging one branch at a time and running the suite after each is for. A
file two steps **rewrite**, or a region both edit, still earns the edge —
`plan-judge-agent` checks every parallel pair for one, and separately checks
that the set has not come out as a chain. `check-workbench` prints the shape:
`plan shape: 17 steps, critical path 8, widest batch 4`.

**Loops resume; they do not respawn.** A loop's second round sends a message
to the same agent instead of spawning a new one, so it picks up from its own
transcript already knowing the diff, the plan and what it flagged. Round two
is "fixed findings 1 and 3, re-check" rather than a cold re-read of
everything. A resumed reviewer still has to verify the fixes landed — resuming
is not rubber-stamping — and a send that fails falls back to a fresh spawn,
said out loud, because losing the loop is recoverable and silently skipping a
round is not.

**Parallel builds address by id and absolute path.** Several steps build at
once, each in its own git worktree, and each spawns a child called
`review-agent` — so a name resolves to whichever was created last and a
round-two message would land on another step's reviewer. Loops address their
children by the `agentId` the spawn returned. For the same reason no agent
trusts its working directory: a builder passes its worktree root as an
absolute path on every dispatch and every resume, and its children run `git -C
<root>` rather than assuming where they are. A review that ran against the
wrong worktree reviews someone else's code and reports nothing wrong.

**Every loop has a ceiling.** Market and judgment: two passes. Audit: two. Plan
judgment: two. Review: three. Then it reports what is still open and moves on. A
loop with no exit is how work dies in review instead of shipping.

**The files are the output; the message is a receipt.** Every agent writes its
work to `.agent-workbench/` and returns only a `VERDICT:` line and the paths it
wrote. Nothing restates its findings in the reply. Two reasons: the caller has
Read, so a summary is a second copy that drifts from the first — and a pipeline
where twelve agents each narrate into the orchestrator's context fills it with
prose nobody reads. Open the file.

**Verdicts are labelled, not positional.** Every agent another agent acts on
emits a line starting `VERDICT:` — `VERDICT: GREEN — screens`,
`VERDICT: 2 blocking, 1 non-blocking`, `VERDICT: MERGED step-3-auth` — and
callers grep for that line rather than reading the first one. This started as a
first-line rule and was changed after testing: agents kept opening with a line
of throat-clearing and pushing a perfectly good verdict to line three. Position
is not a contract a language model reliably honours; a label is one it can
satisfy while still being chatty. Stops follow the same rule:
`VERDICT: STOPPED — <reason>` for every briefing-contract refusal (no
approval, nothing to plan, wrong base, no such branch), so a caller grepping
for `VERDICT:` can tell a clean stop from a crash.

**Reasoning is tiered, and the tiers were set by testing.** Seven of twelve agents
run on Sonnet. Opus is reserved for the four that write or rewrite something
everything downstream inherits — `plan-agent` (at `max`, because a bad plan is
copied into every step after it), `implement-agent`, `reconcile-agent`,
`product-agent` — plus `review-agent`, which was moved to Sonnet and moved
back when it approved a diff Opus had blocked. The reasoning is under *What it
costs*.

**Green is a real answer.** Every judge and auditor is told to pass cleanly when
the work holds. One that always finds something teaches everyone to ignore it.

## How this is tested

The definitions are prose, so they are tested the way prose fails: by being
run. Each release goes through sandbox scenarios — a throwaway git repo, a
seeded `.agent-workbench/`, a scripted user persona, and one driver that plays
each agent by its definition literally, logging every invocation through
`wb-log` and staging through `check-workbench`. A scenario passes when it
completes, every checkpoint holds, and `check-workbench` exits 0 at every
stage it should. The current suite is 30 scenarios: discovery (vague, picky,
and pivoting users; resume-from-state; judge attacks), epics on shipped
products, planning and its escalation paths, the build loop (clean merges,
stops, resumes, parallel worktrees, review ceilings), reconciliation, and a
27-case invariant battery against the two scripts.

The last full pass found and fixed ten bugs, all of the kind a review of the
prose would never catch: a run-log pipe character that defeated the loop
ceiling, an approval gate that passed on `approved: pending`, a judge ceiling
no healthy project could stay under, stop paths no caller could parse. That is
the argument for the method — the bugs live in what one file writes and
another parses, which is exactly what a scenario drives and a read misses.

If you change a contract, re-run a scenario against it. If you change a
script, build the fixture and record expected against actual. Both are cheap;
the failures they catch are not.

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

**Web search.** `market-agent` and `scout-agent` prefer `WebSearch`, which executes on the model
provider's side and may not exist off Anthropic. It falls back to `WebFetch`
(client-side, universal), then to any web-search MCP tool present, and returns
`NO SOURCES` rather than writing a competitive landscape — or a list of product
ideas — from memory. A failed
search and an empty market are opposite findings; the agent will not conflate
them.

## Checking the workbench

The agents write markdown that other agents parse, so drift is otherwise
silent. One script catches the mechanical half, with no model involved:

```
check-workbench                  # or: check-workbench path/to/.agent-workbench
```

Both scripts live in the plugin's `bin/`, which Claude Code puts on `PATH`, so
they run by bare name from any project — there is nothing to copy in. From a
clone without the plugin installed, call them by path: `bin/check-workbench`.

It fails loudly on: a tracker row whose directory is missing, a dependency on a
step that does not exist or is built later, a status nothing ever writes, a
`done` step with no `findings.md`, a *Resources* path under `../` that no
longer resolves, a screen no journey reaches, a missing or still-`pending`
`approved:` line, an open `NEEDS REPLANNING` escalation, unreconciled
`findings.md` files while steps are still planned, a knowledge file with no
`checked:` date or no source URL, and a loop that has run past its ceiling.
Exit 0 clean, 1 on problems.

It also prints the plan's shape, which fails nothing and is worth reading
anyway:

```
  plan shape: 17 steps, critical path 8, widest batch 4
```

`critical path` is the longest dependency chain — the number of build rounds
the plan needs however many builders you spawn. `widest batch` is the most
steps that can ever run at once. When most of the steps sit on the path it
warns, because that is a plan that will build one step at a time and the
depends-on column is where to look.

Run it between stages — after planning, and after each merge. It is free and
instant, and every one of those failures is invisible until something builds
against it. One state is expected rather than alarming: **immediately after a
merge**, the just-finished step's `findings.md` is unreconciled while other
steps are still planned, so the check exits 1 telling you to run
`reconcile-agent` first. That is the check working — run reconcile, then run
it again; a project only ever ends clean after its final reconciliation.

## The run log

After each agent returns, the caller records what it said:

```
wb-log audit-agent "spec: 6 gaps" spec
wb-log review-agent "2 blocking" step-3-auth
wb-log implement-agent "MERGED" step-3-auth
```

That appends to `.agent-workbench/run-log.md`, which is append-only — a verdict
that keeps repeating is the thing you want to see. It is also the evidence
`check-workbench` uses to catch a loop that is not closing, which matters
because the alternative is an agent counting its own rounds in a file it wrote
itself. That is not a control.

**The third field is the loop, not the round.** Every ceiling here is per loop:
two audit rounds *per scope*, three review rounds *per step*, two market and
judgment rounds *per target*. So `check-workbench` counts rows grouped by
`(agent, loop)` — write the scope for `audit-agent`, the step directory for
`review-agent` and `verify-agent`, the target for `market-agent`,
`judge-agent`, and `product-agent`, and keep it
byte-identical across a loop's rounds. Two identities are made up as you go,
one per occurrence: a `plan-judge-agent` run triggered by `reconcile-agent`
gets `reconcile-<today>` — each reconciliation is its own loop, and logging
it as `plan` would trip the planning ceiling on every healthy project — and
`scout-agent` gets `scout`. Counted per agent instead, three
parallel audit scopes read as a runaway loop and the check fails on every
healthy project, which is how a check stops being read.

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

The result: seven of twelve agents run on Sonnet, where before all but two ran
on Opus. Moving the
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
- `scout-agent` when you want candidates with evidence and no commitment to
  build any of them.

## License

MIT.
