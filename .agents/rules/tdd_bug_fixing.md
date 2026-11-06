---
name: tdd-bug-fixing
description: Enforces test-driven reproduction, minimal fixes, and regression verification for bug remediations.
always_on: true
---

# TDD Bug Fixing Protocol

When remediating bugs or issues in this codebase:

1. **Test-First Reproduction**:
   - Write a unit test, regression test, or reproduction script demonstrating the failure before touching production code.
   - Verify the failure mode or edge-case vulnerability.

2. **Minimal Changes**:
   - Keep code diffs strictly scoped to fixing the identified bug.
   - Do NOT perform opportunistic refactoring, renaming, formatting churn, or dependency upgrades unless explicitly requested.

3. **Verification**:
   - Verify syntax, types, and test suite after each change.
   - If any previously working test or functionality regresses, stop immediately and resolve the regression.
