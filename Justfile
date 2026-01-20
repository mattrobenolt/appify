default:
    @just --list

build:
    zig build

build-release:
    zig build -Doptimize=ReleaseFast

fmt:
    zig fmt src build.zig
    swift-format format --in-place --recursive macos

fmt-check:
    zig fmt --check src build.zig
    swift-format lint --recursive macos

lint: fmt-check
    zlint

test:
    zig build test --summary all

run *args:
    zig build run -- {{ args }}

clean:
    rm -rf zig-out .zig-cache
