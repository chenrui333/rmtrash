all: build
	
build:
	swift package update
	swift build -c release