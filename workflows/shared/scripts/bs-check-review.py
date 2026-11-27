#!/usr/bin/env python3
"""Mechanically check a Code Reviewer reply for /bs-loop: validate required sections,
count findings, extract (plan design: ...) and (gate change: ...) user-decision tags,
separate (pre-existing) auto-record items, and flag any Low or Out of Scope item that
mentions a file touched by the diff (or fix commits). Never modifies the working tree.
"""

import os
import re
import subprocess
import sys

USAGE = """\
Usage: bs-check-review.py --pass <N> --base <ref> [--fix-shas <csv|none>] <reply-file>
  --pass <N>           Review pass number (1 = Pass 1 rubric; >=2 = Pass 2+ verifier rubric)
  --base <ref>         Base ref diffed against (e.g. origin/main)
  --fix-shas <csv>     Optional comma-separated fix commit SHAs (or "none") for Pass 2+
  <reply-file>         Path to a file containing the reviewer's reply
Prints KEY=value lines (PASS, LGTM, counts, DECISION_COUNT, PRE_EXISTING_COUNT, SUSPECT_OWNED_COUNT, SUMMARY)
followed by any "DECISION <kind>: <item>", "PRE_EXISTING: <item>", and "SUSPECT_OWNED <section>: <item> (touches <files>)" lines.
Exit: 0 ok, 2 usage/unknown ref/missing file, 4 required reply section(s) missing.
On a non-zero exit, the last stderr line is "next: <action>" for the caller.
"""

NEXT_ON_FAILURE = {
    2: "fix the call (bs-check-review.py --pass <N> --base <ref> [--fix-shas <csv>] <reply-file>), then retry",
    4: "read the child thread with t3_thread_read; if required sections are still missing, re-dispatch once, then report PENDING_REVIEW",
}

HR_RE = re.compile(r"^(?:[-*_]\s*){3,}$")
NONE_RE = re.compile(
    r"^(?:none(?:\s+found)?|n/?a|nothing(?:\s+(?:unresolved|missed|found|to\s+report))?"
    r"|no\s+(?:findings|items|issues|unresolved|missed|low|high|medium|out[- ]of[- ]scope)"
    r"(?:\s+(?:items|findings|issues))?|\(none\)|—|-)\.?$",
    re.IGNORECASE,
)


def fail(code, msg=None):
    if msg:
        sys.stderr.write(msg + "\n")
    nxt = NEXT_ON_FAILURE.get(code)
    if nxt:
        sys.stderr.write(f"next: {nxt}\n")
    sys.exit(code)


def usage():
    sys.stderr.write(USAGE)
    fail(2)


def run_git(args, cwd=None):
    try:
        return subprocess.run(["git", *args], cwd=cwd, encoding="utf-8", errors="replace", capture_output=True)
    except OSError as exc:
        fail(2, f"bs-check-review: failed to run git: {exc}")


def strip_md_wrappers(text):
    return re.sub(r"^[*_`]+|[*_`]+$", "", text.strip()).strip()


def is_none(text):
    cleaned = strip_md_wrappers(text)
    return not cleaned or bool(NONE_RE.match(cleaned))


def parse_sections(text):
    """Parse `### <Heading>` sections outside fenced code blocks (case-insensitive, optional ':')."""
    sections = {}
    current = None
    in_fence = False
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            if current is not None:
                sections[current].append(raw_line)
            continue
        if not in_fence:
            m = re.match(r"^###\s+(.+?)\s*$", raw_line)
            if m:
                current = m.group(1).strip().rstrip(":").lower()
                sections.setdefault(current, [])
                continue
        if current is not None:
            sections[current].append(raw_line)
    return sections


def parse_items(sections, name):
    lines = sections.get(name.lower(), [])
    items = []
    cur = None
    base_indent = None
    in_code = False
    for raw in lines:
        s = raw.strip()
        if s.startswith("```"):
            in_code = not in_code
            if cur is not None:
                cur += " " + s
            continue
        if in_code:
            if cur is not None:
                cur += " " + s
            continue
        if not s or HR_RE.match(s):
            if cur is not None:
                items.append(cur.strip())
                cur = None
            continue
        # Stop before a trailing standalone LGTM line inside the last section.
        if strip_md_wrappers(s) == "LGTM":
            if cur is not None:
                items.append(cur.strip())
                cur = None
            continue
        indent = len(raw) - len(raw.lstrip())
        m = re.match(r"^(?:[-*+]|\d+[.)])\s+(.*)$", raw.lstrip())
        if m and (base_indent is None or indent <= base_indent + 1):
            if base_indent is None:
                base_indent = indent
            if cur is not None:
                items.append(cur.strip())
            cur = m.group(1).strip()
        elif cur is not None:
            cur += " " + s
        else:
            # Plain single-line entry without a bullet marker.
            if not is_none(s):
                items.append(s)
    if cur is not None:
        items.append(cur.strip())
    return [it for it in items if it and not is_none(it)]


def matched_files(item, candidates):
    hits = []
    for path in candidates:
        # Match full repo-relative path bounded by non-path chars, or basename followed by ':' (or '`:')
        full_pat = r"(?<![A-Za-z0-9_./-])" + re.escape(path) + r"(?![A-Za-z0-9_./-])"
        base = os.path.basename(path)
        base_pat = r"(?<![A-Za-z0-9_./-])" + re.escape(base) + r"`?:"
        if re.search(full_pat, item) or (len(base) >= 3 and re.search(base_pat, item)):
            hits.append(path)
    return hits


def has_decision_tag(item):
    low = item.lower()
    return "(plan design:" in low or "(gate change:" in low


def is_pre_existing(item):
    return "(pre-existing)" in item.lower() and not has_decision_tag(item)


def main():
    args = sys.argv[1:]
    pass_str = ""
    base = ""
    fix_shas = ""
    reply_file = ""

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--pass":
            if i + 1 >= len(args):
                usage()
            pass_str = args[i + 1]
            i += 2
        elif arg == "--base":
            if i + 1 >= len(args):
                usage()
            base = args[i + 1]
            i += 2
        elif arg == "--fix-shas":
            if i + 1 >= len(args):
                usage()
            fix_shas = args[i + 1]
            i += 2
        elif arg in ("-h", "--help"):
            usage()
        elif arg.startswith("-"):
            usage()
        else:
            if reply_file:
                usage()
            reply_file = arg
            i += 1

    if not re.fullmatch(r"[0-9]+", pass_str) or int(pass_str) == 0:
        usage()
    pass_num = int(pass_str)
    if not base or not reply_file:
        usage()
    if not os.path.isfile(reply_file):
        fail(2, f"bs-check-review: reply file not found: {reply_file}")

    if run_git(["rev-parse", "--is-inside-work-tree"]).returncode != 0:
        fail(2, "bs-check-review: not inside a git work tree")
    top_res = run_git(["rev-parse", "--show-toplevel"])
    if top_res.returncode != 0:
        fail(2, top_res.stderr.strip() or "bs-check-review: failed to locate git repo root")
    repo_root = top_res.stdout.strip()
    if run_git(["rev-parse", "-q", "--verify", f"{base}^{{tree}}"], cwd=repo_root).returncode != 0:
        fail(2, f"bs-check-review: unknown base ref: {base}")

    diff_res = run_git(["diff", "--name-only", f"{base}...HEAD"], cwd=repo_root)
    if diff_res.returncode != 0:
        diff_res = run_git(["diff", "--name-only", base, "HEAD"], cwd=repo_root)
    if diff_res.returncode != 0:
        fail(2, diff_res.stderr.strip() or f"bs-check-review: git diff failed for base: {base}")
    diff_files = sorted({line.strip() for line in diff_res.stdout.splitlines() if line.strip()})

    fix_files_set = set()
    if fix_shas and fix_shas != "none":
        for raw_sha in fix_shas.split(","):
            sha = "".join(raw_sha.split())
            if not sha:
                continue
            if run_git(["rev-parse", "-q", "--verify", f"{sha}^{{commit}}"], cwd=repo_root).returncode != 0:
                fail(2, f"bs-check-review: unknown fix commit: {sha}")
            show_res = run_git(["show", "--name-only", "--format=", sha], cwd=repo_root)
            if show_res.returncode != 0:
                fail(2, show_res.stderr.strip() or f"bs-check-review: git show failed for commit: {sha}")
            for line in show_res.stdout.splitlines():
                if line.strip():
                    fix_files_set.add(line.strip())
    fix_files = sorted(fix_files_set)

    with open(reply_file, "r", encoding="utf-8") as f:
        text = f.read()

    if pass_num == 1:
        required = ["High", "Medium", "Low", "Out of Scope", "Verification Probes Run"]
    else:
        required = ["Resolved", "Unresolved", "Verification Probes Run"]

    sections = parse_sections(text)
    missing = [h for h in required if h.lower() not in sections]
    if missing:
        fail(4, f"bs-check-review: missing required section(s): {', '.join(missing)}")

    non_empty_lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    lgtm = bool(non_empty_lines and strip_md_wrappers(non_empty_lines[-1]) == "LGTM")

    decisions = []
    pre_existing = []
    suspects = []

    def extract_decisions(items):
        for it in items:
            low = it.lower()
            if "(plan design:" in low:
                decisions.append(("plan-design", it))
            if "(gate change:" in low:
                decisions.append(("gate-change", it))

    if pass_num == 1:
        high = parse_items(sections, "High")
        medium = parse_items(sections, "Medium")
        low = parse_items(sections, "Low")
        oos = parse_items(sections, "Out of Scope")
        extract_decisions(high + medium)
        pre_existing.extend(it for it in (high + medium) if is_pre_existing(it))
        actionable = [it for it in (high + medium) if not is_pre_existing(it)]
        for sec_name, sec_items in (("Low", low), ("Out of Scope", oos)):
            for it in sec_items:
                hits = matched_files(it, diff_files)
                if hits:
                    suspects.append((sec_name, it, hits))
        if decisions or suspects:
            summary = "needs-triage"
        elif actionable:
            summary = "needs-fix"
        else:
            summary = "clean"
        print(f"PASS={pass_num}")
        print(f"LGTM={'true' if lgtm else 'false'}")
        print(f"HIGH={len(high)}")
        print(f"MEDIUM={len(medium)}")
        print(f"LOW={len(low)}")
        print(f"OUT_OF_SCOPE={len(oos)}")
        print(f"DECISION_COUNT={len(decisions)}")
        print(f"PRE_EXISTING_COUNT={len(pre_existing)}")
        print(f"SUSPECT_OWNED_COUNT={len(suspects)}")
        print(f"SUMMARY={summary}")
    else:
        unresolved = parse_items(sections, "Unresolved")
        missed = parse_items(sections, "Missed")
        oos = parse_items(sections, "Out of Scope")
        extract_decisions(unresolved + missed)
        pre_existing.extend(it for it in missed if is_pre_existing(it))
        actionable_missed = [it for it in missed if not is_pre_existing(it)]
        target_files = fix_files if (pass_num >= 3 and fix_files) else sorted(set(diff_files) | set(fix_files))
        for it in oos:
            hits = matched_files(it, target_files)
            if hits:
                suspects.append(("Out of Scope", it, hits))
        if unresolved:
            summary = "blocked"
        elif suspects:
            summary = "needs-triage"
        elif actionable_missed:
            summary = "missed"
        else:
            summary = "clean"
        print(f"PASS={pass_num}")
        print(f"LGTM={'true' if lgtm else 'false'}")
        print(f"UNRESOLVED={len(unresolved)}")
        print(f"MISSED={len(missed)}")
        print(f"OUT_OF_SCOPE={len(oos)}")
        print(f"DECISION_COUNT={len(decisions)}")
        print(f"PRE_EXISTING_COUNT={len(pre_existing)}")
        print(f"SUSPECT_OWNED_COUNT={len(suspects)}")
        print(f"SUMMARY={summary}")

    for kind, it in decisions:
        print(f"DECISION {kind}: {it}")
    for it in pre_existing:
        print(f"PRE_EXISTING: {it}")
    for sec_name, it, hits in suspects:
        print(f"SUSPECT_OWNED {sec_name}: {it} (touches {','.join(hits)})")


if __name__ == "__main__":
    main()
