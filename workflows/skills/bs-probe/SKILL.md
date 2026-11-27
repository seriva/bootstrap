---
name: bs-probe
description: "Read-only root-cause investigation using throwaway probes and sibling-path checks."
---

# Root-Cause Probe Investigation (bs-probe)

Invoking `/bs-probe` authorizes inspecting `$TARGET_REPO` and running non-destructive probes in `.probes/`, without modifying tracked files or committing.
- Core conventions live in `{{BS_CONVENTIONS_CORE}}`.
- Used standalone in any tool, or as the probing building block inside `/bs-plan`, `/bs-task`, `/bs-review`, and `/bs-loop`.

## Workflow

1. **Target & Invariants**: resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (conventions-core).
2. **Identify Root Cause**:
   - Read the code producing the symptom and name the underlying mechanism (a function, rule, or data path), not just the input or caller that exposed it.
   - Slug the mechanism in kebab-case.
3. **Run Throwaway Probes**:
   - Write and run minimal reproduction or verification scripts.
   - Location, `.probes/` setup, and cleanup per **Probes** (conventions-core).
   - Never modify tracked files.
4. **Probe Sibling Paths**:
   - List the other callers, input forms, contexts, or targets that pass through the same mechanism.
   - Probe each one, to separate failing siblings from passing controls.
   - Comparing against a `<BASE>` ref during review: check whether another defect also exists on `<BASE>` in a temporary detached worktree outside the repo (`"{{BS_WORKTREE}}" add <BASE> base` prints its dir; `"{{BS_WORKTREE}}" remove <dir>` afterwards).
5. **Cleanup & Report**:
   - Invoked standalone → reply with:
     - **Root Cause**: `<root-slug>` (`<mechanism>`, with `file:symbol`)
     - **Repro**: `<snippet or command>` → got `<actual>`, want `<expected>`
     - **Sibling Paths**: passing controls vs. failing siblings
     - **Verification Probes Run**: command + observed result per probe
