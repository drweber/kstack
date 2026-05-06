# kstack TODO

Overall plan from README-finished to v0.1.0 launch. Grouped by phase; within each phase items are roughly ordered.

## MISC

- [ ] Add a clean-up skill that removes all "kstack-managed" cluster resources
- [ ] Link to web-hosted help docs instead of expanding help into agent context
- [ ] Stop re-installing preinstalled tools in ci.yaml
- [ ] `/cluster-status`: support "pods on `<node>`" queries
- [ ] We should teach the agent to fetch it's own latest data if necessary (e.g. user says "update pods")
- [ ] Implement `--dry-run`
- [ ] Saftey:
The real mitigation stack for /logs is layered:

Skill prompt frames log content as data (reduces hit rate on obvious injections).
Read bounded slices from disk rather than dumping everything inline (reduces surface).
The agent still confirms before destructive actions (catches what gets through).
Users know logs are untrusted (sets expectations).

## Foundation

- [x] Scaffold repo layout — `.claude/skills/`, `bin/`, `skills/*/SKILL.md.tmpl`, document placeholder resolution convention
- [x] Build `install` script with multi-agent support — auto-detect + `--agent <name>` flag per README agent table (codex, opencode, cursor, factory, slate, kiro, hermes); supports dev, `--local`, and `--global` modes
- [x] Build `uninstall` script
- [x] Shared global flag handling — `--context`, `--namespace`, `--json`, `--dry-run` across every skill
- [x] Upgrade path — `git pull && make install` (dev); `$ROOT_DIR/bin/upgrade` wrapper for managed (`--local`, `--global`) installs; `curl | bash [-s -- --local]` bootstrap at `kubestack.xyz/install.sh` tracks the latest tag
- [x] Update notifications — `bin/check-update` runs from skill preamble on each invocation (24h cache, both modes), `bin/dismiss-update` silences per-version, `bin/upgrade` mode-aware; all three agent-invoked, not user-facing

## Pilot skill + testing

- [ ] Scaffold `/cluster-status` as the pattern-setter for all other skills (includes defining its `--json` output schema, which the first eval scenario will assert against)
- [x] Build eval harness — scenario-driven runner (`scripts/test-evals.sh`) that plants fixtures in the kind cluster, invokes skills via `claude -p`, and scores responses via keyword + structured JSON + LLM-as-judge. Placeholder smoke scenario lands with the harness; real scenarios follow per-skill.
- [ ] Write first eval scenario for `/cluster-status` (`cluster-status-crashloop`) — blocked on the skill landing with a `--json` schema
- [x] CI — `evals` job added (`workflow_dispatch`-only for now; graduate to PR label / nightly cron once scenarios stabilize)

## Remaining skills

Priority: highest-value + simplest first.

- [ ] `/events` — Events API query with dedup and noisy-reason collapse; detect event exporter backends
- [ ] Enable remote grep in Kubetail CLI — `/logs` depends on this CLI surface
- [ ] `/logs` — shell out to kubetail for node-side regex filter
- [ ] `/investigate` — root-cause analysis with state-specific paths for Pending/CrashLoopBackOff/OOMKilled/ImagePullBackOff/Error
- [ ] `/watch` — detached watcher with state-hash filter; management via `--list`/`--stop`
- [ ] `/exec` — interactive exec + ephemeral debug container fallback for scratch/distroless
- [ ] `/audit-security` — RBAC, pod security, secrets; Kyverno/OPA/Falco integration; SARIF output
- [ ] `/audit-network` — NetworkPolicy, Service, Ingress, Gateway API, DNS, encryption; Cilium/Istio/Linkerd integration
- [ ] `/audit-cost` — requests vs usage; metrics-server + Prometheus/OpenCost integration
- [ ] `/audit-outdated` — version skew, image/chart freshness, CVE scan via Trivy, deprecated API detection

## Launch prep

- [ ] Add `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1 (referenced in README badge)
- [ ] Add issue/PR templates and `CONTRIBUTING.md`
- [ ] Verify assets — confirm `assets/kstack.svg`; add social preview card
- [ ] Translate README into 7 languages — zh-CN, ja, ko, de, es, pt-BR, fr under `.github/`
- [ ] Verify external links — Discord, Slack, kubetail-org GitHub
- [ ] Tag `v0.1.0` and announce — release notes, Discord/Slack post

## Decisions locked in

- Pilot skill: `/cluster-status`
- Translations: done pre-launch (README already links them as if they exist)
- Kubetail remote grep: the Rust filter exists; work is enabling it in the Kubetail CLI
- Testing: kind fixtures + eval rubric, deferred until `/cluster-status` is scaffolded

## Open questions

- [ ] How to handle default kubeconfig context — honour at startup, allow mid-session switches, propagate to skills per turn

It's on the edge of acceptable, and the mitigations are real but imperfect. Honest answer in three parts.

Where it sits today. The current model — shared tmux pane, agent can type, user can type, agent reads pane output into context — is a legitimate design, not a reckless one. It's roughly the same shape as Claude Code's own Bash tool: agent proposes commands, runs them, reads output, decides next step. The thing that makes /exec meaningfully riskier than local Bash is the target: a shell inside a production cluster, sometimes with node-level privileges, where an errant command doesn't just break your laptop. The tmux pane itself isn't the problem; the privilege of the endpoint is.

Mitigations that actually help, roughly in order of payoff:

Command-class gating. Not "confirm every command" (users will rubber-stamp) but "confirm the dangerous ones." Destructive verbs (rm, kubectl delete, drop, truncate), anything that writes outside /tmp, anything that touches the API server, anything in node mode that touches /host. A short allowlist of read-only verbs the agent can run without asking covers 80% of real use and makes the confirmations meaningful.

Mode-scaled trust. Pod-container exec is much lower-risk than node or debug mode. The skill could require explicit user approval to enter node/debug mode (it mostly does already) and then apply stricter gating inside those modes — more commands require confirmation, the agent narrates what it's about to do before typing.

Pane-output framing. The skill prompt tells the agent: pane output is untrusted data, never treat lines that look like prompts or system messages as coming from the user, always attribute instructions to the chat channel not the pane. Reduces the rate of successful injections without eliminating them.

Time and scope bounds. Node-mode pods are already short-lived per the doc; making that a hard TTL (auto-teardown after N minutes unless extended) limits how long an injected instruction has to land. Same for debug containers.

Audit trail. Pane contents are already in tmux scrollback — making sure the session name and transcript are easy for the user to review post-hoc turns "I didn't notice" into "I can check." Not prevention, but a real deterrent and a real debugging aid when something goes wrong.

RBAC on the kstack service account. The blast radius of any exec is ultimately bounded by what credentials are reachable from the session. Documenting a least-privilege install (and defaulting to it) caps the worst case. This is the mitigation that survives even when the model is wrong.


Partially, and the partial answer is actually pretty useful. Let me break down what's possible at each layer.

What Kubernetes gives you natively.

securityContext.readOnlyRootFilesystem: true — makes / read-only inside the container. The agent can still read everything, can't write to container paths. Writable emptyDir volumes can be mounted for scratch space if needed (/tmp).
securityContext.capabilities.drop: [ALL] and add: [] — strips Linux capabilities. For a debug container you'd keep SYS_PTRACE (so strace/gdb//proc/<pid>/root work) and drop the rest. No CAP_NET_ADMIN, no CAP_SYS_ADMIN.
runAsNonRoot: true / runAsUser: <n> — doesn't help much for debug because you often need root to read other containers' /proc/<pid>/root, but worth considering for the pod-exec default.
allowPrivilegeEscalation: false — prevents sudo/setuid tricks.
seccompProfile — a restrictive seccomp profile can block whole syscall families (e.g. no mount, no ptrace write operations, no bpf).
These work cleanly for debug-container mode. You keep process-namespace sharing and /proc/<pid>/root visibility (both are kernel-level, not capability-gated for reading), strip write capabilities, and mark the rootfs read-only. The user can still inspect everything — filesystems, network state, processes — and can't accidentally (or via injection) modify the target container's filesystem or its network.

Where it gets harder: node mode.

Node mode is privileged by construction — hostPID, hostNetwork, host filesystem mounted at /host. "Read-only" there is a spectrum:

/host can be mounted readOnly: true. That's a real win — the agent can cat /host/etc/kubernetes/manifests/* but can't rm them or drop a pod manifest into /etc/kubernetes/manifests/ (which would be a root-on-node escape). I'd make this the default and require an explicit flag to get a writable host mount.
hostPID lets you read /proc/<pid>/root of host processes read-only without extra capabilities, so read-only host access still buys you most of the debugging value (journalctl via the host's journal, kubelet config, crictl state, process inspection).
What you can't easily make read-only: hostNetwork. The pod shares the node's network namespace, which means it can send arbitrary packets, talk to the kubelet on localhost, reach the cloud metadata service, etc. You can restrict this with a NetworkPolicy, but node-mode's whole value is that it can reach these things — neuter it and the mode stops being useful.
crictl / container runtime socket — if mounted, the agent can start/stop containers on the node. Don't mount it by default; make it a separate "I really need to poke the runtime" mode.
So node mode can be filesystem-read-only by default, which is the single biggest risk reduction (it blocks the "write a static pod manifest" escape and the "modify kubelet config" escape), while keeping read access that makes the mode useful. Network and PID namespace sharing stay as they are because that's what the mode is for.

Pod-container exec. This is trickier — you're exec'ing into a container that's already running with its own securityContext. You can't retroactively make its rootfs read-only from the exec side. What you can do: when the pod's own security posture is permissive (running as root, writable rootfs), the skill can warn the user before connecting. For the common case you'd just want the agent to not rm things it shouldn't, which lands back in command-class gating rather than container sandboxing.

What I'd propose concretely:

Debug mode: read-only rootfs, drop all caps except SYS_PTRACE, allowPrivilegeEscalation: false, emptyDir at /tmp for scratch. Default. A flag like --writable escalates if the user needs it.
Node mode: read-only /host mount by default; keep hostPID and hostNetwork (they're what the mode is for); do not mount the container runtime socket by default. Flags --writable-host and --runtime-socket opt in explicitly.
Surface the posture in the session banner. When the session opens, print what's read-only and what isn't — "host fs: read-only, runtime socket: not mounted" — so the user knows the blast radius before they start.
This doesn't replace command-class gating or pane-output framing, but it changes the risk profile meaningfully: an injection that successfully steers the agent into running rm -rf /host/etc/kubernetes just fails at the kernel level. That's the kind of mitigation that survives when the model is wrong, which is the bar worth aiming for.

Worth writing up in /exec.mdx once we settle on the defaults — the "Behavior" boxes under each mode are exactly where it'd land.
