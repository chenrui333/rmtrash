bin = $(shell basename $(CURDIR))
version = $(shell git describe --tags --abbrev=0)

.PHONY: deps
deps:
	swift package update

.PHONY: run
run:
	swift run

.PHONY: test
test:
	swift test

.PHONY: build
build:
	swift build -c release

.PHONY: build-universal
build-universal:
	swift build --configuration release --arch x86_64
	swift build --configuration release --arch arm64
	lipo -create .build/x86_64-apple-macosx/release/$(bin) .build/arm64-apple-macosx/release/$(bin) -output .build/release/$(bin)

.PHONY: release
release: build
	mkdir -p .dist
	tar -czf .dist/$(bin)_$(version)_x86_64.tar.gz .build/x86_64-apple-macosx/release/$(bin)
	tar -czf .dist/$(bin)_$(version)_arm64.tar.gz .build/arm64-apple-macosx/release/$(bin)
	tar -czf .dist/$(bin)_$(version)_universal.tar.gz .build/release/$(bin)

.PHONY: install
install: build
	mv .build/release/rmtrash /opt/homebrew/bin/rmtrash

.PHONY: clean
clean:
	rm -rf .build .dist
