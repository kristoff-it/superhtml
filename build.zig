const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version: Version = if (b.option(
        []const u8,
        "force-version",
        "When building the SuperHTML CLI tool force a specific version, bypassing 'git describe'",
    )) |v| .{ .commit = v } else getVersion(b);

    const scripty = b.dependency("scripty", .{});
    const superhtml = b.addModule("superhtml", .{
        .root_source_file = b.path("src/root.zig"),
    });
    superhtml.addImport("scripty", scripty.module("scripty"));

    const options = b.addOptions();
    const verbose_logging = b.option(bool, "log", "Enable verbose logging also in release modes") orelse false;
    const scopes = b.option([]const []const u8, "scope", "Enable this scope (all scopes are enabled when none is specified through this option), can be used multiple times") orelse &[0][]const u8{};
    options.addOption(bool, "verbose_logging", verbose_logging);
    options.addOption([]const []const u8, "enabled_scopes", scopes);
    options.addOption([]const u8, "version", version.string());
    options.addOption(Version.Kind, "version_kind", version);

    const folders = b.dependency("known-folders", .{});
    const lsp = b.dependency("zig-lsp-kit", .{});

    setupTestStep(b, target, superhtml);
    setupCliTool(b, target, optimize, options, superhtml, folders, lsp);
    setupWasmStep(b, optimize, options, superhtml, lsp);
    setupCheckStep(b, target, optimize, options, superhtml, folders, lsp);
    if (version == .tag) {
        setupReleaseStep(b, options, superhtml, folders, lsp);
    }

    if (b.option(
        bool,
        "fuzz",
        "Generate an executable for AFL++ (persistent mode) plus extra tooling",
    ) orelse false) {
        setupFuzzStep(b, target, superhtml);
    }
}

fn setupCheckStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    folders: *std.Build.Dependency,
    lsp: *std.Build.Dependency,
) void {
    const super_cli_check = b.addExecutable(.{
        .name = "superhtml",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    super_cli_check.root_module.addImport("superhtml", superhtml);
    super_cli_check.root_module.addImport(
        "known-folders",
        folders.module("known-folders"),
    );
    super_cli_check.root_module.addImport("lsp", lsp.module("lsp"));
    super_cli_check.root_module.addOptions("build_options", options);

    const check = b.step("check", "Check if the SuperHTML CLI compiles");
    check.dependOn(&super_cli_check.step);
}
fn setupTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    superhtml: *std.Build.Module,
) void {
    const test_step = b.step("test", "Run unit tests");

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "nesting",
    });

    unit_tests.root_module.addImport("superhtml", superhtml);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const fuzz_tests = b.addTest(.{
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "nesting",
    });

    fuzz_tests.root_module.addImport("superhtml", superhtml);
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);
}

fn setupFuzzStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    superhtml: *std.Build.Module,
) void {
    const afl = b.lazyImport(@This(), "zig-afl-kit") orelse return;
    const afl_obj = b.addObject(.{
        .name = "superfuzz-afl",
        .root_source_file = b.path("src/fuzz/afl.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });

    afl_obj.root_module.addImport("superhtml", superhtml);
    afl_obj.root_module.stack_check = false; // not linking with compiler-rt
    afl_obj.root_module.link_libc = true; // afl runtime depends on libc

    const afl_fuzz = afl.addInstrumentedExe(
        b,
        target,
        .ReleaseSafe,
        afl_obj,
    );
    b.getInstallStep().dependOn(&b.addInstallFile(afl_fuzz, "superfuzz-afl").step);

    const super_fuzz = b.addExecutable(.{
        .name = "superfuzz",
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });

    super_fuzz.root_module.addImport("superhtml", superhtml);
    b.installArtifact(super_fuzz);

    const supergen = b.addExecutable(.{
        .name = "supergen",
        .root_source_file = b.path("src/fuzz/astgen.zig"),
        .target = target,
        .optimize = .Debug,
    });

    supergen.root_module.addImport("superhtml", superhtml);
    b.installArtifact(supergen);
}

fn setupCliTool(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    folders: *std.Build.Dependency,
    lsp: *std.Build.Dependency,
) void {
    const super_cli = b.addExecutable(.{
        .name = "superhtml",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    super_cli.root_module.addImport("superhtml", superhtml);
    super_cli.root_module.addImport(
        "known-folders",
        folders.module("known-folders"),
    );
    super_cli.root_module.addImport("lsp", lsp.module("lsp"));
    super_cli.root_module.addOptions("build_options", options);

    const run_exe = b.addRunArtifact(super_cli);
    if (b.args) |args| run_exe.addArgs(args);
    const run_exe_step = b.step("run", "Run the SuperHTML CLI");
    run_exe_step.dependOn(&run_exe.step);

    b.installArtifact(super_cli);
}

fn setupWasmStep(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    lsp: *std.Build.Dependency,
) void {
    const wasm = b.step("wasm", "Generate a WASM build of the SuperHTML LSP for VSCode");
    const super_wasm_lsp = b.addExecutable(.{
        .name = "superhtml",
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        }),
        .optimize = optimize,
        .single_threaded = true,
        .link_libc = false,
    });

    super_wasm_lsp.root_module.addImport("superhtml", superhtml);
    super_wasm_lsp.root_module.addImport("lsp", lsp.module("lsp"));
    super_wasm_lsp.root_module.addOptions("build_options", options);

    const target_output = b.addInstallArtifact(super_wasm_lsp, .{
        .dest_dir = .{ .override = .{ .custom = "" } },
    });
    wasm.dependOn(&target_output.step);
}

fn setupReleaseStep(
    b: *std.Build,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    folders: *std.Build.Dependency,
    lsp: *std.Build.Dependency,
) void {
    const release_step = b.step(
        "release",
        "Create releases for the SuperHTML CLI",
    );
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    for (targets) |t| {
        const release_target = b.resolveTargetQuery(t);

        const super_exe_release = b.addExecutable(.{
            .name = "superhtml",
            .root_source_file = b.path("src/cli.zig"),
            .target = release_target,
            .optimize = .ReleaseFast,
        });

        super_exe_release.root_module.addImport("superhtml", superhtml);
        super_exe_release.root_module.addImport(
            "known-folders",
            folders.module("known-folders"),
        );
        super_exe_release.root_module.addImport("lsp", lsp.module("lsp"));
        super_exe_release.root_module.addOptions("build_options", options);

        const target_output = b.addInstallArtifact(super_exe_release, .{
            .dest_dir = .{
                .override = .{
                    .custom = t.zigTriple(b.allocator) catch unreachable,
                },
            },
        });

        release_step.dependOn(&target_output.step);
    }
}

const Version = union(Kind) {
    tag: []const u8,
    commit: []const u8,
    // not in a git repo
    unknown,

    pub const Kind = enum { tag, commit, unknown };

    pub fn string(v: Version) []const u8 {
        return switch (v) {
            .tag, .commit => |tc| tc,
            .unknown => "unknown",
        };
    }
};
fn getVersion(b: *std.Build) Version {
    const git_path = b.findProgram(&.{"git"}, &.{}) catch return .unknown;
    var out: u8 = undefined;
    const git_describe = std.mem.trim(
        u8,
        b.runAllowFail(&[_][]const u8{
            git_path,            "-C",
            b.build_root.path.?, "describe",
            "--match",           "*.*.*",
            "--tags",
        }, &out, .Ignore) catch return .unknown,
        " \n\r",
    );

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => return .{ .tag = git_describe },
        2 => {
            // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = it.next() orelse unreachable;
            const commit_height = it.next() orelse unreachable;
            const commit_id = it.next() orelse unreachable;

            // Check that the commit hash is prefixed with a 'g'
            // (it's a Git convention)
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.panic("Unexpected `git describe` output: {s}\n", .{git_describe});
            }

            // The version is reformatted in accordance with
            // the https://semver.org specification.
            return .{
                .commit = b.fmt("{s}-dev.{s}+{s}", .{
                    tagged_ancestor,
                    commit_height,
                    commit_id[1..],
                }),
            };
        },
        else => std.debug.panic(
            "Unexpected `git describe` output: {s}\n",
            .{git_describe},
        ),
    }
}
