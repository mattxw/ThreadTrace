SWIFT := swift

.PHONY: build test demo lint format

build:
	$(SWIFT) build

test:
	$(SWIFT) test

demo:
	$(SWIFT) run ThreadTraceDemo

lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --strict; \
	else \
		echo "SwiftLint is not installed; skipping. Install it with: brew install swiftlint"; \
	fi
	$(SWIFT) format lint --strict --recursive Sources Tests Examples Package.swift

format:
	$(SWIFT) format format --in-place --recursive Sources Tests Examples Package.swift
