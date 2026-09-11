---
name: workbench
description: Orchestration protocol for the agent-workbench pipeline. Use when starting or resuming any agent-workbench run, when a spawned agent returns a VERDICT or a dispatch request, when the user answers a queued question or approves a spec or epic, before spawning implement-agents, and when step branches come back ready to merge. You are the only participant guaranteed a spawn tool — this skill is how every inner pass gets dispatched.
---

# Workbench orchestration

You are the orchestrator. Every agent in this pipeline starts with no memory
of your conversation; `.agent-workbench/` is the state that survives between
them. You do not judge the work — each agent rules on its own pass — you
route: spawn the right agent with a self-contained prompt, relay what comes
back, and write the two records that are yours alone, the `approved:` line
and the tracker's status column.

## Rules that hold everywhere

- **You spawn; the agents rule.** Never run a pass inline because it looks
  small — an unsourced market pass or a self-review poisons everything
  downstream of it. A pass that cannot be dispatched waits.
- **Find the verdict, do not read for it.** Every agent answers on a line
  starting `VERDICT:` — grep for it anywhere in the report, then open the
  file the receipt names; the findings live there, not in the message. No
  `VERDICT:` line at all is a failure: re-run the pass once, then report it
  as not done, never as the good outcome.
- **Every dispatch is self-contained.** The agent you spawn does not know
  the product, the phase, or what just happened in this chat. Name the
  target file, the paths, and — on every round after the first with that
  agent — what changed since it last ran. At this level there is no resume:
  every round is a fresh spawn, so the prompt carries what a transcript
  otherwise would.
- **Independent passes spawn in parallel, in one block.** Dependent passes
  wait. One dispatch round is: spawn → read verdict → return to the agent
  that asked for the pass, with the paths of what it wrote.
- **Questions relay by number, batched up to the first blocker.** The queue
  is `state.md`'s *Open* section, most blocking first — read it; never paste
  it at the user wholesale. Each entry carries a `blocks` field. Walk the
  queue in order and put the run of `blocks none` questions through the
  picker together, **up to four in one call** — they are independent by the
  asking agent's own declaration, and asking them one at a time is the
  slowest thing this pipeline does. Stop the batch at the first question that
  blocks something: ask that one alone, and go straight back to the agent
  with the answer before asking anything it named. A queue entry with no
  `blocks` field at all is a blocker — ask it alone; do not assume `none`.
  Relay each question exactly as written, and record every answer verbatim,
  including the option they rejected. An "Other" answer carrying content the
  options did not anticipate ends the round wherever it lands — go back early
  with what you have.

## Find where the run is

Read `.agent-workbench/` before dispatching anything. The files say which
phase you are in; your memory of this chat does not.

| You see | The run is at | First dispatch |
|---|---|---|
| no workbench, no idea what to build | scouting | `scout-agent` |
| no workbench, an idea | discovery, round 1 | `product-agent` with the idea |
| `product/state.md`, no `approved:` | mid-discovery | `product-agent` with the new answers, plus any `pending dispatch` below |
| `state.md` `approved:` (or an approved epic row), no `knowledge/` | knowledge | `knowledge-agent` on the approved target |
| `knowledge/`, no tracker | planning | `plan-agent` |
| `step-feature-state.md` | build | the build loop |
| a receipt naming a dispatch | wherever it came from | that dispatch, then re-invoke its caller |

## Discovery — product-agent drives

Spawn `product-agent` with the idea (round 1) or the user's answers by
number (later rounds). It reads `state.md` itself; you never summarize the
spec to it.

Its receipt is one of:

- `ROUND <n>, phase <p> — <k> questions queued` → relay from *Open* in
  batches, per the rule above, and bring the answers back as a new dispatch.
- `pending dispatch` in the counters → spawn what it asked for, in this
  order: `market-agent` with the `target:` line, then `judge-agent` with the
  same target, then `audit-agent` three times in one parallel block —
  `scope=spec`, `scope=journeys`, `scope=screens`; journeys and screens are
  skipped only when the spec records no UI, and one auditor alone is fine
  there. Then re-invoke `product-agent` with the paths written.
- `READY` → ask the user. On a yes, **you** write `approved: <today>` into
  `state.md` — or into the epic's row in `epics-state.md`, never into
  `spec.md`. `plan-agent` refuses to run without it, and an approval nobody
  wrote down is an approval that gets re-litigated after the plan exists.

`NO SOURCES` from `market-agent` is a missing picture, not an empty one —
relay it as such and let `product-agent` record it.

## Knowledge — before anything gets planned against it

The moment the spec is approved, spawn `knowledge-agent` on it, once. No
agent that plans, builds, verifies or reviews in this pipeline can reach a
registry or a changelog; they work from training memory, and they agree with
each other while doing it. `knowledge-agent` is the only correction, and it
has to land before `plan-agent` writes tasks naming APIs that moved.

Its receipt is `<n> topics`, `NOTHING SURPRISING` — a good outcome, not a
failed pass; carry on — or `NO SOURCES`, which means the building agents are
about to work from memory alone. Say that to the user plainly rather than
letting it pass as a clean run; a stack they know is post-cutoff may be worth
fixing the search for first.

Run it again, on the named dependency only, whenever one appears that
`.agent-workbench/knowledge/` does not cover — `plan-agent` says so in a
plan, `verify-agent` returns it as a loose end, or a step is about to add a
library nothing has verified. It is a cheap pass; a step built against a
remembered API is not.

## Planning — plan-agent, then its judge

Spawn `plan-agent` with the goal and the paths in scope: the spec or epic
file, the tracker, `journeys.md`, the screens, and
`.agent-workbench/knowledge/` if it exists. Its own judge loop either
runs inside it or, on platforms that forbid nesting, comes back as a
dispatch request: spawn `plan-judge-agent` on `.agent-workbench/`, read
`plan-judgment.md` for its verdict, and re-invoke `plan-agent` with the
gaps. Two rounds is its ceiling; after that `plan-agent` reports the set
SHIPPABLE or says plainly what stays unresolved.

Do not build until the tracker exists and `plan-judge` has passed the set —
or `plan-agent` has hit its ceiling and told you so.

## The build loop

1. **Reconcile first.** Any `step-*/findings.md` whose `reconciled:` header
   is empty or absent — the value, never the line's presence — means
   `reconcile-agent` runs once, alone, with no builders in flight. Its
   judge check may come back as a dispatch request: run `plan-judge-agent`,
   then re-invoke `reconcile-agent` with the verdict path. It commits its
   own plan edits; you commit nothing here.
2. **Spawn builders — every runnable step, not the first one.** Walk the
   whole tracker and collect every row that is `planned` with all its
   dependencies `done`. Spawn one `implement-agent` for each, in a single
   parallel block, each with `isolation: "worktree"` and a prompt naming its
   step directory. Two runnable rows means two builders in that block; four
   means four. Taking them one at a time turns a plan that was written to
   fan out into a queue, and it is the difference between a build that takes
   four rounds and one that takes fourteen. A step whose dependencies are
   not all `done` is never offered — the builder refuses anyway, but the
   caller should not set it up to refuse.

   If the batch keeps coming out at one, the plan is a chain, not the
   pipeline: `check-workbench` prints `plan shape:` with the critical path
   and the widest batch, and warns when most steps sit on the path. Say so
   rather than grinding through it — the fix is `plan-agent` cutting the
   dependencies that name a shared file instead of a behavior, and it is
   cheaper at any point in the build than the serial build it replaces.
3. **Handle each receipt.**
   - `MERGED <branch>` → the builder ran the suite on the base branch after
     its merge. Trust but verify cheaply: `check-workbench`, and the next
     reconcile round reads its findings.
   - `READY TO MERGE <branch>` → a rebased, reviewed branch. **Merge one at
     a time yourself** — git refuses a branch checked out in another
     worktree, and two merges at once is how a green build disappears —
     running the suite on the base after each.
   - `STOPPED` naming a dispatch (`verify-agent`, `review-agent`) → spawn
     it with the absolute worktree root, step directory and branch the
     builder gave, then re-invoke the builder with the verdict's path. The
     verdict in the file is the only one that counts; never relay it as
     your own approval.
   - `STOPPED` for anything else — a dependency not `done`, unreconciled
     findings — → the row stays `planned`; it wrote nothing. Clear what it
     named and re-spawn later. Marking it `blocked` strands every step
     that depends on it for a step that was never attempted.
   - `BLOCKED <branch>` → record `blocked` in the tracker and move on;
     the receipt says what would unblock it, which is a decision for the
     user, not for you.
4. **Write the tracker yourself.** `done`, `blocked` — the builder never
   touches `step-feature-state.md`; several of it run at once and a shared
   file edited on several branches is a lost row.
5. Loop back to 1 until every row is `done` or `blocked`.

## Epics — after v1 ships

A new feature request against an approved `spec.md` is an epic, not a
reopening: dispatch `product-agent` as usual and let it notice the approval
itself — it scopes discovery to a new epic file and shrinks the phases that
do not apply. Your one addition: the approval line goes in the epic's
`epics-state.md` row. An approved epic is dispatched to `plan-agent` like
any other target; it continues the existing step and phase numbering.

## Between stages

Run the plugin's `check-workbench` against the repo (it defaults to
`.agent-workbench/`) after planning and after each merge — it is free, and
it catches tracker drift before an agent reads it as fact. If you cannot
locate the script, say so and continue; it is a safety net, not a gate.

## Cost

Dispatches are turns and turns replay context. Batch the independent spawns
into one block, never re-read a file a verdict already told you about, and
do not restate an agent's findings back to it when you re-invoke — name the
paths and what changed. Your context is the pipeline's shared hallway;
prose you keep out of it is budget every later dispatch spends on work.
