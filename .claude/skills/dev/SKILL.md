---
name: dev
description: Autonomous development pipeline — classifies a natural language prompt (feature/bug/refactor/tests) and runs the full route: branch → implement → review → PR. Single human checkpoint only for new features (spec approval).
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash(git *)
  - Bash(gh pr *)
  - Bash(gh issue *)
  - Bash(bin/rails test*)
  - Bash(bundle exec rubocop*)
  - Bash(bundle exec erb_lint*)
  - Bash(bundle exec standardrb*)
  - Bash(bin/rails db:migrate*)
  - Bash(ls *)
  - Bash(mkdir *)
  - Task
  - TaskCreate
  - TaskUpdate
  - AskUserQuestion
  - Skill
  - Agent
---

# Dev — Autonomous Development Pipeline

Classifies a prompt and runs the full development pipeline to a pushed branch with an open PR.

## Input

`$ARGUMENTS` — A natural language description of the work. Examples:

```
/dev "add a new filter by commune to the members list"
/dev "fix the crash when approving an onboarding request"
/dev "refactor the onboarding controller to use service objects"
/dev "write tests for the ResidenceCertificate model"
```

## Pipeline

### Step 0 — Pre-flight: check for suspended workflows

Before classifying the prompt, check `docs/specs/` for any spec file containing `Status: suspended` in its front-matter:

```bash
grep -rl "Status: suspended" docs/specs/ 2>/dev/null
```

If a suspended spec is found:
1. Present the spec file path to the developer
2. Ask: "There is a suspended spec waiting for approval: `<path>`. Do you want to resume it, or proceed with the new prompt?"
3. If resume: re-present the spec, wait for explicit approval, then continue at stage 2c (Branch) of the Feature route
4. If new prompt: proceed to Step 1 (Classification)

---

### Step 1 — Classify

Classify `$ARGUMENTS` into one of four routes:

| Route | Signals | Branch prefix |
|-------|---------|--------------|
| `feature` | "add", "create", "implement", "new", "build" | `feature/` |
| `bug` | "fix", "crash", "broken", "not working", "error" | `fix/` |
| `refactor` | "refactor", "centralize", "migrate", "clean up", "move" | `refactor/` |
| `tests` | "write tests", "add tests", "test", "coverage" | `tests/` |

If the prompt is ambiguous, ask one clarifying question before proceeding. Do not guess.

Generate a kebab-case slug from the prompt (lowercase, hyphens, max 40 chars). Examples:
- "add filter by commune to members" → `filter-by-commune-members`
- "fix crash approving onboarding" → `crash-approving-onboarding`

---

### Step 2 — Route

Execute the pipeline for the classified route. Every stage has a self-healing loop (see Self-Healing section). If more than 2 stages in the pipeline exhaust all 3 self-healing attempts, suspend the pipeline and escalate to the developer.

---

## Feature Route

```
[Pre-flight] → Classify → Brainstorm → [HUMAN APPROVAL] → Branch → Plan → TDD → Execute → Review → Finish → PR
```

**2a. Brainstorm**

Explore the codebase to understand context:
- Read relevant models, controllers, views, tests
- Identify patterns used in similar features
- Ask clarifying questions one at a time
- Write the spec to `docs/specs/YYYY-MM-DD-<feature>-design.md`

**2b. HUMAN APPROVAL ← mandatory checkpoint**

Present the spec file path and ask for explicit approval:

> "Spec written to `<path>`. Please review it and reply 'approved' (or request changes)."

- If changes requested: update spec, re-present
- Do NOT write any implementation code before receiving approval
- **If session ends before approval:** Set `Status: suspended` in the spec file's front-matter and stop

**2c. Branch**

After approval:

```bash
git fetch origin
git branch -a | grep "feature/<slug>"
```

If branch exists, append date: `feature/<slug>-YYYYMMDD`

```bash
git checkout main
git pull origin main
git checkout -b feature/<slug>
```

**2d. Plan**

Enter plan mode to design the implementation:
- List files to create/modify
- Order of implementation
- Schema changes (migrations) if needed
- Test strategy

**2e. TDD**

Write tests first following Minitest patterns:
- Model tests in `test/models/`
- Controller tests in `test/controllers/`
- Use fixtures from `test/fixtures/`

**2f. Execute**

Implement the feature following the approved plan and CLAUDE.md patterns.

**2g. Review** (self-review)

Review all changed files for:
- Security issues (SQL injection, XSS, mass assignment)
- N+1 queries
- Missing validations
- Rails conventions compliance
- I18n usage for user-facing strings

For each issue found: fix inline, re-review. Maximum 3 fix-and-retry cycles. If unresolved after 3 attempts, escalate to developer.

**2h. Finish + Push + PR**

Run validations, commit, push, create PR → see Finish Protocol and PR Protocol sections below.

---

## Bug Route

```
[Pre-flight] → Classify → Branch → Debug → Fix → Regression Tests → Review → Finish → PR
```

**2a. Branch**

```bash
git fetch origin
git branch -a | grep "fix/<slug>"
git checkout main && git pull origin main
git checkout -b fix/<slug>
```

**2b. Debug**

Reproduce the issue and identify the root cause. Limit codebase exploration to **15 files maximum**. If root cause cannot be identified within this limit, escalate to developer.

Document the root cause before proceeding to Fix.

**2c. Fix**

Apply a minimal targeted fix. Do not refactor surrounding code.

**2d. Regression Tests**

Write a regression test that fails without the fix and passes with it. Run:

```bash
bin/rails test
```

If the regression test fails, the fix is incomplete (fix the implementation, not the test). Self-healing loop applies (3 attempts max).

**2e. Review** (self-review)

Review for:
- Security (SQL injection, XSS, CSRF, mass assignment)
- N+1 queries
- Missing validations
- Rails conventions

Maximum 3 fix-and-retry cycles.

**2f. Finish + Push + PR**

See Finish Protocol and PR Protocol. Include root cause in PR body.

---

## Refactor Route

```
[Pre-flight] → Classify → Branch → Plan → Execute → Tests → Review → Finish → PR
```

**2a. Branch**

```bash
git fetch origin
git branch -a | grep "refactor/<slug>"
git checkout main && git pull origin main
git checkout -b refactor/<slug>
```

**2b. Plan**

The plan must: map what changes and what stays the same; identify all consumers of refactored code; order steps to preserve working state at each step.

**2c. Execute**

Verify `bin/rails test` passes after each major step.

**2d. Tests**

Run existing test suite. Add tests for any public method touched by this refactor that was not previously tested.

**2e. Review**

Check modified file paths. If any path contains `controllers/`, `models/concerns/`, `services/`, or authentication-related code, review for security issues first.

**2f. Finish + Push + PR**

See Finish Protocol and PR Protocol.

---

## Tests Route

```
[Pre-flight] → Classify → Branch → TDD Write → Run Tests → Review → Finish → PR
```

**2a. Branch**

```bash
git fetch origin
git branch -a | grep "tests/<slug>"
git checkout main && git pull origin main
git checkout -b tests/<slug>
```

**2b. TDD Write**

Read the source file to understand contracts and behavior. Follow existing patterns in `test/`. Write tests using Minitest with fixtures.

**2c. Run Tests**

```bash
bin/rails test <file>
```

If a test fails: apply the self-healing loop (3 attempts max). Tiebreaker: fix the test (not the source), since the tests were written as part of this change.

**2d. Review**

Self-review the tests for completeness and correctness.

**2e. Finish + Push + PR**

See Finish Protocol and PR Protocol.

---

## Finish Protocol

Run validations in sequence:

```bash
bundle exec standardrb --fix
bundle exec erb_lint --lint-all
bin/rails test
```

Stage specific files (never `git add -A`), commit, and push:

```bash
git add <files>
git commit -m "$(cat <<'EOF'
<concise description>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push -u origin <branch>
```

## PR Protocol

After push, create the PR:

```bash
gh pr create \
  --title "<concise title under 70 chars>" \
  --body "$(cat <<'BODY'
## Summary
- [bullet points describing what changed and why]

## Route
[feature | bug | refactor | tests]

## Root cause (bugs only)
[description of what was broken and why]

## Test plan
- [ ] [checklist of what to manually verify]
- [ ] Tests pass locally (bin/rails test)
- [ ] No lint errors (bundle exec standardrb)
- [ ] ERB lint passes (bundle exec erb_lint --lint-all)

🤖 Generated with Claude Code autonomous agent workflow
BODY
)" \
  --base main
```

---

## Self-Healing Loop

Every stage (except HUMAN APPROVAL) follows this loop on failure:

```
Attempt 1: apply targeted fix, retry stage
Attempt 2: broader diagnosis, retry stage
Attempt 3: alternative approach, retry stage
  → Still failing: escalate to developer with what was attempted, the exact error, and suggested next steps
```

**Specialized handlers:**
- Test failures → fix implementation or test (not both simultaneously); apply tiebreaker rule
- Lint errors → `bundle exec standardrb --fix` then fix remaining violations manually
- ERB errors → `bundle exec erb_lint --lint-all --autocorrect` then fix remaining

**Total pipeline cap:** If more than 2 stages exhaust all 3 attempts, suspend the pipeline and escalate with a summary of all failed stages.

---

## Constraints

- Never use `git push --force` or `--no-verify`
- Never amend published commits — always create new commits
- Never use `git add -A` — always stage specific files
- Never commit files matching `.env*`, `*.key`, `*.pem`, or in `.gitignore`
- Branch naming: `feature/<slug>`, `fix/<slug>`, `refactor/<slug>`, `tests/<slug>`; append `-YYYYMMDD` if branch exists
- Escalate before any destructive action (dropping tables, deleting files, reset --hard)

---

## Project-Specific Rules (yuntapp)

- **Framework:** Ruby on Rails 8.1.1 with Hotwire (Turbo + Stimulus)
- **Database:** SQLite3 with migrations
- **Frontend:** Tailwind CSS + DaisyUI, Turbo Frames/Streams, Stimulus controllers
- **Tests:** Minitest with fixtures, SimpleCov for coverage
- **Linting:** RuboCop (rails-omakase), Standard, ERB Lint
- **I18n:** All user-facing strings must use i18n (es.yml / en.yml)
- **Status fields:** Use string constants with manual `status?` methods, not Rails enums
- **Normalization:** Use `before_validation` callbacks for data normalization (RUN, phone, names)
- **Authorization:** Three levels — superadmin, admin, panel user
- **Asset Pipeline:** Propshaft + Importmap (no Webpack/esbuild)
