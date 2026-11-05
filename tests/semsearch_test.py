"""Tests for docker/semsearch. Stdlib only; a stub HTTP server stands in for LM Studio.

Run: python3 -m unittest discover -s tests -p '*_test.py'
"""

import hashlib
import importlib.machinery
import importlib.util
import json
import math
import os
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "docker", "semsearch")


def load_module():
    loader = importlib.machinery.SourceFileLoader("semsearch", SCRIPT)
    spec = importlib.util.spec_from_loader("semsearch", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


ss = load_module()

# --------------------------------------------------------------------------- stub server

WORD_RE = re.compile(r"[a-z0-9]+")


def bag_vector(text, dims=768):
    """Deterministic embedding: hashed bag of words, so shared words mean higher cosine."""
    for prefix in ("search_query: ", "search_document: "):
        if text.startswith(prefix):
            text = text[len(prefix):]
    vec = [0.0] * dims
    for word in WORD_RE.findall(text.lower()):
        h = int(hashlib.md5(word.encode()).hexdigest(), 16)
        vec[h % 256] += 1.0  # land in the first 256 dims so Matryoshka truncation keeps signal
    return vec


class Stub:
    """Configurable fake of the LM Studio OpenAI-compatible API."""

    def __init__(self):
        self.requests = []  # (path, parsed body)
        self.embed_delay = 0.0
        self.chat_delay = 0.0
        self.chat_mode = "marker"  # marker | null | error200 | http500
        self.marker = "relevantmarker"
        self.lock = threading.Lock()
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                with stub.lock:
                    stub.requests.append((self.path, body))
                if self.path.endswith("/embeddings"):
                    time.sleep(stub.embed_delay)
                    data = [{"object": "embedding", "index": i, "embedding": bag_vector(t)}
                            for i, t in enumerate(body["input"])]
                    return self.reply(200, {"object": "list", "data": data})
                if self.path.endswith("/chat/completions"):
                    time.sleep(stub.chat_delay)
                    return stub.chat(self, body)
                self.reply(200, {"error": "Unexpected endpoint or method."})

            def reply(self, code, obj):
                raw = json.dumps(obj).encode()
                try:
                    self.send_response(code)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(raw)))
                    self.end_headers()
                    self.wfile.write(raw)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}/v1"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def chat(self, handler, body):
        if self.chat_mode == "http500":
            return handler.reply(500, {"error": "boom"})
        if self.chat_mode == "error200":
            return handler.reply(200, {"error": "Unexpected endpoint or method."})
        if self.chat_mode == "null":
            return handler.reply(200, {"choices": [{"message": {"content": "yes"}, "logprobs": None}]})
        doc = body["messages"][1]["content"]
        yes = 0.95 if self.marker in doc else 0.02
        top = [{"token": "yes", "logprob": math.log(yes)},
               {"token": "No", "logprob": math.log(1 - yes)}]
        return handler.reply(200, {"choices": [{"message": {"content": "yes"},
                                                "logprobs": {"content": [{"token": "yes", "top_logprobs": top}]}}]})

    def calls(self, suffix):
        with self.lock:
            return [b for p, b in self.requests if p.endswith(suffix)]

    def embedded_inputs(self):
        return [t for b in self.calls("/embeddings") for t in b["input"]]

    def reset(self):
        with self.lock:
            self.requests.clear()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


# --------------------------------------------------------------------------- fixtures

PY_SRC = '''import os


def alpha():
    return 1


@decorator
def beta(x):
    return x * 2


class Gamma:
    def method(self):
        return 3
'''

JS_SRC = '''const x = 1;

function shrinkSlice(a) {
  return a.slice(0, a.length / 2);
}

export const openFile = async (p) => {
  return fs.open(p);
};

class Widget {
  render() {}
}
'''

GO_SRC = '''package main

import "os"

func main() {
	os.Exit(0)
}

func (s *Server) Start() error {
	return nil
}

type Config struct {
	Port int
}
'''

SH_SRC = '''#!/usr/bin/env bash
set -e

install_claude() {
  echo claude
}

function install_agy {
  echo agy
}
'''


class RepoCase(unittest.TestCase):
    """Temp git repo + temp cache + stub server per test."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="semsearch-test-")
        self.repo = os.path.join(self.tmp, "repo")
        self.cache = os.path.join(self.tmp, "cache")
        os.makedirs(self.repo)
        subprocess.run(["git", "init", "-q", self.repo], check=True)
        self.stub = Stub()

    def tearDown(self):
        self.stub.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, rel, text):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
        return path

    def env(self, **extra):
        env = {k: v for k, v in os.environ.items() if not k.startswith("SEMSEARCH_")}
        env.update(SEMSEARCH_API_BASE=self.stub.base, SEMSEARCH_CACHE=self.cache,
                   SEMSEARCH_EMBED_MODEL="test-embed", SEMSEARCH_RERANK_MODEL="")
        env.update({k: v for k, v in extra.items() if v is not None})
        for k, v in extra.items():
            if v is None:
                env.pop(k, None)
        return env

    def run_cli(self, *args, cwd=None, timeout=30, **env):
        return subprocess.run([sys.executable, SCRIPT, *args], cwd=cwd or self.repo, env=self.env(**env),
                              capture_output=True, text=True, timeout=timeout)

    def db(self):
        files = [f for f in os.listdir(self.cache) if f.endswith(".db")]
        self.assertEqual(len(files), 1, files)
        return sqlite3.connect(os.path.join(self.cache, files[0]))

    def chunk_paths(self):
        with self.db() as con:
            return sorted({r[0] for r in con.execute("select path from chunks")})


# --------------------------------------------------------------------------- Task 1.1: index

class ChunkingTest(unittest.TestCase):
    def spans(self, path, src):
        return [(c[0], c[2]) for c in ss.chunk_file(path, src)]  # (start, symbol)

    def test_python_uses_ast_boundaries_including_decorators(self):
        spans = self.spans("a.py", PY_SRC)
        self.assertIn((4, "alpha"), spans)
        self.assertIn((8, "beta"), spans)  # decorator line, not the def line
        self.assertIn((13, "Gamma"), spans)

    def test_js_headers(self):
        symbols = [s for _, s in self.spans("a.js", JS_SRC)]
        self.assertIn("shrinkSlice", symbols)
        self.assertIn("openFile", symbols)
        self.assertIn("Widget", symbols)

    def test_go_headers(self):
        symbols = [s for _, s in self.spans("main.go", GO_SRC)]
        self.assertEqual(symbols[-3:], ["main", "Start", "Config"])

    def test_bash_headers(self):
        symbols = [s for _, s in self.spans("install.sh", SH_SRC)]
        self.assertIn("install_claude", symbols)
        self.assertIn("install_agy", symbols)

    def test_chunks_cover_lines_and_respect_max_size(self):
        src = "\n".join(f"line {i}" for i in range(1, 151)) + "\n"
        chunks = ss.chunk_file("notes.txt", src)
        self.assertTrue(all(c[1] - c[0] + 1 <= ss.MAX_CHUNK_LINES for c in chunks))
        self.assertEqual(chunks[0][0], 1)
        self.assertEqual(chunks[-1][1], 150)
        long_fn = "def big():\n" + "".join(f"    x{i} = {i}\n" for i in range(200))
        chunks = ss.chunk_file("big.py", long_fn)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(c[1] - c[0] + 1 <= ss.MAX_CHUNK_LINES for c in chunks))

    def test_python_syntax_error_falls_back_to_windows(self):
        chunks = ss.chunk_file("broken.py", "def (:\n" * 10)
        self.assertEqual(len(chunks), 1)

    def test_skips_binary_minified_and_lockfiles(self):
        self.assertFalse(ss.indexable("a.png", b"\x89PNG\x00\x00"))
        self.assertFalse(ss.indexable("app.min.js", b"var a=1;"))
        self.assertFalse(ss.indexable("package-lock.json", b"{}"))
        self.assertFalse(ss.indexable("bundle.js", b"x" * 5000))  # one giant line
        self.assertTrue(ss.indexable("a.py", PY_SRC.encode()))


class IndexTest(RepoCase):
    def seed(self):
        self.write("src/a.py", PY_SRC)
        self.write("web/app.js", JS_SRC)
        self.write("main.go", GO_SRC)

    def test_incremental_reindex(self):
        self.seed()
        r = self.run_cli("--index")
        self.assertEqual(r.returncode, 0, r.stderr)
        first = len(self.stub.embedded_inputs())
        self.assertGreater(first, 0)
        self.assertTrue(all(t.startswith("search_document: ") for t in self.stub.embedded_inputs()))

        self.stub.reset()
        self.run_cli("--index")
        self.assertEqual(self.stub.embedded_inputs(), [], "unchanged repo must not re-embed")

        self.stub.reset()
        time.sleep(0.01)
        self.write("main.go", GO_SRC + "\nfunc extra() {}\n")
        self.run_cli("--index")
        inputs = self.stub.embedded_inputs()
        self.assertTrue(inputs)
        self.assertTrue(all(":: " in t and t.split(" :: ")[0].endswith("main.go") for t in inputs), inputs)

        os.remove(os.path.join(self.repo, "web/app.js"))
        self.run_cli("--index")
        self.assertEqual(self.chunk_paths(), ["main.go", "src/a.py"])
        with self.db() as con:
            fts = {r[0] for r in con.execute("select path from chunks_fts")}
        self.assertEqual(fts, {"main.go", "src/a.py"})

    def test_mtime_only_change_does_not_reembed(self):
        self.seed()
        self.run_cli("--index")
        self.stub.reset()
        os.utime(os.path.join(self.repo, "main.go"), (time.time() + 100, time.time() + 100))
        self.run_cli("--index")
        self.assertEqual(self.stub.embedded_inputs(), [])

    def test_paths_are_repo_relative_from_subdirectory(self):
        self.seed()
        r = self.run_cli("--index", cwd=os.path.join(self.repo, "src"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.chunk_paths(), ["main.go", "src/a.py", "web/app.js"])

    def test_tracked_untracked_and_ignored(self):
        self.write(".gitignore", "secret/\n")
        self.write("tracked.py", PY_SRC)
        subprocess.run(["git", "-C", self.repo, "add", "tracked.py", ".gitignore"], check=True)
        subprocess.run(["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "-c",
                        "core.hooksPath=/dev/null", "commit", "-qm", "init"], check=True)
        self.write("new_untracked.py", PY_SRC)
        self.write("secret/hidden.py", PY_SRC)
        self.run_cli("--index")
        paths = self.chunk_paths()
        self.assertIn("tracked.py", paths)
        self.assertIn("new_untracked.py", paths)
        self.assertNotIn("secret/hidden.py", paths)

    def test_budget_stops_early_commits_and_resumes(self):
        for i in range(80):  # 80 files -> > 2 batches of 32 chunks
            self.write(f"pkg/f{i}.go", f"package pkg\n\nfunc F{i}() int {{\n\treturn {i}\n}}\n")
        self.stub.embed_delay = 0.2
        r = self.run_cli("needle", SEMSEARCH_INDEX_BUDGET="0.1")
        self.assertEqual(r.returncode, 0, r.stderr)
        m = re.search(r"indexed (\d+)/(\d+) chunks", r.stderr)
        self.assertTrue(m, r.stderr)
        done, total = int(m.group(1)), int(m.group(2))
        self.assertTrue(0 < done < total, (done, total))
        with self.db() as con:
            stored = con.execute("select count(*) from chunks where vec is not null").fetchone()[0]
        self.assertEqual(stored, done)

        self.stub.reset()
        self.stub.embed_delay = 0
        r = self.run_cli("--index", SEMSEARCH_INDEX_BUDGET="0.1")  # --index ignores the budget
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.stub.embedded_inputs()), total - done, "resume must skip committed batches")
        with self.db() as con:
            self.assertEqual(con.execute("select count(*) from chunks where vec is null").fetchone()[0], 0)

    def test_vectors_are_truncated_and_normalised(self):
        self.seed()
        self.run_cli("--index")
        with self.db() as con:
            blob = con.execute("select vec from chunks where vec is not null limit 1").fetchone()[0]
        vec = ss.unpack(blob)
        self.assertEqual(len(vec), ss.DIMS)
        self.assertAlmostEqual(math.sqrt(sum(v * v for v in vec)), 1.0, places=4)


# --------------------------------------------------------------------------- Task 1.2: recall + output

HEADER_RE = re.compile(r"^\S+:\d+-\d+ ")


class SearchTest(RepoCase):
    def seed(self):
        self.write("config/loader.go", "package config\n\nfunc LoadSettingsFile(path string) error {\n"
                                       "\t// parse yaml configuration settings file from disk\n\treturn nil\n}\n")
        self.write("net/socket.go", "package net\n\nfunc DialTimeout(addr string) error {\n"
                                    "\t// open tcp connection with deadline\n\treturn nil\n}\n")
        self.write("ui/zz.js", "function zzqUniqueName() {\n  return 42;\n}\n")
        for i in range(30):
            self.write(f"filler/f{i}.py", f"def filler_{i}():\n    return 'apple banana cherry {i}'\n")

    def headers(self, out):
        return [line for line in out.splitlines() if HEADER_RE.match(line)]

    def test_semantic_query_ranks_matching_chunk_first(self):
        self.seed()
        r = self.run_cli("parse", "yaml", "configuration", "settings", "--fast")
        self.assertEqual(r.returncode, 0, r.stderr)
        heads = self.headers(r.stdout)
        self.assertTrue(heads, r.stdout)
        self.assertTrue(heads[0].startswith("config/loader.go:3-6 "), heads)
        queries = [b["input"] for b in self.stub.calls("/embeddings") if any("search_query" in t for t in b["input"])]
        self.assertEqual(queries, [["search_query: parse yaml configuration settings"]])

    def test_exact_symbol_found_by_keyword_search_without_endpoint(self):
        self.seed()
        r = self.run_cli("zzqUniqueName", SEMSEARCH_API_BASE=None)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("use rg", r.stderr)
        self.assertTrue(self.headers(r.stdout)[0].startswith("ui/zz.js:1-3 "), r.stdout)

    def test_camel_case_symbol_matches_split_words(self):
        self.seed()
        r = self.run_cli("unique", "name", SEMSEARCH_API_BASE=None)
        self.assertTrue(self.headers(r.stdout)[0].startswith("ui/zz.js:1-3 "), r.stdout)

    def test_operator_heavy_queries_do_not_crash(self):
        self.seed()
        for q in ['api.go', '--fast', 'NOT', 'fix: AND', 'foo-bar: "baz" (qux)', '!!!']:
            r = self.run_cli("--", q, "--fast") if q.startswith("-") else self.run_cli(q, "--fast")
            self.assertEqual(r.returncode, 0, (q, r.stderr))
            self.assertNotIn("Traceback", r.stderr, q)

    def test_fts_query_quotes_every_token(self):
        self.assertEqual(ss.fts_query('foo-bar: "baz" (qux)'), '"foo" OR "bar" OR "baz" OR "qux"')
        self.assertEqual(ss.fts_query("!!!"), "")

    def test_rrf_dedupes_and_caps_candidates(self):
        dense = list(range(20))
        keyword = [5, 3, 100, 101, 102, 103, 104, 105, 106, 107]
        fused = ss.rrf_fuse(dense, keyword)
        ids = [i for i, _ in fused]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertLessEqual(len(ids), ss.MAX_CANDIDATES)
        self.assertEqual(ids[:2], [3, 5])  # in both lists -> fused ahead

    def test_k_and_output_format(self):
        self.seed()
        r = self.run_cli("apple", "banana", "-k", "3", "--fast")
        heads = self.headers(r.stdout)
        self.assertEqual(len(heads), 3, r.stdout)
        for line in r.stdout.splitlines():
            self.assertTrue(line == "" or HEADER_RE.match(line) or line.startswith("    "), line)

    def test_json_output(self):
        self.seed()
        r = self.run_cli("open tcp connection", "--json", "--fast")
        data = json.loads(r.stdout)
        top = data["results"][0]
        self.assertEqual((top["path"], top["start"], top["end"]), ("net/socket.go", 3, 6))
        self.assertIn("DialTimeout", top["text"])
        self.assertEqual(data["mode"], "hybrid")

    def test_no_matches(self):
        self.write("a.txt", "hello\n")
        r = self.run_cli("zzzz", SEMSEARCH_API_BASE=None)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.strip(), "no matches")


# --------------------------------------------------------------------------- Task 1.3: rerank

class RerankTest(RepoCase):
    QUERY = ("token", "parser", "stream")

    def seed(self):
        for i in range(6):  # decoys: strong word overlap with the query, no marker
            self.write(f"decoy/d{i}.py", f"def decoy_{i}():\n    # token parser stream token parser stream {i}\n    return {i}\n")
        long_body = "".join(f"    step_{n} = {n}\n" for n in range(40))
        self.write("real/target.py", "def target():\n    # token relevantmarker\n" + long_body)

    def ranked_paths(self, *extra, **env):
        r = self.run_cli(*self.QUERY, "--json", "-k", "10", *extra, SEMSEARCH_RERANK_MODEL="qwen3-reranker-0.6b", **env)
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        return [x["path"] for x in data["results"]], data["mode"]

    def test_rerank_reorders_and_sends_verified_request_shape(self):
        self.seed()
        fast, mode = self.ranked_paths("--fast")
        self.assertEqual(mode, "hybrid")
        self.assertNotEqual(fast[0], "real/target.py")
        self.assertEqual(self.stub.calls("/chat/completions"), [], "--fast must not rerank")

        self.stub.reset()
        reranked, mode = self.ranked_paths()
        self.assertEqual(mode, "rerank")
        self.assertEqual(reranked[0], "real/target.py")

        calls = self.stub.calls("/chat/completions")
        self.assertTrue(0 < len(calls) <= ss.RERANK_TOP)
        body = calls[0]
        self.assertEqual(body["model"], "qwen3-reranker-0.6b")
        self.assertEqual((body["temperature"], body["max_tokens"], body["logprobs"], body["top_logprobs"]), (0, 2, True, 10))
        roles = [m["role"] for m in body["messages"]]
        self.assertEqual(roles, ["system", "user", "assistant"])
        self.assertEqual(body["messages"][2]["content"], "<think>\n\n</think>\n\n")
        user = body["messages"][1]["content"]
        self.assertIn("<Query>: token parser stream", user)
        for b in calls:
            doc = b["messages"][1]["content"].split("<Document>: ", 1)[1]
            self.assertLessEqual(len(doc.split("\n")), ss.RERANK_LINES + 1)  # +1: path header line

    def test_failures_fall_back_to_rrf_order(self):
        self.seed()
        fast, _ = self.ranked_paths("--fast")
        for mode in ("null", "error200", "http500"):
            self.stub.chat_mode = mode
            paths, got_mode = self.ranked_paths()
            self.assertEqual(got_mode, "hybrid", mode)
            self.assertEqual(paths, fast, mode)

    def test_deadline_falls_back_to_rrf(self):
        self.seed()
        fast, _ = self.ranked_paths("--fast")
        self.stub.chat_delay = 0.7  # 7 pairs x 0.7 s > 4 s deadline
        t = time.monotonic()
        paths, mode = self.ranked_paths()
        self.assertEqual(mode, "hybrid")
        self.assertEqual(paths, fast)
        self.assertLess(time.monotonic() - t, ss.RERANK_DEADLINE + 2.5)

    def test_no_rerank_model_means_no_rerank(self):
        self.seed()
        r = self.run_cli(*self.QUERY, "--json")
        self.assertEqual(json.loads(r.stdout)["mode"], "hybrid")
        self.assertEqual(self.stub.calls("/chat/completions"), [])


# --------------------------------------------------------------------------- Task 1.4: fail-open

def closed_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class HangingServer:
    """Accepts connections and never answers."""

    def __init__(self):
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen()
        self.conns = []
        self.base = f"http://127.0.0.1:{self.sock.getsockname()[1]}/v1"
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while True:
            try:
                self.conns.append(self.sock.accept()[0])
            except OSError:
                return

    def close(self):
        for c in self.conns:
            c.close()
        self.sock.close()


class FailOpenTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("svc/handler.go", "package svc\n\nfunc HandleRequest() {\n\t// serve http request\n}\n")
        r = self.run_cli("--index")  # warm index so timings measure the query path only
        self.assertEqual(r.returncode, 0, r.stderr)
        self.stub.reset()

    def test_unset_base_exits_zero_with_hint(self):
        r = self.run_cli("serve request", SEMSEARCH_API_BASE=None)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stderr.strip(), ss.UNAVAILABLE)
        self.assertIn("svc/handler.go", r.stdout)  # keyword results still served

    def test_closed_port_fails_open_fast(self):
        t = time.monotonic()
        r = self.run_cli("serve request", SEMSEARCH_API_BASE=f"http://127.0.0.1:{closed_port()}/v1")
        elapsed = time.monotonic() - t
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("use rg", r.stderr)
        self.assertLess(elapsed, 0.5)

    def test_slow_but_working_server_is_not_timed_out_by_preflight(self):
        self.stub.embed_delay = 1.5
        r = self.run_cli("serve request", "--json", "--fast")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("use rg", r.stderr)
        self.assertEqual(json.loads(r.stdout)["mode"], "hybrid")

    def test_hanging_server_degrades_within_request_timeout(self):
        hang = HangingServer()
        self.addCleanup(hang.close)
        t = time.monotonic()
        r = self.run_cli("serve request", "--json", "--fast", SEMSEARCH_API_BASE=hang.base)
        elapsed = time.monotonic() - t
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("use rg", r.stderr)
        self.assertEqual(json.loads(r.stdout)["mode"], "keyword")
        self.assertLess(elapsed, 4.5)  # plan: query embed timeout 3 s (literal, so a raised constant fails here)

    def test_not_a_git_repo_exits_two(self):
        plain = os.path.join(self.tmp, "plain")
        os.makedirs(plain)
        r = self.run_cli("anything", cwd=plain)
        self.assertEqual(r.returncode, 2)
        self.assertIn("not a git repository", r.stderr)

    def test_corrupt_index_is_rebuilt(self):
        db_file = [f for f in os.listdir(self.cache) if f.endswith(".db")][0]
        for suffix in ("-wal", "-shm"):
            try:
                os.remove(os.path.join(self.cache, db_file + suffix))
            except FileNotFoundError:
                pass
        with open(os.path.join(self.cache, db_file), "wb") as f:
            f.write(b"this is not a sqlite database" * 100)
        r = self.run_cli("serve request", "--fast")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("Traceback", r.stderr)
        self.assertIn("svc/handler.go", r.stdout)

    def test_model_change_rebuilds_index(self):
        with self.db() as con:
            total = con.execute("select count(*) from chunks").fetchone()[0]
        r = self.run_cli("--index", SEMSEARCH_EMBED_MODEL="other-model")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.stub.embedded_inputs()), total)
        self.assertTrue(all(b["model"] == "other-model" for b in self.stub.calls("/embeddings")))
        with self.db() as con:
            self.assertEqual(dict(con.execute("select key, value from meta"))["model"], "other-model")

    def test_usage_error_exits_two(self):
        r = self.run_cli()
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
