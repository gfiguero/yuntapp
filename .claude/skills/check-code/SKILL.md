---
name: check-code
description: Run all code quality checks across the entire Rails codebase — linting, tests, and security analysis.
user-invocable: true
---

Run all code quality checks for the yuntapp Rails project. Maximize parallelism — launch all independent checks simultaneously.

## Checks to run

**Group 1 — Run in parallel:**

1. **StandardRB**: `bundle exec standardrb` (Ruby Standard style — includes RuboCop rules)
2. **ERB Lint**: `bundle exec erb_lint --lint-all` (ERB template lint)
3. **Routes**: `bin/rails routes` (verify routes compile without errors)

**Group 2 — Run after Group 1 (heavier):**

5. **Tests**: `bin/rails test` (full Minitest suite)
6. **Coverage**: Check SimpleCov output after tests for coverage percentages

## Summary table

After all checks complete, present this table:

| Check | Result |
|-------|--------|
| StandardRB | pass/fail (N offenses) |
| ERB Lint | pass/fail |
| Routes | pass/fail |
| Tests | X tests, Y assertions — pass/fail |
| Coverage | Lines: X% / Branches: X% |

## Error reporting

If any check fails, show the relevant error output below the table. For StandardRB, list the top offenses by count.

## Notes

- Group 2 tests run separately so their output doesn't interleave with linting.
- Coverage is informational — report the numbers but don't fail on thresholds.
- If a tool is not installed, skip that check and report "skipped (not installed)" in the table.
