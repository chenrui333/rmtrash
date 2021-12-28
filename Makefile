all: build
	
build:
	clang -fobjc-arc -framework Foundation main.m -o rmtrash