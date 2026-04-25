---
name: check-code
description: Run all code quality checks across the entire Rails codebase — linting, tests, security analysis and gem audits.
user-invocable: true
allowed-tools:
  - Bash(bundle exec standardrb*)
  - Bash(bundle exec erb_lint*)
  - Bash(bundle exec brakeman*)
  - Bash(bundle exec bundler-audit*)
  - Bash(bin/rails routes*)
  - Bash(bin/rails test*)
---

Run all code quality checks for the yuntapp Rails project. Maximize parallelism — launch all independent checks simultaneously.

## Checks to run

**Group 1 — Run in parallel:**

1. **StandardRB**: `bundle exec standardrb` (Ruby Standard style — includes RuboCop rules)
2. **ERB Lint**: `bundle exec erb_lint --lint-all` (ERB template lint)
3. **Routes**: `bin/rails routes` (verify routes compile without errors)
4. **Brakeman**: `bundle exec brakeman --no-pager -q` (static security analysis for Rails)
5. **Bundler Audit**: `bundle exec bundler-audit check --update` (known CVEs in gems)

**Group 2 — Run after Group 1 (heavier):**

6. **Tests**: `bin/rails test` (full Minitest suite)
7. **Coverage**: Check SimpleCov output after tests for coverage percentages

## Summary table

After all checks complete, present this table:

| Check | Result |
|-------|--------|
| StandardRB | pass/fail (N offenses) |
| ERB Lint | pass/fail |
| Routes | pass/fail |
| Brakeman | pass/fail (N warnings) |
| Bundler Audit | pass/fail (N vulnerabilities) |
| Tests | X tests, Y assertions — pass/fail |
| Coverage | Lines: X% / Branches: X% |

## Error reporting

If any check fails, show the relevant error output below the table. For StandardRB, list the top offenses by count. For Brakeman, list warnings by confidence level (High first).

## Notes

- Group 2 tests run separately so their output doesn't interleave with linting.
- Coverage is informational — report the numbers but don't fail on thresholds.
- Brakeman warnings marked as `Ignore` in `.brakeman.ignore` are expected — don't report those.
- If a tool is not installed, skip that check and report "skipped (not installed)" in the table.
