# Spec-driven engineering loop — entry points.
# Most engineers only need: `make doctor`, `make dry-run`, `make loop`.
SHELL := /bin/bash
SPEC  ?= specs/000-example

.DEFAULT_GOAL := help
.PHONY: help doctor selftest dry-run loop new-spec fmt gates \
        spec plan tasks implement review fix verify install uninstall clean

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

doctor: ## Report prerequisite + configuration status
	@bash scripts/doctor.sh

selftest: ## Dry-run the loop against the bundled example (no model calls)
	@bash loop/run.sh --dry-run --spec specs/000-example --yes

dry-run: ## Dry-run the loop against $(SPEC) (no model calls)
	@bash loop/run.sh --dry-run --spec "$(SPEC)" --yes

loop: ## Run the full loop against $(SPEC) (real model calls; opens a PR, never merges)
	@bash loop/run.sh --spec "$(SPEC)"

new-spec: ## Scaffold a new spec dir from templates: make new-spec SLUG=NNN-my-feature
	@test -n "$(SLUG)" || { echo "usage: make new-spec SLUG=NNN-my-feature"; exit 64; }
	@mkdir -p "specs/$(SLUG)"
	@cp specs/templates/spec.md "specs/$(SLUG)/spec.md"
	@cp specs/templates/prd.md  "specs/$(SLUG)/prd.md"
	@cp specs/templates/adr.md  "specs/$(SLUG)/adr-001.md"
	@echo "created specs/$(SLUG)/ — edit spec.md, then: make dry-run SPEC=specs/$(SLUG)"

fmt: ## Format the tree in place across detected stacks
	@stacks="$$(bash adapters/detect.sh .)"; \
	 for s in $$stacks; do echo "== fmt:$$s =="; bash adapters/stacks/$$s.sh fmt; done

gates: ## Run the check gates (lint typecheck test build securityscan) over detected stacks
	@stacks="$$(bash adapters/detect.sh .)"; \
	 if [ -z "$$stacks" ]; then echo "no stack detected; gates skip"; exit 0; fi; \
	 rc=0; for v in lint typecheck test build securityscan; do \
	   for s in $$stacks; do echo "== $$v:$$s =="; bash adapters/stacks/$$s.sh $$v || rc=1; done; \
	 done; exit $$rc

# --- single-stage helpers (interactive; require `claude` auth) ---------------
spec: ## Run the Specify stage interactively
	@claude "/spec-init Active spec: $(SPEC). Follow specs/constitution.md."
plan: ## Run the Plan stage interactively
	@claude "/plan Active spec: $(SPEC). Follow specs/constitution.md."
tasks: ## Run the Tasks stage interactively
	@claude "/tasks Active spec: $(SPEC). Follow specs/constitution.md."
implement: ## Run the Implement stage interactively
	@claude "/implement Active spec: $(SPEC). Follow specs/constitution.md."
review: ## Run the Review stage interactively
	@claude "/review Active spec: $(SPEC). Follow specs/constitution.md."
fix: ## Run the Fix stage interactively
	@claude "/fix Active spec: $(SPEC). Follow specs/constitution.md."
verify: ## Run the Verify stage interactively
	@claude "/verify Active spec: $(SPEC). Follow specs/constitution.md."

install: ## Check prerequisites and print plugin-install instructions
	@bash scripts/install.sh
uninstall: ## Print plugin-uninstall instructions
	@bash scripts/uninstall.sh

clean: ## Remove local run artifacts under .loop/
	@rm -rf .loop && echo "removed .loop/"
