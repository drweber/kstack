# Fixture README

Used by render_help tests. Mirrors the real README's per-skill `<dt>/<dd>` structure so the extractor can be exercised on a stable, minimal input.

## Skills Reference

**Global flags** (supported by every skill):

| Flag              | Description                                    |
|-------------------|------------------------------------------------|
| `--context <ctx>` | Override the current kubeconfig context        |
| `--namespace <n>` | Scope the run to a single namespace            |
| `--json`          | Emit structured output                         |
| `--dry-run`       | Print commands without executing               |

---

### Demo

<dl>
<dt>

#### `/demo`

</dt>
<dd>

A fixture skill used by tests.

**What it does:** nothing real — it exists so install_funcs.bats and install_local.bats can verify man-page rendering against a known section.

**Options:**
- `--flag-one` — does one thing
- `--flag-two` — does another

</dd>
<dt>

#### `/demo-with-args <resource>`

</dt>
<dd>

Variant whose heading carries an argument, used to verify the renderer matches `/<skill>` followed by either a backtick or a space.

**Arguments:**
- `<resource>` — anything

</dd>
</dl>

---
