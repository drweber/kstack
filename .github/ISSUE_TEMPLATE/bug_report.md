---
name: Bug report
about: A skill misbehaved, the installer failed, or something doesn't match the docs
title: ''
labels: needs-triage
assignees: ''
---

<!-- Delete any section that doesn't apply. -->

## What happened

<!-- What you ran and what came back. Paste the skill's output if it's short. -->

## What you expected instead

## Where it went wrong

<!-- A skill (/cluster-status, /logs, …), the installer, the update check,
     the uninstaller — whichever applies. -->

## Environment

- **kstack version:** <!-- global: cat ~/.config/kstack/manifest/version
                          local/dev: cat .kstack/manifest/version -->
- **Install mode:** <!-- global (curl … | bash) / local (--local) / dev (make install from a clone) -->
- **Agent CLI + version:** <!-- claude, codex, opencode, cursor, factory, slate, kiro, hermes, pi -->
- **OS + arch:**
- **kubectl / cluster:** <!-- output of `kubectl version` -->

## Steps to reproduce

1.
2.

## Anything else

<!-- Logs, a minimal manifest that triggers it, a screenshot.

     Skill output can carry real cluster detail — namespaces, workload names,
     node names, labels. Please redact anything you'd rather not publish. -->
