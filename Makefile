# Contributor dev entrypoint. Thin facade over scripts/ — each target
# shells out to a script that's also runnable directly.
#
# See CLAUDE.md for the full contributor guide.

.PHONY: install test test-e2e test-evals lint clean help

install:
	./scripts/install

test:
	./scripts/test.sh

test-e2e:
	./scripts/test-e2e.sh

test-evals:
	./scripts/test-evals.sh

lint:
	./scripts/lint.sh

clean:
	./scripts/clean.sh

help:
	@echo "Targets:"
	@echo "  install     dev-mode install (renders skills into <repo>/.<agent>/skills/)"
	@echo "  test        fast bats tiers (unit + integration)"
	@echo "  test-e2e    cluster-backed tier (requires kind + docker)"
	@echo "  test-evals  eval harness (requires ANTHROPIC_API_KEY + claude CLI)"
	@echo "  lint        shellcheck"
	@echo "  clean       remove dev-mode artifacts"
