---
name: bs-probe
description: "Read-only root-cause investigation using throwaway probes and sibling-path checks."
---

# Root-Cause Probe Investigation (bs-probe)

Invoking `/bs-probe` authorizes inspecting `$TARGET_REPO` and running non-destructive probes in `.probes/` without modifying tracked files or committing. Shared worker conventions (**Target**, **Probes**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`. Used standalone or as the probing building block inside `/bs-plan`, `/bs-task`, `/bs-review`, and `/bs-loop`.

## Workflow

1. **Target & Invariants**: Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Identify Root Cause**: Read the code producing the symptom to name the underlying mechanism (a function, rule, or data path; slug it in kebab-case), not just the input or caller that exposed it.
3. **Run Throwaway Probes**: Write and execute minimal reproduction/verification scripts in the host's scratch dir, or under `$TARGET_REPO/.probes/` when they need repo-relative imports, never in source/test dirs. Before writing the first probe in `.probes/`, exclude it locally: `e="$(git rev-parse --git-path info/exclude)"; grep -qxs '.probes/' "$e" || echo '.probes/' >> "$e"`. Never modify tracked files.
4. **Probe Sibling Paths**: List other callers, input forms, contexts, or targets that pass through the same mechanism and probe each one to separate failing siblings from passing controls. When comparing against a `<BASE>` ref during review, verify whether another defect also exists on `<BASE>` in a temporary detached worktree outside the repo (`"{{BS_WORKTREE}}" add <BASE> base` prints its dir; `"{{BS_WORKTREE}}" remove <dir>` afterwards).
5. **Cleanup & Report**: Delete `.probes/` before any format/lint run or commit (tree-walking linters ignore git's exclude file) and before returning. When invoked standalone (or as `Probe Investigator`), reply with:
   - **Root Cause**: `<root-slug>` (`<mechanism>`, with `file:symbol`)
   - **Repro**: `<snippet or command>` → got `<actual>`, want `<expected>`
   - **Sibling Paths**: passing controls vs. failing siblings
   - **Verification Probes Run**: command + observed result per probe
