---
name: bs-probe
description: "Read-only root-cause investigation using throwaway probes and sibling-path checks."
---

# Root-Cause Probe Investigation (bs-probe)

Invoking `/bs-probe` authorizes inspecting `$TARGET_REPO` and running non-destructive probes in `.probes/` without modifying tracked files or committing. Shared worker conventions (**Target**, **Probes**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`. Used standalone or as the probing building block inside `/bs-plan`, `/bs-task`, `/bs-review`, and `/bs-loop`.

## Workflow

1. **Target & Invariants**: Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Identify Root Cause**: Read the code producing the symptom to name the underlying mechanism (**Follow-ups** in `{{BS_CONVENTIONS}}`), not just the input or caller that exposed it.
3. **Run Throwaway Probes**: Write and execute minimal reproduction/verification scripts under `$TARGET_REPO/.probes/` (or scratch dir), never in source/test dirs. Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Never modify tracked files.
4. **Probe Sibling Paths**: List other callers, input forms, contexts, or targets that pass through the same mechanism and probe each one to separate failing siblings from passing controls. When comparing against a `<BASE>` ref during review, verify whether another defect also exists on `<BASE>` in a temporary detached worktree (`git worktree add --detach .probes/base <BASE>`, then `git worktree remove --force .probes/base`).
5. **Cleanup & Report**: Delete `.probes/` before returning. When invoked standalone (or as `Probe Investigator`), reply with:
   - **Root Cause**: `<root-slug>` (`<mechanism>`, with `file:symbol`)
   - **Repro**: `<snippet or command>` → got `<actual>`, want `<expected>`
   - **Sibling Paths**: passing controls vs. failing siblings
   - **Verification Probes Run**: command + observed result per probe
