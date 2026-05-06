# scripts/

Dev scripts. The Makefile at the repo root is a thin facade over these — every target shells out to a script here.

## `install`

The installer. Handles all three modes (dev, `--local`, `--global`).

- **Dev mode** (`./scripts/install` or `make install`) renders from this checkout into `<repo>/.kstack/` and `<repo>/.<agent>/skills/`.
- **Managed modes** (`--local`, `--global`) are invoked by the hosted bootstrap (`scripts/bootstrap.sh`) after it clones an upstream checkout, or by `$ROOT_DIR/bin/upgrade` on re-run. Both maintain their own `upstream/` checkout and never render from the invoker's tree.

## `bootstrap.sh`

Curl-pipe bootstrap hosted at `https://kubestack.xyz/install.sh`. Resolves the latest tagged release, clones a kstack-owned checkout (at `~/.config/kstack/upstream/` for global installs or `$PWD/.kstack/upstream/` for `--local`), then execs `$UPSTREAM_DIR/scripts/install`.

`scripts/bootstrap.sh` is the source of truth. A verbatim copy lives in the `kubetail-website` repo's static assets (served at the public URL). **When you edit `scripts/bootstrap.sh`, copy the updated file into `kubetail-website` and ship it.** There is no automated sync.

Treat edits here like edits to a release artifact: they affect every new global or local install the moment the website redeploys, so land them deliberately.

## `clean.sh`

Wipes dev-mode install artifacts (rendered skill directories, `.kstack/`, legacy `.build/`) so you can re-run `make install` against a clean tree. Development-only; only touches gitignored paths.

## `lint.sh`, `test.sh`, `test-e2e.sh`, `test-evals.sh`

Dev tooling — see `CLAUDE.md` for the full descriptions and CI invocations.
