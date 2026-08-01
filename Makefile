build:
	swift build

test:
	swift run SpitterTests

lint:
	swift format lint --strict --recursive Sources Package.swift

check: build test lint

app:
	./build.sh

.PHONY: build test lint check app
