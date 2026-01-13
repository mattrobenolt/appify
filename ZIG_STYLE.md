# Zig Style Guide

General Zig conventions and patterns. For alloconda-specific conventions, see [AGENTS.md](AGENTS.md).

## Zig Development

Always use `zigdoc` to discover APIs for the Zig standard library and any third-party dependencies.

Examples:
```bash
zigdoc std.fs
zigdoc std.posix.getuid
zigdoc ghostty-vt.Terminal
zigdoc vaxis.Window
```

## Common Zig Patterns

These patterns reflect current Zig APIs and may differ from older documentation.

**ArrayList:**
```zig
var list: std.ArrayList(u32) = .empty;
defer list.deinit(allocator);
try list.append(allocator, 42);
```

**HashMap/StringHashMap (unmanaged):**
```zig
var map: std.StringHashMapUnmanaged(u32) = .empty;
defer map.deinit(allocator);
try map.put(allocator, "key", 42);
```

**HashMap/StringHashMap (managed):**
```zig
var map: std.StringHashMap(u32) = .init(allocator);
defer map.deinit();
try map.put("key", 42);
```

**stdout/stderr Writer:**
```zig
var buf: [4096]u8 = undefined;
const writer = std.fs.File.stdout().writer(&buf);
defer writer.flush() catch {};
try writer.print("hello {s}\n", .{"world"});
```

**build.zig executable/test:**
```zig
b.addExecutable(.{
    .name = "foo",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
```

## Zig Code Style

**Naming:**
- `camelCase` for functions and methods
- `snake_case` for variables and parameters
- `PascalCase` for types, structs, and enums

**Type inference with anonymous literals:** Prefer explicit type annotation with `.` access:
```zig
// Struct initialization
const foo: Type = .{ .field = value };  // Good
const foo = Type{ .field = value };     // Avoid

// Function calls
var arena: std.heap.ArenaAllocator = .init(gpa);  // Good
var arena = std.heap.ArenaAllocator.init(gpa);    // Avoid
var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(gpa);    // Avoid
```

**Control flow as expressions:** Prefer `return switch`/`return if` over returns in each branch:
```zig
// Good - single return, switch is an expression
return switch (str[0]) {
    'D' => .debug,
    'L' => .info,
    else => .info,
};

// Avoid - repetitive returns in each branch
switch (str[0]) {
    'D' => return .debug,
    'L' => return .info,
    else => return .info,
}
```

**File structure:**
1. `//!` doc comment describing the module
2. `const Self = @This();` (for self-referential types)
3. `const log = std.log.scoped(.module_name);`

**Import aliases:** Create short aliases for modules and types used more than once:
```zig
const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const Allocator = mem.Allocator;  // Always alias this common type
```

**Functions:** Order methods as `init` → `deinit` → public API → private helpers

**Memory:** Pass allocators explicitly, use `errdefer` for cleanup on error

**Allocator argument order:** When a function takes an allocator, it should be the first argument (after comptime type parameters):
```zig
fn process(allocator: Allocator, data: []const u8) !void { ... }  // Good
fn process(data: []const u8, allocator: Allocator) !void { ... }  // Avoid
```

**Documentation:** Use `///` for public API, `//` for implementation notes. Always explain *why*, not just *what*.

**Tests:** Inline in the same file, register in src/main.zig test block

## Safety Conventions

Inspired by [TigerStyle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md).

**Assertions:**
- Add assertions that catch real bugs, not trivially true statements
- Focus on API boundaries and state transitions where invariants matter
- Good: bounds checks, null checks before dereference, state machine transitions
- Avoid: asserting something immediately after setting it, checking internal function arguments

**Function size:**
- Soft limit of 70 lines per function
- Centralize control flow (switch/if) in parent functions
- Push pure computation to helper functions

**Comments:**
- Explain *why* the code exists, not *what* it does
- Document non-obvious thresholds, timing values, protocol details
