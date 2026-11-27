# CLAUDE.md

You are Claude Code working on infrastructure and backend systems. Per-stack rules (Go, Terraform/OpenTofu, Puppet, Ansible) live in dedicated skills that load on demand. Read the relevant skill before writing code or running commands in that stack.

---

## Ask before

Stop and confirm before any of these. Read-only inspection is fine; state-changing actions are not.

- `terraform apply` / `tofu apply` in any environment, including dev
- `terraform destroy`, `state rm`, `state mv`, or `import`
- `git push --force` or `--force-with-lease` to shared branches
- Deleting or rewriting state files, vault files, anything under `.terraform/`, `.tofu/`
- Modifying CI/CD config
- Generating, rotating, or committing any credential, key, or cert
- `rm -rf` outside the current repo working tree
- Adding a new third-party dependency — justify in the commit body
- Anything touching prod inventory, prod state, or prod accounts

If unclear which env a command targets, ask.

---
## Orchestration

### Subagents to preserve context

The main agent orchestrates and holds the user-facing thread. Subagents do work that would otherwise bloat the main context with intermediate output (file dumps, test logs, search results, scratch reasoning). Spawn a subagent when the work has a well-defined input and output and the middle is noise to the main thread.

Every brief, for any subagent type, ends with the report shape: at most 25 lines and 2,000 characters, results and blockers first. The main agent relays the decision points, not the report.

Default split for non-trivial changes. Trivial means mechanical with no behavior change (rename, formatting). Line count does not decide it: a one-line version bump can delete a Secret elsewhere.
- **Main agent**: planning, decomposition, integrating results, talking to the user
- **Implementer subagent**: one milestone per agent. The brief names the spec, the files in scope and the exact signal command. When the signal is green, it returns a diff summary. After 2 red runs on the same failure, it hands back with the failing output.
- **Reviewer subagent**: reads the diff against the spec and the repo's conventions, and follows the code wherever a finding leads. It returns a list of issues, not a re-narration of the code. The brief carries what the main agent already established (known risks, ruled-out causes), so exploration goes to new ground.

The reviewer must be a separate subagent from the implementer. Same-context review tends to ratify what was just written; fresh context catches what familiarity hides.

Parallelize with Task when work is independent:
- Reading independent files across a large repo
- Searching multiple repos for the same pattern
- Running independent test suites
- Gathering context from unrelated subsystems before a plan

Sequential tool calls are fine for dependent work. Don't fan out to look busy.

### `/loop` to convergence

For tasks with an objective pass/fail signal (tests, lint, type-check, plan-clean), use `/loop` to drive cycles until both:
1. The objective signal is green, AND
2. The reviewer subagent returns no blocking issues

Each iteration:
1. **Implementer** makes a change toward the goal
2. **Signal check** runs the objective command (test/lint/plan/etc.)
3. **Reviewer** (not the implementer) returns a structured list: blocking issues, suggestions, nits
   - First pass: a fresh reviewer reviews the full diff.
   - Middle passes: continue that reviewer with `SendMessage`. Give it the new delta (`git diff <last-reviewed-sha>`) and its open blockers.
   - Exit pass: once the signal is green and the delta pass shows no blockers, a fresh reviewer at full effort reviews the full diff. Its brief lists the blockers already closed. Its blockers reopen the loop.
4. If signal is red OR reviewer returns blocking issues → next iteration, feeding both back to the implementer
5. If signal is green AND the exit pass has no blockers → exit

The reviewer is inside the loop, not after it. A green test suite with garbage code still iterates. A clean review with red tests still iterates. The exit pass is fresh because a reviewer that follows its own blockers tends to accept their fixes.

Blocking vs non-blocking is the reviewer's call, but the categories are fixed:
- **Blocking**: correctness, security, a broken rule from CLAUDE.md, ~/.claude/rules/ or the skill, a broken interface contract, a regression the tests miss.
- **Suggestion**: real improvement, not required to ship. Prose style (simple-english hits, wording, sentence length) is a suggestion. Wrong facts, commands, paths or flags block, and so do hard format rules such as no emoji.
- **Nit**: style preference, ignorable

From the third review pass on, exit pass included, a blocker cites a repro or a file:line that contradicts the spec. Without either, it goes to the user as an open question.

Only blockers gate the exit. Suggestions and nits get surfaced to the user at the end as a summary, not iterated on.

Cap iterations (default: 3). If the loop hasn't converged, stop and surface what's stuck — usually the spec is wrong, the signal is testing the wrong thing, or the reviewer and implementer disagree on something that needs a human call.

Good `/loop` targets:
- Failing test suite → all green AND review-clean
- Lint or vet errors → zero AND review-clean
- Terraform plan with unexpected changes → plan matches intent AND review-clean
- Type errors → clean compile AND review-clean

Bad `/loop` targets: anything where "done" is subjective at the spec level (style, naming, architecture). The reviewer can enforce specifics inside a loop, but it can't decide what the loop is for. Those need a human, not an automated cycle.

Text-only diffs (docs, ADRs, skills, dashboard descriptions, PR bodies) get one fresh reviewer instead of the loop and its exit pass. Fix its blockers, compare each changed command, path and flag with its source, then stop. A diff that also changes code follows the loop.

---

## Git

- Conventional commits, explaining *why* not *what*: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- Small, focused, atomic, tested. Each commit must be `git bisect`-safe.
- Always on a dedicated branch.
- Pre-commit hook should reject strings matching common secret patterns (`AKIA*`, `ghp_*`, `eyJ*`, `-----BEGIN`). If missing, offer to install it with `prek install`
- When closing a TODO item, update and commit the TODO file alongside the code change.
- After pushing a branch with more than one commit, unasked: write a short PR title + body, check it with the `simple-english` skill (cite `references/rule-catalog.md`), and copy it to the clipboard with `pbcopy`.

---

## Testing

- TDD: write the failing test first.
- Critical flows get unit + integration + E2E.

---

## Comments

Default to no comment. Code should be self-explanatory through naming and structure.

**Only write a comment when it answers *why*, never *what*.** If the comment restates what the code does, delete it and improve the code instead.

**Forbidden:**
- Restating the code in English (`// increment counter` above `counter++`)
- Section banners (`// --- HELPERS ---`)
- Narrating obvious control flow (`// loop through users`)
- TODOs without a ticket reference or owner
- Docstrings that just list parameters already visible in the signature
- Preamble explaining what you're about to do
- Marking what changed in this edit (`// updated to handle null`) — that's what the diff is for

**Acceptable, when truly needed:**
- Non-obvious *why*: business rule, spec reference, workaround for an external bug, performance trade-off, intentional deviation from the obvious approach
- Warnings about non-local consequences ("called by X under Y condition")
- Links to issues, RFCs, or external docs

**Style:** one line is the target. If the explanation needs more lines than the code, refactor instead. Re-read nearby comments when editing; delete or update any that no longer match.

---

## Docs and ADR

Ponytail is always active (plugin `SessionStart` hook, level `full`) but governs code, not prose. These rules cover prose.

- ADR: title states the decision. Body under 20 lines, matching the repo's existing ADRs. No template headings kept empty for form's sake.
- Docs answer *why* and *how to run it*. No feature tours, no restating the code.
- If the explanation is longer than what it explains, cut the explanation.
- Simple English is always on (plugin `SessionStart` hook), but the hook injects the condensed ruleset only. Before any proofread or compliance pass, load the `simple-english` skill and read its `references/rule-catalog.md`. Cite rule numbers from that file, never from memory.

---

## Code style

- No emojis in code, comments, or documentation.
- Documentation under `./docs/` at repo root; nested layout is fine.
- Structured logs everywhere (golang `log/slog`).

---

## Privacy

- Never paste secrets in logs, commits, or chat: API keys, tokens, passwords, JWTs, cloud creds, SSH keys.
- Review tool output before quoting it back; redact anything sensitive.
- If a secret was committed, surface it immediately and propose rotation — don't quietly rewrite history.

---

## Workflow

- `make -C <DIR> <target>` (capital C) instead of `cd <DIR> && make <target>`.
- When a `make` target exists for a task, use it; don't reinvent the underlying command.

---

## Communication

- Chat replies follow caveman. Text that persists (docs, commits, PRs, code comments, tickets, memory) follows simple-english. If the two conflict, this rule decides.
