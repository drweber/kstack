# GUI mode cheat sheet — building `/console` URLs

Scope: how to construct deep-linked URLs into the Kubetail logging console at `http://localhost:7500/console`. The console reads filters from query-string parameters and applies them on load — there is **no share-link generator** in the UI, so the agent builds these URLs by hand.

**Canonical source:** the dashboard SPA source at `https://github.com/kubetail-org/kubetail/tree/main/dashboard-ui/src/pages/console` and `kubetail serve --help`. If anything here disagrees with the running console on the user's installed version, trust the SPA. This file is a hint and may lag.

> **Starting `kubetail serve`:** the SKILL workflow handles probing `http://localhost:7500/` and starting `kubetail serve --skip-open` in a detached `kstack-logs-ui` tmux session. This document is purely about the URLs you point the user's browser at after the backend is up.

## URL shape

```
http://localhost:7500/console?<param>=<value>&<param>=<value>...
```

All filters are query-string params on `/console`. Apply standard URL percent-encoding to every value (spaces, slashes inside regexes, etc.). Multi-value params are encoded as **repeated keys** — *not* CSV.

## Parameter reference

| Param | Cardinality | Format | Purpose |
|-------|-------------|--------|---------|
| `kubeContext` | single | raw cluster-context name | Which kube context to query. Maps to the kstack `<pinned>` context. |
| `source` | multi (repeat) | `<namespace>:<workload-kind>/<name>` | Workloads to tail. `workload-kind` ∈ `deployments`, `statefulsets`, `daemonsets`, `replicasets`, `cronjobs`, `jobs`, `pods`. Wildcards in the name segment are accepted (e.g. `default:deployments/nginx/*`). |
| `container` | multi (repeat) | `<namespace>:<pod-name>/<container-name>` | Narrow to specific containers within pods. Same parsing regex as `source`. |
| `grep` | single | literal *or* `/regex/` | Search filter. Bare strings are matched literally (special chars escaped server-side). Wrap in forward slashes (`/pattern/`) for regex. Invalid regex fails silently. |
| `region` | multi (repeat) | raw string | Cloud region facet (`us-west-1`, etc.). |
| `zone` | multi (repeat) | raw string | Availability zone facet. |
| `node` | multi (repeat) | raw string | Kubernetes node name facet. |
| `os` | multi (repeat) | raw string | OS facet (`linux`, `windows`). |
| `arch` | multi (repeat) | raw string | CPU arch facet (`amd64`, `arm64`). |
| `mode` | single | `head` \| `tail` \| `cursor` | Initial scroll position. Default `tail`. |
| `cursor` | single | RFC 3339 / ISO-8601 timestamp | Required when `mode=cursor`; jump to that point in time. |

### Parsing strictness

- `source` and `container` use the regex `^([^:]+):([^/]+)\/(.+)$`. Anything that doesn't match is **silently dropped** — there is no error toast. Always emit the namespace prefix even when it feels redundant.
- Facet params (`region`, `zone`, `node`, `os`, `arch`) accept any non-empty string and are matched against pod metadata. Empty values render an empty facet row, so don't include `?region=` with no value.
- `grep` literals are escaped server-side; you do not need to escape regex metachars yourself when sending a literal. To send a *regex*, wrap it in `/.../` and percent-encode the slashes inside.

## Time windows

The `/console` route does **not** accept relative time-window params (`since=1h`, `until=...`) for deep-linking. The console always boots in tail mode and the user adjusts the window from inside the UI.

What the URL *does* support is jumping to an absolute timestamp:

```
?mode=cursor&cursor=2024-06-15T10:30:01Z
```

When the user's natural-language request specifies a relative window like "last 15 minutes":

- If you can compute an absolute start timestamp (current time minus the window), emit `mode=cursor&cursor=<ISO-8601>` to land at the start of the window.
- Otherwise, omit `mode`/`cursor`, let the console open in `tail`, and surface the requested window as a "suggested filter" in chat for the user to apply via the UI's time-range control.

The download dialog inside the console accepts richer time inputs (ISO-8601 durations like `PT1M`/`P1D`, unix timestamps, relative phrases), but those are POST-form fields, **not** URL params. Don't try to encode them as query string.

## Mapping the resolved target onto params

The SKILL's Workflow step 2 resolves the user's request into these primitives. Map each onto the console's params:

| Resolved primitive | Param(s) |
|--------------------|----------|
| Pinned kube context | `kubeContext` |
| Namespace | encoded into the `<namespace>:` prefix of every `source`/`container`; **not** a standalone param |
| Workload selector (deployment / daemonset / etc.) | `source` (repeat for each match) |
| Specific pod | `source=<ns>:pods/<pod-name>` |
| Specific container | `container=<ns>:<pod-name>/<container-name>` |
| Grep literal | `grep=<literal>` |
| Grep regex | `grep=/<pattern>/` (percent-encode the slashes) |
| Source filter (node, region, zone, os, arch) | matching facet param, repeated for each value |
| Time window start (absolute) | `mode=cursor&cursor=<ISO-8601>` |
| Time window (relative, can't resolve) | omit; surface in chat |

Build the URL by appending each resolved primitive's params in any order — ordering does not affect behavior.

## Worked examples

### Tail one deployment in a namespace

User: *"open the dashboard for the api deployment in prod"*

```
http://localhost:7500/console?kubeContext=prod&source=prod:deployments/api
```

### Multiple workloads, literal grep

User: *"browse api and worker logs filtered for 'timeout'"*

```
http://localhost:7500/console?source=default:deployments/api&source=default:deployments/worker&grep=timeout
```

### Regex grep

User: *"show me anything matching `error[0-9]+` across the checkout pods"*

```
http://localhost:7500/console?source=default:deployments/checkout&grep=%2Ferror%5B0-9%5D%2B%2F
```

(Decoded: `grep=/error[0-9]+/`. The outer `/` and inner `[`, `]`, `+` are percent-encoded.)

### Narrow to a container

User: *"open the console pinned to the sidecar container of api-7d-xyz"*

```
http://localhost:7500/console?source=default:pods/api-7d-xyz&container=default:api-7d-xyz/sidecar
```

### Facet filtering by node and region

User: *"browse logs from the us-west-1 region, only worker-1 and worker-2"*

```
http://localhost:7500/console?region=us-west-1&node=worker-1&node=worker-2
```

### Jump to a specific timestamp

User: *"open the console at 10:30 UTC on June 15 2024"*

```
http://localhost:7500/console?mode=cursor&cursor=2024-06-15T10:30:00Z
```

### Relative window translated to cursor

User: *"open the console for api, last 15 minutes"* (current time `2026-05-06T12:00:00Z`)

```
http://localhost:7500/console?source=default:deployments/api&mode=cursor&cursor=2026-05-06T11:45:00Z
```

### Complex deep link

```
http://localhost:7500/console?kubeContext=prod&source=default:deployments/api&source=default:deployments/web&container=default:api-pod/api&region=us-west-1&grep=error&mode=cursor&cursor=2024-06-15T10:30:01Z
```

## Encoding rules

- Always percent-encode values. The `:` and `/` characters inside `source`/`container` values are part of the format and should stay unencoded; everything else (spaces, regex metachars, slashes inside a `grep` regex) gets encoded.
- Multi-value params: repeat the key. `?region=us-west-1&region=us-east-1` ✅. `?region=us-west-1,us-east-1` ❌ (treated as one literal value `us-west-1,us-east-1`).
- Empty values: omit the param entirely. Don't emit `?grep=` or `?region=` with no value.
- Param order: irrelevant.

## Things this URL schema does *not* support

Don't try to encode any of these as query params — they're not read by the console:

- Relative durations (`since=1h`, `last=15m`).
- An end-of-window timestamp (`until`, `end`). You can pin a *start* via `cursor`, but not a stop.
- Container/pod names without their namespace prefix.
- Regex flags (`/pattern/i`) — the regex is consumed as-is, no flag parsing.
- Output column selection — column visibility is set in the app config, not the URL.

When the user wants behavior the URL can't express, open the console with whatever params *do* apply and surface the rest in chat as a suggested filter for the user to apply via the UI controls.

## Probing & lifecycle

Repeat of the SKILL workflow's invariants, since they bound this document's scope:

- The agent ensures `kubetail serve --skip-open` is running in `kstack-logs-ui` (a detached tmux session) and that `http://localhost:7500/` returns 200 before opening any URL.
- The agent never auto-restarts an existing `kstack-logs-ui` session; if the backend behaves oddly, attach with `tmux attach -t kstack-logs-ui` to inspect server logs and ask the user before killing/restarting.
- The standard `/logs` teardown verb kills `kstack-logs-ui` along with any tail sessions.

## When to fall back to terminal mode

If the user's request maps cleanly to a single workload + window + grep, **terminal mode** (`kubetail logs` in tmux) is the better fit — see `references/kubetail-logs.md`. The console is for exploratory, multi-source, or interactive cases where the user wants to drive the filter UI themselves.
