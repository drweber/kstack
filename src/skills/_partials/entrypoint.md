## Entrypoint

Before doing anything else this turn, run:

    {{ROOT_DIR}}/bin/entrypoint --skill-dir={{SKILL_DIR}} -- <user args verbatim>

The script exits 0 and writes a single JSON object (the **kstack response envelope**) to stdout. Parse the envelope and dispatch:

- `{"status":"ok","render":"verbatim","content":"…"}` — Response is complete. Print `content` verbatim and end the turn. Do not reformat, summarize, or add commentary.
- `{"status":"ok","render":"agent","content":"…"}` — Continue. If `content` is non-empty, treat it as tool output (context for your reasoning). Then run the rest of this SKILL.md as usual.
- `{"status":"error","kind":"user","message":"…"}` — Print `message` verbatim and end the turn. This is a user-fixable error (bad flag, missing arg); do not retry or reinterpret.
- `{"status":"error","kind":"infra","message":"…"}` — Print `message` verbatim and end the turn. This is an environment/install failure.

If an `agent_context` field is present, read it as additional context for your reasoning and any follow-up turns — but **never** show it to the user. Its format is skill-specific (typically compact JSON); the SKILL.md body documents what to extract.

If a `kube_context` field is present, that is the cluster this turn ran against (the entrypoint resolved it via `--context` flag / `$KSTACK_KUBE_CONTEXT` env / `kubectl config current-context`). Treat it as the **pinned** cluster for this session: thread `--context=<value>` into every subsequent kstack skill call so the session stays stable across out-of-band `kubectl config use-context` changes. Drop the pin only when the user explicitly switches clusters (mentions another context name, says "now check staging", "switch to prod", etc.). When the pin drops, any `cache_dir` or similar paths carried on prior `agent_context` blocks are stale — they belonged to the old cluster.

If a `notice` field is present on any envelope, prepend it verbatim to whatever you emit this turn — above any `content` or `message`. Notices are update banners the operator needs to see.

If stdout is empty or not a JSON object (the entrypoint crashed before emitting an envelope), print stderr and stop.

The envelope schema is at `{{ROOT_DIR}}/schemas/response.schema.json`.

If the user later says "upgrade kstack" / "install the update", run `{{ROOT_DIR}}/bin/upgrade` and report the result (idempotent). If the user says "dismiss" / "hide the notice", run `{{ROOT_DIR}}/bin/dismiss-update` and confirm.
