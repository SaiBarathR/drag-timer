# Drag Timer – Developer shortcuts
# Requires: full Xcode (not just Command Line Tools)
#
# Usage:
#   make          - build debug and run the app
#   make run      - build debug and run the app
#   make build    - build a release app bundle into dist/
#   make test     - run the full test suite
#   make clean    - remove build artefacts

DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null)
XCODE_PATH     = /Applications/Xcode.app/Contents/Developer
SWIFT          = swift

# Auto-promote to full Xcode if CLT is currently active.
ifeq ($(findstring CommandLineTools,$(DEVELOPER_DIR)),CommandLineTools)
  ifneq ($(wildcard $(XCODE_PATH)),)
    DEVELOPER_DIR = $(XCODE_PATH)
  endif
endif

export DEVELOPER_DIR

.PHONY: all run build test clean

all: run

## Build (debug) and launch the app directly.
run:
	@echo "→ Building debug binary…"
	$(SWIFT) build --product DragTimer
	@echo "→ Launching Drag Timer…"
	$$($(SWIFT) build --product DragTimer --show-bin-path)/DragTimer

## Package a universal release app bundle into dist/.
build:
	@echo "→ Building universal release app bundle…"
	./Scripts/build-app.sh
	@echo "→ Opening app…"
	open "dist/Drag Timer.app"

## Run the full XCTest suite.
test:
	@echo "→ Running tests…"
	$(SWIFT) build
	$(SWIFT) test
	$(SWIFT) run DragTimer --self-test

## Remove all build artefacts.
clean:
	@echo "→ Cleaning build artefacts…"
	rm -rf .build dist
	@echo "Done."

