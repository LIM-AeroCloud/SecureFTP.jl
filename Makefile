EXEC:=julia

default: help

docs/Manifest.toml: docs/Project.toml
	${EXEC} --project=docs -e 'using Pkg; Pkg.instantiate()'

docs-instantiate:
	${EXEC} --project=docs -e 'using Pkg; Pkg.instantiate()'

docs: changelog
	${EXEC} --project=docs docs/make.jl

changelog: docs/Manifest.toml
	${EXEC} --project=docs release-scripts/changelog.jl

bump-version:
	${EXEC} --project=docs release-scripts/pre-release.jl

test:
	${EXEC} --project -e 'using Pkg; Pkg.test()'

pre-release: test bump-version docs

post-release:
	${EXEC} --project=docs release-scripts/post-release.jl

help:
	@echo "The following make commands are available:"
	@echo " - make changelog: update all links in CHANGELOG.md's footer"
	@echo " - make docs: build the documentation and update changelog links"
	@echo " - make test: run the tests"
	@echo " - make bump-version: set version to stable"
	@echo " - make pre-release: run tests, build docs, update changelog links, and bump version"
	@echo " - make post-release: increment minor version"

.PHONY: default docs-instantiate help changelog docs test bump-version pre-release post-release
