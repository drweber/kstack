# Contributing to kstack

Thank you for your interest in contributing to kstack! We're building a skill pack that brings AI-assisted Kubernetes monitoring, troubleshooting, and auditing to Claude Code and other agent CLIs, and we'd love your help.

This document will guide you through the contribution process.

## Table of Contents

- [Where to Find Code](#where-to-find-code)
- [How to Run Tests and Other Checks](#how-to-run-tests-and-other-checks)
- [Filing an Issue](#filing-an-issue)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Branch Naming Guidelines](#branch-naming-guidelines)
- [Editor Configuration](#editor-configuration)
- [Automation](#bots-and-automation)
- [AI Policy](#ai-policy)
- [Community](#community)

## Where to Find Code

Kstack is a **skill pack** (not an app). The shipped artifacts are `SKILL.md` files plus a handful of POSIX shell helpers — there is no runtime service. The split is: **`src/` = installer payload (what gets copied or rendered into an install root); everything else = dev infra.**

### Main Components

- **`/src`** — installer payload
  - `bin/` — install-time and runtime shell helpers (`entrypoint`, `check-update`, `upgrade`, `uninstall`, …)
  - `lib/` — sourced shell libraries (`agents.sh`, `response.sh`, `manifest.sh`, …)
  - `skills/` — skill templates (`<name>/SKILL.md.tmpl`, optional `scripts/main`) and shared `_partials/`
  - `schemas/` — JSON schemas (e.g. response envelope)

- **`/scripts`** — repo dev scripts (`install`, `lint.sh`, `test.sh`, `test-e2e.sh`, `test-evals.sh`, `bootstrap.sh`, `clean.sh`)

- **`/tests`** — bats + eval harness (`unit/`, `integration/`, `e2e/`, `evals/`, `fixtures/`)

- **`Makefile`** — thin facade over `scripts/` (`make install`, `make test`, `make lint`, `make clean`)

### Quick Reference

| Working on...                                | Go to                                  |
|----------------------------------------------|----------------------------------------|
| A skill's prose / template                   | `src/skills/<name>/SKILL.md.tmpl`      |
| A skill's shell logic                        | `src/skills/<name>/scripts/main`       |
| Cross-cutting prose (global flags, preamble) | `src/skills/_partials/`                |
| The installer                                | `scripts/install`                      |
| Hosted `curl \| bash` bootstrap              | `scripts/bootstrap.sh`                 |
| Agent registry (name → CLI → skills dir)     | `src/lib/agents.sh`                    |
| Help text for a skill                        | `#### /<skill>` section in `README.md` |

See [`CLAUDE.md`](./CLAUDE.md) for the full architecture overview (rendering pipeline, install modes, response envelope contract).

## How to Run Tests and Other Checks

Make sure your changes pass all tests and checks before submitting a pull request.

### Shell

All shipped shell (`scripts/install`, everything under `src/bin/` and `src/lib/`, plus any skill `scripts/main`) must run on **bash 3.2+** — that's macOS's `/usr/bin/bash`. Concretely: no `declare -A`, no `${var,,}`/`${var^^}`, no `mapfile`/`readarray`, no `&>` redirection, and watch out for `set -u` + empty arrays. Dev-only scripts (`scripts/*.sh`, `tests/**`) may assume newer bash since they only run on CI/contributor machines.

```bash
# Lint (shellcheck, severity=warning) — requires `shellcheck`
./scripts/lint.sh

# Fast bats tiers (unit + integration) — requires `bats-core`
./scripts/test.sh

# Run a single test file
bats tests/unit/agents.bats

# Run a single test by name
bats -f "renders SKILL.md" tests/integration/install.bats
```

### Cluster-backed tests

The e2e and eval tiers stand up a kind cluster (`kstack-test`) and require Docker.

```bash
# E2E tier — requires `kind`, `kubectl`, Docker
./scripts/test-e2e.sh

# Reuse the cluster across runs during dev loops
KSTACK_REUSE_CLUSTER=1 ./scripts/test-e2e.sh

# Eval tier — additionally requires ANTHROPIC_API_KEY, `claude`, `jq`, `yq`
./scripts/test-evals.sh

# Run a single eval scenario
./scripts/test-evals.sh --scenario <id>
```

### Local install for manual testing

```bash
# Render skills into <repo>/.<agent>/skills/ for every agent CLI on PATH
make install

# Wipe gitignored install artifacts so install runs against a clean tree
make clean
```

## Filing an Issue

For anything larger than a typo — and especially for a new skill, where the shape of the answer matters more than the code — an issue first saves everyone time.

Opening one offers two templates:

- **Bug report** — a skill misbehaved, the installer failed, or something doesn't match the docs.
- **Feature or skill request** — a new skill, or something an existing skill should also handle.

Usage questions get a faster answer on [Discord](https://discord.gg/CmsmWAVkvX) or in the [Kubernetes Slack channel](https://kubernetes.slack.com/archives/C08SHG1GR37). Security vulnerabilities go to hello@kubetail.com rather than a public issue — see [SECURITY.md](./SECURITY.md).

Two details are specific to kstack and worth including up front:

- **Which skill**, plus the installed version — `cat ~/.config/kstack/manifest/version` for a global install, `cat .kstack/manifest/version` for local or dev.
- **Which agent CLI**, since skills render per agent into that agent's own skills directory.

One caution: skill output carries real cluster detail — namespaces, workload and node names, labels. Redact anything you'd rather not publish before pasting it.

## Commit Guidelines

Keep commits minimal and focused. Multiple commits in a PR are fine if they represent logical, well-separated steps that make the change easier to review.

### Format

We follow the [Conventional Commits](https://www.conventionalcommits.org) format:

```
<type>[optional scope]: commit title goes here (all lowercase)

[optional body]

Signed-off-by: Your Name <you@example.com>
```

**Types:**

- `build` - Changes that affect the build system or external dependencies
- `chore` - Routine maintenance or housekeeping changes (e.g., updating configs, dependencies, or scripts)
- `ci` - Changes to our CI configuration files and scripts
- `docs` - Documentation only changes
- `feat` - A new feature
- `fix` - A bug fix
- `perf` - A code change that improves performance
- `refactor` - A code change that neither fixes a bug nor adds a feature
- `revert` - Changes that restore old code or behavior
- `style` - Changes that do not affect the meaning of the code (white-space, formatting, etc)
- `test` - Adding missing tests or correcting existing tests

## Pull Request Guidelines

### Before Submitting

1. **Check for duplicates**: Review existing [issues](https://github.com/kubetail-org/kstack/issues) and [pull requests](https://github.com/kubetail-org/kstack/pulls)
2. **Run tests**: Execute `./scripts/lint.sh` and `./scripts/test.sh` (and `./scripts/test-e2e.sh` if your change touches cluster behavior)
3. **Update help text**: A new skill needs both a `SKILL.md.tmpl` and a matching `#### /<skill>` section in `README.md`, or `render_help` will exit non-zero during install
4. **Clean commits**: Ensure each commit is minimal, focused, and follows our [commit format](https://www.conventionalcommits.org)

### PR Title Format

Add an emoji to indicate the PR type:

- 🎣 Bug fix
- 🐋 New feature
- 📜 Documentation
- ✨ General improvement

### PR Description

Your PR should include:

- Link to related issue: `Fixes #123`
- **Summary**: Explain the goal of your PR
- **Key Changes**: List the specific key changes made

### PR Checklist

- [ ] Add the correct emoji to the PR title
- [ ] Related issue linked above, if any
- [ ] Commit messages use [conventional commit](https://www.conventionalcommits.org) format
- [ ] Changes are minimal and focused

## Branch Naming Guidelines

Use descriptive branch names. As a suggestion, you can use this pattern:

```
<type>/<short-description>
```

## Editor Configuration

### AI-Assisted Editors

For AI-assisted editors like Claude Code, Codex, Cursor, or GitHub Copilot, refer to the [`CLAUDE.md`](./CLAUDE.md) file for comprehensive guidance on this codebase's architecture and conventions.

### Visual Studio Code

Recommended extensions:
- **ShellCheck**: `timonwong.shellcheck`
- **Bats**: `jetmartin.bats`
- **EditorConfig**: `EditorConfig.EditorConfig`

## Bots and Automation

### GitHub Actions

Our CI pipeline (`.github/workflows/ci.yml`) runs four jobs on every pull request:

- **lint** — shellchecks all shipped shell (`scripts/install`, `src/bin/`, `src/lib/`, `scripts/*.sh`, plus selected test helpers)
- **bats** — runs `scripts/test.sh` on Linux, macOS, and Windows (amd64+arm64)
- **bats-e2e** — runs `scripts/test-e2e.sh` against a kind cluster on Linux amd64 (required status check)

You can see the status of these checks in your PR. If any checks fail, review the logs and fix the issues before requesting a review.

### CLA Assistant

If this is your first contribution, our [CLA (Contributor License Agreement)](https://cla-assistant.io/) assistant will prompt you to sign the CLA when you create your pull request. This is a one-time requirement.

## AI Policy

As a contributor you're encouraged to use AI tools in your workflow just as you would use classic tools such as search engines, language servers, linters, debuggers, documentation, or books. These tools are an invaluable resource and can help you write better code and explore ideas more efficiently.

That said, AI tools are different than classic tools because they can blur the line between helping you to do the work and doing the work for you. And when that line becomes blurry, it can limit opportunities to build the deep understanding that comes from writing and reasoning through code yourself.

As an open source project, kstack is not only committed to building a user-friendly, AI-powered K8s monitoring toolkit but also to helping our contributors grow as engineers. We invest a lot of time and effort into code quality, thoughtful reviews, and well-defined engineering specs. We do so happily because we enjoy it but also because it's our responsibility to the community.

In return, we ask that contributions be authored by you. While AI tools can support your workflow, submitted code should reflect your own understanding and intent. To keep our focus on meaningful collaboration within the community, we do not accept contributions authored entirely by llms.

When you use an AI tool, include an Assisted-by tag in the following format:

```
Assisted-by: AGENT_NAME:MODEL_VERSION
```

Where:

    `AGENT_NAME` is the name of the AI tool or framework
    `MODEL_VERSION` is the specific model version used

Example:

```
git commit -a -s --trailer "Assisted-by: Claude:claude-opus-4.7" -m "<message>"
```

## Community

We'd love to hear from you! Here's how to connect with the kstack community.

### Communication Channels

- **[Discord](https://discord.gg/CmsmWAVkvX)**: Join for real-time discussions, questions, and community chat
- **[Slack](https://kubernetes.slack.com/archives/C08SHG1GR37)**: Connect with us on the Kubernetes workspace

### Code of Conduct

Please read and follow our [Code of Conduct](https://github.com/kubetail-org/.github/blob/main/CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inclusive environment for all contributors.

---

Thanks for contributing to kstack!
