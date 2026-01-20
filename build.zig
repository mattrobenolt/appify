const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const panic = std.debug.panic;
const Allocator = mem.Allocator;

const GhosttyXCFrameworkTarget = enum { native, universal };

const GhosttySteps = struct {
    install_root_step: *std.Build.Step,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .macos) @panic("appify macOS build only supports macOS targets.");
    const optimize = b.standardOptimizeOption(.{});

    const ghostty_xcframework_target = b.option(
        GhosttyXCFrameworkTarget,
        "ghostty-xcframework-target",
        "Ghostty xcframework target (native or universal).",
    ) orelse .native;

    const exe = addAppifyExecutable(b, target, optimize);
    b.installArtifact(exe);

    addRunStep(b, exe);
    addTestStep(b, exe);

    const ghostty_steps = addGhosttySteps(b, ghostty_xcframework_target, optimize);
    addMacosSteps(b, optimize, ghostty_steps.install_root_step, exe);
}

fn addAppifyExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "appify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
}

fn addRunStep(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn addTestStep(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn addGhosttySteps(
    b: *std.Build,
    ghostty_xcframework_target: GhosttyXCFrameworkTarget,
    optimize: std.builtin.OptimizeMode,
) GhosttySteps {
    const ghostty_dep = b.dependency("ghostty", .{
        .@"version-string" = "0.0.0",
    });

    // Patch Ghostty in-place until the config-load API is upstreamed.
    const ghostty_target_arg = @tagName(ghostty_xcframework_target);

    const ghostty_capi_path = ghostty_dep.path("src/config/CApi.zig").getPath(b);
    const needs_ghostty_patch = !fileContains(
        b.allocator,
        ghostty_capi_path,
        "ghostty_config_load_file",
    );
    var ghostty_patch_step: ?*std.Build.Step = null;
    if (needs_ghostty_patch) {
        const ghostty_patch = b.addSystemCommand(&.{
            "patch",
            "-p1",
            "-i",
            b.pathFromRoot("patches/ghostty-config-load-file.patch"),
        });
        ghostty_patch.setCwd(ghostty_dep.path("."));
        ghostty_patch_step = &ghostty_patch.step;
    }

    const ghostty_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "-Dapp-runtime=none",
        "-Dversion-string=0.0.0",
        "-Demit-macos-app=false",
        "-Demit-xcframework=true",
        "-Di18n=false",
        b.fmt("-Doptimize={s}", .{@tagName(optimize)}),
        b.fmt("-Dxcframework-target={s}", .{ghostty_target_arg}),
    });
    if (ghostty_patch_step) |step| ghostty_cmd.step.dependOn(step);
    ghostty_cmd.setCwd(ghostty_dep.path("."));
    ghostty_cmd.expectExitCode(0);
    ghostty_cmd.addFileInput(ghostty_dep.path("build.zig"));
    ghostty_cmd.addFileInput(ghostty_dep.path("build.zig.zon"));
    ghostty_cmd.addFileInput(ghostty_dep.path("src/config/CApi.zig"));
    ghostty_cmd.addFileInput(ghostty_dep.path("include/ghostty.h"));
    ghostty_cmd.addFileInput(b.path("patches/ghostty-config-load-file.patch"));
    // Keep the Ghostty build step cacheable by declaring its inputs.
    addRunFileInputsForDir(
        b,
        ghostty_cmd,
        ghostty_dep.path("src").getPath(b),
        &.{},
    );
    addRunFileInputsForDir(
        b,
        ghostty_cmd,
        ghostty_dep.path("include").getPath(b),
        &.{},
    );

    const ghostty_install = b.addInstallDirectory(.{
        .source_dir = ghostty_dep.path("macos/GhosttyKit.xcframework"),
        .install_dir = .prefix,
        .install_subdir = "GhosttyKit.xcframework",
    });
    ghostty_install.step.dependOn(&ghostty_cmd.step);

    const install_prefix = b.getInstallPath(.prefix, "");
    const install_prefix_abs = if (fs.path.isAbsolute(install_prefix))
        install_prefix
    else
        b.pathFromRoot(install_prefix);
    const zig_out_abs = b.pathFromRoot("zig-out");
    const ghostty_xcframework_src = b.fmt("{s}/GhosttyKit.xcframework", .{install_prefix_abs});
    const ghostty_xcframework_dest = b.pathFromRoot("zig-out/GhosttyKit.xcframework");
    const ghostty_install_root_step: *std.Build.Step = if (std.mem.eql(u8, install_prefix_abs, zig_out_abs))
        &ghostty_install.step
    else blk: {
        // Xcode project references zig-out directly; mirror the xcframework there.
        const copy_step = CopyDirStep.create(
            b,
            .{ .cwd_relative = ghostty_xcframework_src },
            .{ .cwd_relative = ghostty_xcframework_dest },
        );
        copy_step.step.dependOn(&ghostty_install.step);
        break :blk &copy_step.step;
    };

    const ghostty_step = b.step(
        "ghostty-lib",
        "Build GhosttyKit.xcframework.",
    );
    ghostty_step.dependOn(&ghostty_install.step);

    return .{ .install_root_step = ghostty_install_root_step };
}

fn addMacosSteps(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    ghostty_install_root_step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
) void {
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
        "-destination",
        "generic/platform=macOS",
    });
    // Use a build-cache output directory so Zig can skip xcodebuild when inputs are unchanged.
    const xcodebuild_output_dir = xcodebuild_cmd.addPrefixedOutputDirectoryArg(
        "CONFIGURATION_BUILD_DIR=",
        "appify-build",
    );
    xcodebuild_cmd.setCwd(b.path("macos/appify"));
    xcodebuild_cmd.step.dependOn(ghostty_install_root_step);
    xcodebuild_cmd.expectExitCode(0);
    xcodebuild_cmd.addFileInput(.{
        .cwd_relative = b.pathFromRoot("zig-out/GhosttyKit.xcframework/Info.plist"),
    });
    addRunFileInputsForDir(
        b,
        xcodebuild_cmd,
        b.pathFromRoot("macos/appify"),
        &.{
            ".swift",
            ".plist",
            ".xcconfig",
            ".entitlements",
            ".pbxproj",
            ".xcscheme",
            ".xcworkspacedata",
            ".strings",
            ".storyboard",
            ".xib",
            ".json",
            ".png",
            ".jpg",
            ".jpeg",
            ".pdf",
        },
    );
    macos_step.dependOn(&xcodebuild_cmd.step);

    const appify_app_dir = xcodebuild_output_dir.join(b.allocator, "appify.app") catch @panic("OOM");
    const template_cmd = b.addSystemCommand(&.{
        "tar",
        "-cf",
    });
    // Pack the built app into a tarball, then embed it via a generated Zig module.
    const template_tar = template_cmd.addOutputFileArg("appify-template.tar");
    template_cmd.addArgs(&.{"-C"});
    template_cmd.addDirectoryArg(appify_app_dir);
    template_cmd.addArg(".");
    template_cmd.addFileInput(appify_app_dir.join(b.allocator, "Contents/MacOS/appify") catch @panic("OOM"));
    template_cmd.addFileInput(appify_app_dir.join(b.allocator, "Contents/Info.plist") catch @panic("OOM"));
    template_cmd.step.dependOn(&xcodebuild_cmd.step);

    const template_files = b.addWriteFiles();
    _ = template_files.addCopyFile(template_tar, "appify-template.tar");
    const template_zig = template_files.add(
        "appify_template.zig",
        "pub const data = @embedFile(\"appify-template.tar\");\n",
    );
    exe.step.dependOn(&template_files.step);

    const template_module = b.addModule("template_tar", .{
        .root_source_file = template_zig,
    });
    exe.root_module.addImport("template_tar", template_module);
}

fn fileContains(gpa: Allocator, path: []const u8, needle: []const u8) bool {
    const file = if (fs.path.isAbsolute(path))
        fs.openFileAbsolute(path, .{})
    else
        fs.cwd().openFile(path, .{});
    var handle = file catch |err| {
        panic("unable to open '{s}': {s}", .{ path, @errorName(err) });
    };
    defer handle.close();

    const stat = handle.stat() catch |err| {
        panic("unable to stat '{s}': {s}", .{ path, @errorName(err) });
    };
    if (stat.size == 0) return false;

    var buffer: [4096]u8 = undefined;
    var file_reader = handle.reader(&buffer);
    const reader = &file_reader.interface;

    const contents = reader.readAlloc(gpa, stat.size) catch |err| {
        panic("unable to read '{s}': {s}", .{ path, @errorName(err) });
    };
    defer gpa.free(contents);
    return mem.indexOf(u8, contents, needle) != null;
}

fn addRunFileInputsForDir(
    b: *std.Build,
    run: *std.Build.Step.Run,
    root_path: []const u8,
    extensions: []const []const u8,
) void {
    const dir = if (fs.path.isAbsolute(root_path))
        fs.openDirAbsolute(root_path, .{ .iterate = true })
    else
        fs.cwd().openDir(root_path, .{ .iterate = true });
    var handle = dir catch |err| {
        panic("unable to open '{s}': {s}", .{ root_path, @errorName(err) });
    };
    defer handle.close();

    var walker = handle.walk(b.allocator) catch @panic("OOM");
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch |err| {
            panic("unable to walk '{s}': {s}", .{ root_path, @errorName(err) });
        } orelse break;

        if (entry.kind != .file) continue;
        if (extensions.len != 0 and !hasExtension(entry.path, extensions)) continue;

        const full_path = b.pathJoin(&.{ root_path, entry.path });
        run.addFileInput(.{ .cwd_relative = full_path });
    }
}

fn hasExtension(path: []const u8, extensions: []const []const u8) bool {
    for (extensions) |ext| {
        if (mem.endsWith(u8, path, ext)) return true;
    }
    return false;
}

const CopyDirStep = struct {
    step: std.Build.Step,
    source_dir: std.Build.LazyPath,
    dest_dir: std.Build.LazyPath,

    pub fn create(
        b: *std.Build,
        source_dir: std.Build.LazyPath,
        dest_dir: std.Build.LazyPath,
    ) *CopyDirStep {
        const step = b.allocator.create(CopyDirStep) catch @panic("OOM");
        step.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "copy GhosttyKit.xcframework",
                .owner = b,
                .makeFn = make,
            }),
            .source_dir = source_dir.dupe(b),
            .dest_dir = dest_dir.dupe(b),
        };
        source_dir.addStepDependencies(&step.step);
        return step;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const b = step.owner;
        const self: *CopyDirStep = @fieldParentPtr("step", step);
        step.clearWatchInputs();

        const src_path = self.source_dir.getPath3(b, step);
        const dest_path = self.dest_dir.getPath3(b, step);

        const src = try src_path.toString(b.allocator);
        defer b.allocator.free(src);
        const dest = try dest_path.toString(b.allocator);
        defer b.allocator.free(dest);

        try copyDirTree(b.allocator, src, dest);
    }
};

fn copyDirTree(allocator: Allocator, source_path: []const u8, dest_path: []const u8) !void {
    try deleteTreePath(dest_path);
    if (fs.path.isAbsolute(dest_path)) {
        try ensureDirAbsolute(dest_path);
    } else {
        try fs.cwd().makePath(dest_path);
    }

    var source_dir = try openDirPath(source_path, true);
    defer source_dir.close();
    var dest_dir = try openDirPath(dest_path, false);
    defer dest_dir.close();

    try copyDirContents(allocator, source_dir, dest_dir);
}

fn copyDirContents(allocator: Allocator, source_dir: fs.Dir, dest_dir: fs.Dir) !void {
    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                try dest_dir.makePath(entry.path);
            },
            .file => {
                try ensureParentDir(dest_dir, entry.path);
                try source_dir.copyFile(entry.path, dest_dir, entry.path, .{});
            },
            .sym_link => {
                try ensureParentDir(dest_dir, entry.path);
                var buf: [fs.max_path_bytes]u8 = undefined;
                const target = try source_dir.readLink(entry.path, &buf);
                dest_dir.symLink(target, entry.path, .{}) catch |err| {
                    if (err != error.PathAlreadyExists) return err;
                };
            },
            else => {},
        }
    }
}

fn ensureParentDir(dir: fs.Dir, path: []const u8) !void {
    const parent = fs.path.dirname(path) orelse return;
    try dir.makePath(parent);
}

fn ensureDirAbsolute(path: []const u8) !void {
    if (!fs.path.isAbsolute(path)) return error.BadPathName;
    fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        error.FileNotFound => {
            const parent = fs.path.dirname(path) orelse return err;
            try ensureDirAbsolute(parent);
            try fs.makeDirAbsolute(path);
        },
        else => return err,
    };
}

fn openDirPath(path: []const u8, iterate: bool) !fs.Dir {
    const opts: fs.Dir.OpenOptions = .{ .iterate = iterate };
    return if (fs.path.isAbsolute(path))
        fs.openDirAbsolute(path, opts)
    else
        fs.cwd().openDir(path, opts);
}

fn deleteTreePath(path: []const u8) !void {
    if (fs.path.isAbsolute(path)) {
        fs.deleteTreeAbsolute(path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
        return;
    }

    fs.cwd().deleteTree(path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}
