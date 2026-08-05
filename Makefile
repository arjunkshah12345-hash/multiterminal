.PHONY: verify test build run app install dmg icon

verify:
	swift test
	swiftc Sources/multiterminal/LayoutMath.swift Sources/multiterminal/TerminalEnvironment.swift tools/verify_layout.swift -o .build/layout-verify
	.build/layout-verify
	swift build -c release
	git diff --check

test:
	swift test

build:
	swift build -c release

run:
	swift run

app:
	sh tools/build_app.sh debug

install:
	sh tools/build_app.sh install release

dmg:
	sh tools/build_dmg.sh

icon:
	sh tools/build_icon.sh
