# Build configuration
# -------------------

APP_NAME := $(shell grep -Eo 'app: :\w*' mix.exs | cut -d ':' -f 3)
APP_VERSION := $(shell grep -Eo 'version: "[0-9\.]*"' mix.exs | cut -d '"' -f 2)
GIT_REVISION := $(shell git rev-parse HEAD)
DOCKER_IMAGE_TAG ?= $(APP_VERSION)
DOCKER_REGISTRY ?=
DOCKER_LOCAL_IMAGE:= $(APP_NAME):$(DOCKER_IMAGE_TAG)
DOCKER_REMOTE_IMAGE:= $(DOCKER_REGISTRY)/$(DOCKER_LOCAL_IMAGE)

# Introspection targets
# ---------------------

.PHONY: help
help: header targets

.PHONY: header
header:
	@echo "\033[34mEnvironment\033[0m"
	@echo "\033[34m---------------------------------------------------------------\033[0m"
	@printf "\033[33m%-23s\033[0m" "APP_NAME"
	@printf "\033[35m%s\033[0m" $(APP_NAME)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "APP_VERSION"
	@printf "\033[35m%s\033[0m" $(APP_VERSION)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "GIT_REVISION"
	@printf "\033[35m%s\033[0m" $(GIT_REVISION)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "DOCKER_IMAGE_TAG"
	@printf "\033[35m%s\033[0m" $(DOCKER_IMAGE_TAG)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "DOCKER_REGISTRY"
	@printf "\033[35m%s\033[0m" $(DOCKER_REGISTRY)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "DOCKER_LOCAL_IMAGE"
	@printf "\033[35m%s\033[0m" $(DOCKER_LOCAL_IMAGE)
	@echo ""
	@printf "\033[33m%-23s\033[0m" "DOCKER_REMOTE_IMAGE"
	@printf "\033[35m%s\033[0m" $(DOCKER_REMOTE_IMAGE)
	@echo "\n"

.PHONY: targets
targets:
	@echo "\033[34mTargets\033[0m"
	@echo "\033[34m---------------------------------------------------------------\033[0m"
	@perl -nle'print $& if m{^[a-zA-Z_-\d]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

# Build targets
# -------------

.PHONY: prepare
prepare: ## Install Elixir dependencies
	mix deps.get

.PHONY: build
build: ## Build a Docker image for the OTP release
	docker build --rm --tag $(DOCKER_LOCAL_IMAGE) .

.PHONY: push
push: ## Push the Docker image to the registry
	docker tag $(DOCKER_LOCAL_IMAGE) $(DOCKER_REMOTE_IMAGE)
	docker push $(DOCKER_REMOTE_IMAGE)

# Development targets
# -------------------

.PHONY: run
run: ## Run the server in an IEx shell
	iex -S mix phx.server

.PHONY: dependencies
dependencies: ## Install Elixir dependencies
	mix deps.get

.PHONY: test
test: ## Run the test suite
	mix test

# Check, lint and format targets
# ------------------------------

.PHONY: check
check: check-format check-unused-dependencies check-dependencies-security check-code-security check-static-typing check-code-coverage ## Run various checks on source files

.PHONY: check-code-coverage
check-code-coverage:
	mix coveralls

.PHONY: check-dependencies-security
check-dependencies-security:
	mix deps.audit

.PHONY: check-code-security
check-code-security:
	mix sobelow --config

.PHONY: check-format
check-format:
	mix format --check-formatted

.PHONY: check-unused-dependencies
check-unused-dependencies:
	mix deps.unlock --check-unused

.PHONY: check-static-typing
check-static-typing:
	mix dialyzer

.PHONY: format
format: ## Format Elixir source files
	mix format

.PHONY: lint
lint: lint-elixir ## Lint source files

.PHONY: lint-elixir
lint-elixir:
	mix compile --warnings-as-errors --force
	mix credo --strict