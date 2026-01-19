const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .macos) @panic("appify macOS build only supports macOS targets.");
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    const ghostty_xcframework_target = b.option(
        enum { native, universal },
        "ghostty-xcframework-target",
        "Ghostty xcframework target (native or universal).",
    ) orelse .native;

    const exe = b.addExecutable(.{
        .name = "appify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the executable's
    // root module.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    const ghostty_dep = b.dependency("ghostty", .{});
    const ghostty_target_arg = switch (ghostty_xcframework_target) {
        .native => "native",
        .universal => "universal",
    };

    const ghostty_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "-Dapp-runtime=none",
        "-Demit-macos-app=false",
        "-Demit-xcframework=true",
        "-Di18n=false",
        b.fmt("-Doptimize={s}", .{@tagName(optimize)}),
        b.fmt("-Dxcframework-target={s}", .{ghostty_target_arg}),
    });
    ghostty_cmd.setCwd(ghostty_dep.path("."));

    const ghostty_install = b.addInstallDirectory(.{
        .source_dir = ghostty_dep.path("macos/GhosttyKit.xcframework"),
        .install_dir = .prefix,
        .install_subdir = "GhosttyKit.xcframework",
    });
    ghostty_install.step.dependOn(&ghostty_cmd.step);

    const ghostty_step = b.step(
        "ghostty-lib",
        "Build GhosttyKit.xcframework.",
    );
    ghostty_step.dependOn(&ghostty_install.step);

    const macos_step = b.step(
        "macos",
        "Build GhosttyKit.xcframework and appify.app",
    );
    const xcodebuild_config: []const u8 = if (optimize == .Debug) "Debug" else "Release";
    const xcodebuild_cmd = b.addSystemCommand(&.{
        "xcodebuild",
        "-scheme",
        "appify",
        "-configuration",
        xcodebuild_config,
        b.fmt("CONFIGURATION_BUILD_DIR={s}", .{b.getInstallPath(.prefix, "")}),
    });
    xcodebuild_cmd.setCwd(b.path("macos/appify"));
    xcodebuild_cmd.step.dependOn(&ghostty_install.step);
    macos_step.dependOn(&xcodebuild_cmd.step);

    const template_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\tar -cf "$1" -C "$2" . &&
        \\cat > "$3" <<'EOF'
        \\pub const data = @embedFile("appify-template.tar");
        \\EOF
        ,
        "--",
    });
    _ = template_cmd.addOutputFileArg("appify-template.tar");
    const appify_app_path = b.getInstallPath(.prefix, "appify.app");
    template_cmd.addDirectoryArg(.{ .cwd_relative = appify_app_path });
    template_cmd.addFileInput(.{
        .cwd_relative = b.getInstallPath(.prefix, "appify.app/Contents/MacOS/appify"),
    });
    const template_zig = template_cmd.addOutputFileArg("appify_template.zig");
    template_cmd.step.dependOn(&xcodebuild_cmd.step);
    exe.step.dependOn(&template_cmd.step);

    const template_module = b.addModule("template_tar", .{
        .root_source_file = template_zig,
    });
    exe.root_module.addImport("template_tar", template_module);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
