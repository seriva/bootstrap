#!/usr/bin/env python3
"""Review-run state of a branch's PR for the bs-* skills, from one `gh pr view` call, plus the
writers of the Gate line (`set`, `ci`) and persistent triage/fix metadata (`record`, `get`)
stored in an HTML comment block in the PR body. Never writes the working tree.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

PLACEHOLDER = "*Automated AI review & fix cycle in progress...*"
FIX_SUBJECT_SUFFIX = ": address review feedback"
GATE_MARKER = "**Gate:**"
STATE_START = "<!-- bs-review-state:v1"
STATE_END = "-->"

USAGE = """\
Usage: bs-review-state.py <branch>
       bs-review-state.py get <branch>
       bs-review-state.py record <branch> [--fix-used] [--fix-sha <sha>]... [--pass <label>]... [--defer <item>]... [--keep-gate <item>]...
       bs-review-state.py set <branch> <GATE> <detail> [<report-file>]
       bs-review-state.py ci <branch> <passes-run>
Prints "<state> <base-branch>", or "none" when the branch has no PR. <state> is the first match:
  merged | closed        the PR is merged or closed (gh may return one for a reused branch name)
  ready                  open and not a draft
  in-review | fix-used   draft whose Review Status is still the placeholder; fix-used once recorded
                         via `record --fix-used`/`--fix-sha` or a commit subject ends in
                         ": address review feedback" (the one Fix Turn)
  gated:<GATE>           draft whose first Gate line starts with PASSED, BLOCKED_BY_DEFECTS,
                         or BLOCKED_BY_CI (later Gate lines, e.g. quoted in the report, are ignored)
  draft                  any other draft
get reads the persistent triage/fix state block from the PR body (defaults if absent) and prints:
  FIX_USED=true|false, FIX_SHAS=<csv|none>, PASSES=<list|none>, DEFERRED <item|none>, KEPT_GATE <item|none>.
record merges the given flags into that HTML comment block in the PR body (preserving prior entries
  and all visible PR text; --fix-sha implies --fix-used) and prints the updated state like `get`.
set writes "**Gate:** <GATE> (<detail>)", GATE one of PASSED, BLOCKED_BY_DEFECTS, BLOCKED_BY_CI:
  while the body has the placeholder, the line holding it becomes "## Review Status", the
  Gate line, and <report-file>'s contents (required then; e.g. Findings and probe details);
  afterwards it replaces the first Gate line (no <report-file>). Then prints the new state.
ci waits for the PR's CI (bs-pr-ci), rewrites the Gate line from the result, marks the PR ready
  when it is PASSED, and prints "<REVIEW_STATUS> <ci-result>" and a "next: <action>" line:
    pass, skipped, none-configured   PASSED (skipped: CI did not test this PR)
    fail <checks>, conflict          BLOCKED_BY_CI (the PR stays a draft)
    gh failure while waiting         BLOCKED_BY_CI error
Exit: 0 ok, 2 usage, 3 gh failed, 4 malformed PR body (missing placeholder/Gate line or corrupted state block).
On a non-zero exit, the last stderr line is "next: <action>" for the caller.
"""

NEXT_ON_FAILURE = {
    2: "fix the call as the error or usage above says, then retry",
    3: "gh failed (error above): retry once; if it fails again, stop and report the error",
    4: "stop and report: the PR body is missing its review marker or has a corrupted bs-review-state block",
}

STATE_BLOCK_RE = re.compile(
    re.escape(STATE_START) + r"\r?\n(.*?)\r?\n" + re.escape(STATE_END),
    re.DOTALL,
)
GATE_LINE_RE = re.compile(r"\*\*Gate(?::\*\*|\*\*:)\s*([A-Z_]+)")
GATE_MARKER_RE = re.compile(r"\*\*Gate(?::\*\*|\*\*:)")
VALID_GATES = {"PASSED", "BLOCKED_BY_DEFECTS", "BLOCKED_BY_CI"}


def fail(code, msg=None):
    if msg:
        sys.stderr.write(msg.rstrip("\n") + "\n")
    nxt = NEXT_ON_FAILURE.get(code)
    if nxt:
        sys.stderr.write(f"next: {nxt}\n")
    sys.exit(code)


def usage():
    sys.stderr.write(USAGE)
    fail(2)


def default_state():
    return {
        "fix_used": False,
        "fix_shas": [],
        "passes": [],
        "deferred": [],
        "gate_changes_kept": [],
    }


def load_state(body):
    matches = list(STATE_BLOCK_RE.finditer(body))
    if not matches:
        if STATE_START in body:
            fail(4, "bs-review-state: corrupted or unclosed state block in PR body")
        return default_state(), None
    m = matches[-1]
    raw = m.group(1).strip()
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("state must be a JSON object")
    except Exception as exc:
        fail(4, f"bs-review-state: corrupted state block in PR body: {exc}")
    st = default_state()
    fix_used = data.get("fix_used", False)
    if not isinstance(fix_used, bool):
        fail(4, "bs-review-state: corrupted 'fix_used' field in state block")
    st["fix_used"] = fix_used
    for key in ("fix_shas", "passes", "deferred", "gate_changes_kept"):
        val = data.get(key, [])
        if not isinstance(val, list) or not all(isinstance(x, str) for x in val):
            fail(4, f"bs-review-state: corrupted '{key}' field in state block")
        st[key] = list(val)
    return st, m


def clean_line(text):
    return re.sub(r"[\r\n]+", " ", text).strip()


def append_unique(lst, item):
    item = clean_line(item)
    if item and item not in lst:
        lst.append(item)


def format_state(st):
    lines = [
        f"FIX_USED={'true' if st['fix_used'] else 'false'}",
        f"FIX_SHAS={','.join(st['fix_shas']) if st['fix_shas'] else 'none'}",
        f"PASSES={', '.join(st['passes']) if st['passes'] else 'none'}",
    ]
    if st["deferred"]:
        for item in st["deferred"]:
            lines.append(f"DEFERRED {item}")
    else:
        lines.append("DEFERRED none")
    if st["gate_changes_kept"]:
        for item in st["gate_changes_kept"]:
            lines.append(f"KEPT_GATE {item}")
    else:
        lines.append("KEPT_GATE none")
    return "\n".join(lines)


def run_gh(args):
    try:
        return subprocess.run(["gh", *args], encoding="utf-8", errors="replace", capture_output=True)
    except OSError as exc:
        fail(3, f"bs-review-state: failed to run gh: {exc}")


def edit_pr_body(branch, new_body):
    fd, tmp_path = tempfile.mkstemp(prefix="bs-review-state.body.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_body)
        res = run_gh(["pr", "edit", branch, "--body-file", tmp_path])
        if res.returncode != 0:
            fail(3, res.stderr)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def fetch_body(branch):
    res = run_gh(["pr", "view", branch, "--json", "body"])
    if res.returncode != 0:
        fail(3, res.stderr)
    try:
        data = json.loads(res.stdout)
    except Exception as exc:
        fail(3, f"bs-review-state: failed to parse gh output: {exc}")
    return data.get("body") or ""


def read_state(branch):
    res = run_gh(["pr", "view", branch, "--json", "state,isDraft,baseRefName,body,commits"])
    if res.returncode != 0:
        if "no pull requests found" in res.stderr:
            return "none"
        fail(3, res.stderr)
    try:
        data = json.loads(res.stdout)
    except Exception as exc:
        fail(3, f"bs-review-state: failed to parse gh output: {exc}")

    state = data.get("state", "")
    draft = bool(data.get("isDraft", False))
    base = data.get("baseRefName", "")
    body = data.get("body") or ""
    commits = data.get("commits") or []
    fixes = sum(
        1 for c in commits
        if isinstance(c, dict) and str(c.get("messageHeadline", "")).endswith(FIX_SUBJECT_SUFFIX)
    )

    # Only the first Gate line counts: it is the one `set` writes and rewrites, ahead of the report,
    # whose Findings or probe output may quote other Gate lines.
    gate = ""
    for ln in body.splitlines():
        m = GATE_LINE_RE.search(ln)
        if m:
            gate = m.group(1)
            break

    if state == "MERGED":
        s = "merged"
    elif state == "CLOSED":
        s = "closed"
    elif not draft:
        s = "ready"
    elif PLACEHOLDER in body:
        st, _ = load_state(body)
        s = "fix-used" if (st["fix_used"] or fixes > 0) else "in-review"
    else:
        s = f"gated:{gate}" if gate in VALID_GATES else "draft"
    return f"{s} {base}"


def set_gate(branch, gate, detail, report=""):
    if gate not in VALID_GATES:
        usage()
    if report and not os.path.isfile(report):
        fail(2, f"bs-review-state: no such report file: {report}")

    body = fetch_body(branch)
    line = f"{GATE_MARKER} {gate} ({detail})"
    lines = body.splitlines()

    if PLACEHOLDER in body:
        if not report:
            fail(2, "bs-review-state: set needs a <report-file> to replace the placeholder")
        with open(report, "r", encoding="utf-8") as f:
            report_lines = f.read().splitlines()
        out_lines = []
        done = False
        seen_heading = False
        for ln in lines:
            if not done and PLACEHOLDER in ln:
                if not seen_heading or re.match(r"^##\s+Review Status", ln):
                    out_lines.append("## Review Status")
                    out_lines.append("")
                out_lines.append(line)
                out_lines.append("")
                out_lines.extend(report_lines)
                done = True
                continue
            # seen_heading: the placeholder sits in a "## Review Status" section; any other heading ends it.
            if re.match(r"^#+\s", ln):
                seen_heading = bool(re.match(r"^##\s+Review Status\s*$", ln))
            out_lines.append(ln)
        new_body = "\n".join(out_lines) + "\n"
    elif GATE_MARKER_RE.search(body):
        if report:
            fail(2, "bs-review-state: <report-file> only replaces the placeholder")
        out_lines = []
        done = False
        for ln in lines:
            if not done and GATE_MARKER_RE.search(ln):
                out_lines.append(line)
                done = True
                continue
            out_lines.append(ln)
        new_body = "\n".join(out_lines) + "\n"
    else:
        fail(4, f"bs-review-state: PR body for {branch} has neither the review placeholder nor a Gate line")

    edit_pr_body(branch, new_body)


def cmd_record(branch, opts):
    body = fetch_body(branch)
    st, match = load_state(body)

    i = 0
    changed = False
    while i < len(opts):
        flag = opts[i]
        if flag == "--fix-used":
            st["fix_used"] = True
            changed = True
            i += 1
        elif flag in ("--fix-sha", "--pass", "--defer", "--keep-gate"):
            if i + 1 >= len(opts) or not opts[i + 1].strip():
                fail(2, f"bs-review-state: {flag} requires a non-empty value")
            val = opts[i + 1]
            if flag == "--fix-sha":
                st["fix_used"] = True
                append_unique(st["fix_shas"], val)
            elif flag == "--pass":
                append_unique(st["passes"], val)
            elif flag == "--defer":
                append_unique(st["deferred"], val)
            elif flag == "--keep-gate":
                append_unique(st["gate_changes_kept"], val)
            changed = True
            i += 2
        else:
            fail(2, f"bs-review-state: unknown record option: {flag}")
    if not changed:
        fail(2, "bs-review-state: record requires at least one option")

    # Escape '-->' inside JSON strings so a repro containing '-->' cannot close the HTML comment.
    payload = json.dumps(st, separators=(",", ":"), ensure_ascii=False).replace("-->", "--\\u003e")
    block = f"{STATE_START}\n{payload}\n{STATE_END}"
    if match is not None:
        new_body = body[:match.start()] + block + body[match.end():]
        if not new_body.endswith("\n"):
            new_body += "\n"
    else:
        trimmed = body.rstrip("\r\n")
        new_body = f"{trimmed}\n\n{block}\n" if trimmed else f"{block}\n"

    edit_pr_body(branch, new_body)
    print(format_state(st))


def cmd_ci(branch, passes):
    current = read_state(branch)
    if current == "none":
        fail(3, f"bs-review-state: no PR for {branch}")
    base = current.split(" ", 1)[1]

    pr_ci_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bs-pr-ci")
    try:
        res = subprocess.run([pr_ci_script, branch], encoding="utf-8", errors="replace", capture_output=True)
    except OSError as exc:
        rc = 127
        result = ""
        ci_msg_lines = [f"bs-review-state: failed to run bs-pr-ci: {exc}"]
        ci_msg = ci_msg_lines[0]
    else:
        rc = res.returncode
        result = res.stdout.strip()
        ci_msg_lines = [ln for ln in res.stderr.splitlines() if not ln.startswith("next: ")]
        ci_msg = "\n".join(ci_msg_lines)

    if rc == 2:
        fail(2, ci_msg)

    if rc == 0 and result == "pass":
        status, ci, detail = "PASSED", "pass", f"{passes}; CI: pass"
    elif rc == 0 and result == "skipped":
        status, ci, detail = "PASSED", "skipped", f"{passes}; CI: skipped, no check ran"
    elif rc == 0 and result == "none-configured":
        status, ci, detail = "PASSED", "none-configured", f"{passes}; CI: none configured"
    elif rc == 0 and result.startswith("fail "):
        status, ci, detail = "BLOCKED_BY_CI", result, f"{passes}; failing: {result[len('fail '):]}"
    elif rc == 0 and result == "conflict":
        status, ci, detail = "BLOCKED_BY_CI", "conflict", f"{passes}; merge conflict with {base}"
    else:
        if ci_msg:
            sys.stderr.write(ci_msg + "\n")
        first_err = ci_msg_lines[0] if ci_msg_lines else ""
        status, ci, detail = "BLOCKED_BY_CI", "error", f"{passes}; CI wait failed: {first_err}"

    set_gate(branch, status, detail)
    if status == "PASSED":
        ready_res = run_gh(["pr", "ready", branch])
        if ready_res.returncode != 0:
            fail(3, ready_res.stderr)

    print(f"{status} {ci}")
    if ci in ("pass", "none-configured"):
        print("next: return the PR URL with REVIEW_STATUS=PASSED (the PR is marked ready)")
    elif ci == "skipped":
        print(
            "next: tell the user CI did not test this PR (every check was skipped: a workflow `if:` "
            "excludes the branch; never say CI passed), then return the PR URL with REVIEW_STATUS=PASSED "
            "(the PR is marked ready)"
        )
    else:
        print(
            f"next: leave the PR in Draft, alert the user ({detail}), "
            "and return the PR URL with REVIEW_STATUS=BLOCKED_BY_CI"
        )


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else ""

    if cmd == "get":
        if len(args) != 2 or not args[1]:
            usage()
        body = fetch_body(args[1])
        st, _ = load_state(body)
        print(format_state(st))
    elif cmd == "record":
        if len(args) < 3 or not args[1]:
            usage()
        cmd_record(args[1], args[2:])
    elif cmd == "set":
        if len(args) not in (4, 5) or not args[1] or not args[3]:
            usage()
        report = args[4] if len(args) == 5 else ""
        set_gate(args[1], args[2], args[3], report)
        print(read_state(args[1]))
    elif cmd == "ci":
        if len(args) != 3 or not args[1] or not args[2]:
            usage()
        cmd_ci(args[1], args[2])
    else:
        if len(args) != 1 or not args[0] or args[0] in ("-h", "--help"):
            usage()
        print(read_state(args[0]))


if __name__ == "__main__":
    main()
