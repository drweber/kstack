# Terminal mode cheat sheet — building `kubetail logs` invocations

Scope: how to translate a resolved target (selector, namespace, time window, grep, facet filters) into a correct `kubetail logs` command line.

**Canonical source:** the CLI source at `https://github.com/kubetail-org/kubetail/tree/main/modules/cli/cmd/logs.go` and `kubetail logs --help`. If anything here disagrees with the running CLI on the user's installed version, trust `--help`. This file is a hint and may lag.

> **tmux wrapping:** the SKILL workflow handles wrapping the resolved command in a detached `kstack-logs-<slug>` tmux session and opening a terminal on it. This document is purely about the `kubetail logs ...` arg vector you put inside that session.

## Command shape

```
kubetail logs [flags] <source> [<source>...]
```

At least one **source** positional is required. Sources select pods/containers; flags control stream mode, time window, filtering, output, and backend.

## Source syntax

```
[<namespace>:]<workload-kind>/<name>[/<container>]
[<namespace>:]<pod-name>[/<container>]
```

- **Namespace prefix** (`<ns>:`) is optional. If omitted, kubetail uses the kubeconfig context's default namespace, falling back to `default`.
- **Workload kinds** (case-sensitive, plural and short forms accepted):
  `pod`/`pods`/`po`, `deployment`/`deployments`/`deploy`, `daemonset`/`daemonsets`/`ds`, `statefulset`/`statefulsets`/`sts`, `replicaset`/`replicasets`/`rs`, `job`/`jobs`, `cronjob`/`cronjobs`/`cj`.
- **Container segment** (`/<container>`) narrows to one container. Use `/*` to select all containers in the matched pods (equivalent to `--all-containers` for that source). Omit it to get the default (main) container.
- **Wildcards in the workload name** are accepted: `deployments/*` matches every deployment in the namespace.
- **Multiple sources** are merged: `kubetail logs deployments/api deployments/worker` tails both.

Examples (from `kubetail logs --help`):

| Positional | Meaning |
|------------|---------|
| `web-abc123` | Pod named `web-abc123` in the default namespace, default container |
| `deployments/web` | Deployment `web`, default container in every matching pod |
| `deployments/web/api` | Deployment `web`, only the `api` container |
| `deployments/web/*` | Deployment `web`, all containers (init + main + sidecars) |
| `deployments/*` | Every deployment in the default namespace |
| `frontend:web-abc123` | Pod `web-abc123` in namespace `frontend` |
| `frontend:deployments/web` | Deployment `web` in namespace `frontend` |

## Stream mode (mutually exclusive: `--head` / `--tail` / `--all`)

| Flag | Short | Type | Default | Behavior |
|------|-------|------|---------|----------|
| `--tail[=N]` | `-t` | optional int64 | 10 when bare | Last N records, then exit (or stream if `--follow`). |
| `--head[=N]` | `-h` | optional int64 | 10 when bare | First N records from the start of the window, then exit. |
| `--all` | — | bool | false | Every record in the window. |
| `--follow` | `-f` | bool | false | Stream new records indefinitely. Combine with `--tail` or `--all` (not bare `--head`). |

**Default:** if none of `--head`/`--tail`/`--all`/`--since` is set, kubetail picks `--tail=10`. If `--since` is set without an explicit mode, it picks `--head` (first records from that point). Don't rely on these defaults blindly — always set the mode you want.

## Time-window flags

Four flags pair up:

| Flag | Mutually exclusive with | Semantics |
|------|------------------------|-----------|
| `--since` | `--after` | Inclusive lower bound |
| `--after` | `--since` | Strictly-after lower bound (kubetail converts to `since = after + 1ns`) |
| `--until` | `--before` | Inclusive upper bound |
| `--before` | `--until` | Strictly-before upper bound (kubetail converts to `until = before - 1ns`) |

**Accepted formats** for every time flag:

- ISO 8601 *duration* relative to *now*: `PT30M`, `PT1H`, `PT15S`, `P1D`. Parsed as a negative offset from `time.Now()` — no minus sign needed.
- RFC 3339 timestamp: `2024-06-15T10:30:00Z`, `2024-06-15T10:30:00.123Z`.
- Empty string = no bound on that side.

Use durations for "last N minutes / hours" requests; use RFC 3339 only when the user names an absolute instant.

## Grep / search

| Flag | Short | Type | Notes |
|------|-------|------|-------|
| `--grep` | `-g` | string (regex) | Case-insensitive (kubetail prepends `(?i)`); ANSI-tolerant around whitespace; **regex, not literal**. |

- Pattern is Go `regexp` syntax. To send a literal phrase, escape regex metachars yourself or wrap in non-meta characters (e.g. word boundaries).
- Multiple `--grep` flags: last one wins. There is no inversion flag — use a regex negative lookahead if you need "not matching X".
- Empty value disables grep.
- **Backend matters:** with the Kubetail API backend, grep runs server-side (efficient). With the Kubernetes API backend, grep runs client-side and kubetail prints `Warning: Kubernetes API backend filters records locally. Use Kubetail API backend for remote grep.` See "Backend" below.

## Source-filter flags (facets)

All five accept either repeated flags or comma-separated values; multiple values within one flag = OR, multiple different flags = AND.

| Flag | Type | Filters by |
|------|------|------------|
| `--region` | []string | Pod's node region (cloud metadata) |
| `--zone` | []string | Pod's node availability zone |
| `--node` | []string | Pod's node name |
| `--os` | []string | Pod's node OS (`linux`, `windows`) |
| `--arch` | []string | Pod's node CPU arch (`amd64`, `arm64`) |

These filters require the **Kubetail API backend**. With the Kubernetes API backend, they're effectively ignored.

## Container selection

| Flag | Type | Default | Notes |
|------|------|---------|-------|
| `--all-containers` | bool | false | Include init containers, main containers, and sidecars/ephemeral containers. Equivalent to suffixing every source with `/*`. |

There is **no `--container` / `-c` flag** — pick a specific container via the source path's third segment (`deployments/web/sidecar`).

Default behavior: only main containers (from `pod.Status.ContainerStatuses`).

## Output / formatting

| Flag | Type | Default | Behavior |
|------|------|---------|----------|
| `--raw` | bool | false | Strip every metadata column; print only the log message. Forces `--hide-header` and disables `--all-containers` columns. |
| `--columns` | []string | `timestamp,dot` | **Replaces** the default column set. Valid names: `timestamp`, `dot`, `node`, `region`, `zone`, `os`, `arch`, `namespace`, `pod`, `container`. |
| `--add-columns` | []string | — | Append columns to the current set (deduped). |
| `--remove-columns` | []string | — | Remove columns from the current set. |
| `--hide-header` | bool | false | Suppress the table header row. |
| `--with-cursors` | bool | false | After the stream ends (only without `--follow` and `--all`), print `--- Next page: --after <ts> ---` / `--- Prev page: --before <ts> ---` cursors for paginating. |

The `dot` column renders a colored bullet keyed off container ID; it's stripped automatically when stdout isn't a color-capable TTY (or when `$NO_COLOR` is set).

## Kubeconfig / context

| Flag | Type | Notes |
|------|------|-------|
| `--kube-context` | string | Kubeconfig context name. **Always pass `--kube-context=<pinned>`** — this is the kstack convention. |
| `--kubeconfig` | string | Path to kubeconfig file. Usually unset. |
| `--in-cluster` | bool | Use in-cluster service-account auth. Only relevant when running kubetail itself inside a pod — the agent will not normally use this. |

There is **no `--namespace` / `-n` / `--all-namespaces` / `-A` flag** on `logs`. Namespace selection is per-source via the `<ns>:` prefix on each positional argument.

## Backend

| Flag | Type | Default | Behavior |
|------|------|---------|----------|
| `--backend` | string (`auto` \| `kubetail` \| `kubernetes`) | `auto` | Which API backend to use. |

- `auto` — probe the in-cluster Kubetail API; use it if installed, otherwise fall back to the vanilla Kubernetes API and print a warning suggesting `kubetail cluster install`.
- `kubetail` — require the Kubetail API; error out if it isn't installed.
- `kubernetes` — skip the probe and use the Kubernetes API directly; grep runs locally (slow on large logs) and facet filters are ignored.

The skill's preconditions already confirm the Kubetail API is installed, so you almost always want `--backend=auto` (the default — usually no need to pass it explicitly). Pass `--backend=kubetail` only when you want the command to fail loudly if the API is missing.

## Mapping the resolved target onto flags

The SKILL's Workflow step 2 resolves the user's request into primitives. Map each onto kubetail flags:

| Resolved primitive | Flag(s) |
|--------------------|---------|
| Pinned kube context | `--kube-context=<pinned>` |
| Namespace | `<ns>:` prefix on every positional source |
| Workload selector | positional `<kind>/<name>` (one per match) |
| Specific pod | positional `<ns>:<pod-name>` |
| Specific container | third segment of the source: `<kind>/<name>/<container>` |
| All containers in scope | `/*` on each source, or `--all-containers` |
| Time window (relative, e.g. "last 15m") | `--since=PT15M` |
| Time window (absolute start) | `--since=<RFC3339>` |
| Time window (absolute end) | `--until=<RFC3339>` |
| Grep literal | `--grep="<phrase>"` (escape regex metachars first) |
| Grep regex | `--grep="<pattern>"` |
| Facet filter | `--region`/`--zone`/`--node`/`--os`/`--arch`, repeated or CSV |
| Stream new records | `--follow` |
| First N vs last N | `--head[=N]` vs `--tail[=N]` |
| Everything in window | `--all` |

## Worked examples

### Tail one deployment (most common case)

User: *"errors on api last hour"*

```
kubetail logs --kube-context=<pinned> --since=PT1H --grep=error --follow deployments/api
```

### Specific container in a specific namespace

User: *"checkout sidecar logs in prod"*

```
kubetail logs --kube-context=<pinned> --follow prod:deployments/checkout/sidecar
```

### Multiple workloads, last 100 records

User: *"last 100 lines from api and worker"*

```
kubetail logs --kube-context=<pinned> --tail=100 deployments/api deployments/worker
```

### Regex grep with follow

User: *"stream anything matching `error[0-9]+` from checkout"*

```
kubetail logs --kube-context=<pinned> --grep='error[0-9]+' --follow deployments/checkout
```

### Time range with `--all`

User: *"every record between 10:00 and 11:00 UTC on June 15 from nginx"*

```
kubetail logs --kube-context=<pinned> --since=2024-06-15T10:00:00Z --until=2024-06-15T11:00:00Z --all deployments/nginx
```

### Facet filter (region + arch)

User: *"web logs from us-east-1 on arm64 nodes"*

```
kubetail logs --kube-context=<pinned> --region=us-east-1 --arch=arm64 --follow deployments/web
```

### All containers including init

User: *"every container — init, main, sidecars — in the api pods"*

```
kubetail logs --kube-context=<pinned> --all-containers --follow deployments/api
```

### Raw output (just messages)

User: *"give me api logs with no metadata, just the messages"*

```
kubetail logs --kube-context=<pinned> --raw --follow deployments/api
```

### Custom columns

User: *"show pod and container columns alongside the message"*

```
kubetail logs --kube-context=<pinned> --columns=timestamp,pod,container --follow deployments/api
```

## Gotchas

- **`--head`/`--tail`/`--all` are mutually exclusive.** Cobra rejects more than one. Default is `--tail=10` if you set none.
- **`--head` alone with `--follow` is invalid.** `--head=N --follow` errors out. Use `--tail --follow` or `--all --follow` to stream after a backfill.
- **No `-n`/`--namespace`.** It's per-source, prefixed with `<ns>:`. Forgetting the prefix silently uses the kubeconfig default namespace.
- **Grep is regex and case-insensitive.** A user-supplied "literal" with regex metachars (`.`, `+`, `?`, `(`, `)`, `[`, `]`, `*`, `^`, `$`, `{`, `}`, `|`, `\`) needs escaping if you intend a literal match.
- **Facet filters silently no-op without the Kubetail API backend.** If you're paranoid about a fall-back to the Kubernetes API, pass `--backend=kubetail` to surface the missing API as an error.
- **Default container resolution.** Without `--all-containers` or an explicit container in the source path, kubetail picks main containers only — init and sidecar containers are excluded.
- **Exit codes are coarse.** Any error → exit 1, including "no pods matched". Read stderr to distinguish causes; don't branch on the exit code alone.
- **Wildcards live in the source path, not in flags.** `deployments/*` is the way to spread; there is no `--label` / `-l` selector flag on `logs`.

## When to fall back to GUI mode

If the user's request is exploratory, multi-source without a precise selector, or asks for the dashboard / browser / console, switch to **GUI mode** (`kubetail serve` + browser deep link). See `references/kubetail-serve.md`.
