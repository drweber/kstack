# kstack eval harness

This tier measures whether Claude, given a kstack skill and a cluster with a
planted failure, produces the correct diagnosis. It sits alongside
`tests/unit/`, `tests/integration/`, and `tests/e2e/`, but is run by its own
driver (`scripts/test-evals.sh`) because its semantics differ: runs are
probabilistic, each hits the Anthropic API, and artifacts are captured for
after-the-fact inspection.

## How it works

Per scenario, the runner:

1. Creates a namespace labeled `kstack-eval/scenario=<id>`.
2. Applies `fixture.yaml` into that namespace.
3. Runs `wait.sh` (if present) until the planted state is observable.
4. Invokes `claude -p` with `--output-format stream-json`, N times.
5. Scores each run using a **hybrid** strategy:
   - **Keyword pre-flight**: `rubric.must_mention` / `must_not_mention`
     substrings. A miss short-circuits the run — no API spend on the
     judge.
   - **Structured**: if `expected.structured` is defined and the skill
     emits JSON, `required_findings` / `forbidden_findings` are matched
     against the skill's JSON output.
   - **LLM-as-judge**: if `rubric.judge_criteria` is defined, a second
     `claude -p` call grades the response against the rubric and returns
     `{pass, reason, violations}`.
6. Scenario passes iff `passes >= pass_threshold`.
7. Deletes the namespace (async) and moves on.

All artifacts land under `tests/evals/artifacts/<id>/` (gitignored). Per
run you'll find `run-N.jsonl` (stream-json transcript), `run-N.text`
(final assistant message), `run-N.stderr` (claude's stderr, captured
even on success — empty when there's nothing to report), and when the
rubric uses `judge_criteria`, `run-N.judge.json` plus
`run-N.judge.stderr`.

## Authoring a scenario

Each scenario lives in `tests/evals/scenarios/<id>/` with four files:

- **`scenario.yaml`** — metadata and runtime knobs. Minimal shape:

  ```yaml
  id: my-scenario
  skill: /my-skill
  namespace: eval-my-scenario
  runs: 3
  pass_threshold: 2
  wait_seconds: 60
  claude_flags:
    model: claude-opus-4-7     # pin — don't use floating aliases
    allowed_tools: "Bash,Read,Grep"
  ```

  Setting `placeholder: true` makes the scenario skip by default; run it
  with `./scripts/test-evals.sh --include-placeholder`.

- **`fixture.yaml`** — kubectl-applyable manifests. The runner applies
  them with `-n $namespace`, so do not embed a namespace in the manifest.

- **`prompt.txt`** — the literal user turn, passed verbatim to `claude
  -p`. Typically `Run /<skill> ... and report findings.`

- **`expected.yaml`** — rubric:

  ```yaml
  structured:                    # optional; requires skill --json output
    required_findings:
      - kind: pod_crashloop
        name: crash-server
    forbidden_findings: []
  rubric:
    must_mention: ["CrashLoopBackOff", "crash-server"]
    must_not_mention: ["ImagePullBackOff"]
    judge_criteria: |            # optional; omit to skip LLM-judge
      Response must identify pod crash-server as CrashLoopBackOff…
  ```

- **`wait.sh`** (optional, executable) — readiness gate. Exits 0 once the
  planted failure is observable. Receives the scenario's namespace as
  `$1`.

- **`teardown.sh`** (optional, executable) — runs after the last scoring
  pass (and on a `wait.sh` timeout) to undo any cluster-wide state the
  scenario mutated outside its namespace (e.g. patches to a kube-system
  ConfigMap, or CRDs installed in `wait.sh`). Receives the namespace as
  `$1`. Best-effort, time-limited to 60s, failures are logged but don't
  fail the scenario. Per-namespace cleanup isn't needed — the runner
  deletes the namespace right after `teardown.sh` runs.

## Running locally

```bash
export ANTHROPIC_API_KEY=sk-...

# Run every scenario. The kind cluster is reused across invocations by
# default — set KSTACK_REUSE_CLUSTER=0 to force teardown on exit.
./scripts/test-evals.sh

# Run just one scenario.
./scripts/test-evals.sh --scenario cluster-status-crashloop

# Include the placeholder scenario (skipped by default).
./scripts/test-evals.sh --include-placeholder
```

Requires `kind`, `kubectl`, `docker`, `claude`, `jq`, and `yq` on PATH. If
`ANTHROPIC_API_KEY` is unset, the script exits 0 with a skip message so
dev loops that only run `scripts/test.sh` / `scripts/test-e2e.sh` are
unaffected.

## Environment variables

| Var                       | Purpose                                                       |
|---------------------------|---------------------------------------------------------------|
| `ANTHROPIC_API_KEY`       | Required. Auth for `claude -p`.                               |
| `KSTACK_EVAL_MAX_RUNS`    | Override `runs` per scenario (CI sets `1` or `3`).            |
| `KSTACK_EVAL_BUDGET_USD`  | Hard cap on cumulative spend; runner exits early once hit.    |
| `KSTACK_KIND_CLUSTER`     | Kind cluster name (default `kstack-test`).                    |
| `KSTACK_REUSE_CLUSTER`    | Adopt an existing cluster; skip teardown. Default `1` here.   |

## CI

A `workflow_dispatch`-only `evals` job lives in `.github/workflows/ci.yml`.
Trigger it with `gh workflow run ci.yml`. Artifacts from every run are
uploaded as `eval-artifacts` with 30-day retention. The trigger surface
will grow (PR label, nightly cron) once we have real scenarios and a
known cost profile.
