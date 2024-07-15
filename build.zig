const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mode = .{ .target = target, .optimize = optimize };

    const scripty = b.dependency("scripty", mode);
    const super = b.addModule("super", .{ .root_source_file = b.path("src/root.zig") });
    super.addImport("scripty", scripty.module("scripty"));

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "nesting",
    });

    unit_tests.root_module.addImport("super", super);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const super_cli = b.addExecutable(.{
        .name = "superhtml",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    const verbose_logging = b.option(bool, "log", "Enable verbose logging also in release modes") orelse false;
    const scopes = b.option([]const []const u8, "scope", "Enable this scope (all scopes are enabled when none is specified through this option), can be used multiple times") orelse &[0][]const u8{};
    const options = b.addOptions();
    options.addOption(bool, "verbose_logging", verbose_logging);
    options.addOption([]const []const u8, "enabled_scopes", scopes);

    const folders = b.dependency("known-folders", .{});
    const lsp = b.dependency("zig-lsp-kit", .{});

    super_cli.root_module.addImport("super", super);
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

    const super_cli_check = b.addExecutable(.{
        .name = "super",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    super_cli_check.root_module.addImport("super", super);
    super_cli_check.root_module.addImport(
        "known-folders",
        folders.module("known-folders"),
    );
    super_cli_check.root_module.addImport("lsp", lsp.module("lsp"));
    super_cli_check.root_module.addOptions("build_options", options);

    const check = b.step("check", "Check if the SuperHTML CLI compiles");
    check.dependOn(&super_cli_check.step);

    const release_step = b.step("release", "Create releases for the SuperHTML CLI");
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
            .name = "super",
            .root_source_file = b.path("src/cli.zig"),
            .target = release_target,
            .optimize = .ReleaseFast,
        });

        const release_mode = .{ .target = release_target, .optimize = .ReleaseFast };

        const scripty_release = b.dependency("scripty", release_mode);

        const super_release = b.addModule("super", .{
            .root_source_file = b.path("src/root.zig"),
        });

        super_release.addImport("scripty", scripty_release.module("scripty"));
        super_exe_release.root_module.addImport("super", super_release);
        super_exe_release.root_module.addImport(
            "known-folders",
            folders.module("known-folders"),
        );
        super_exe_release.root_module.addImport("lsp", lsp.module("lsp"));
        super_exe_release.root_module.addOptions("build_options", options);

        const target_output = b.addInstallArtifact(super_exe_release, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        release_step.dependOn(&target_output.step);
    }

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

    super_wasm_lsp.root_module.addImport("super", super);
    super_wasm_lsp.root_module.addImport("lsp", lsp.module("lsp"));
    super_wasm_lsp.root_module.addOptions("build_options", options);

    const wasm = b.step("wasm", "Generate a WASM build of the SuperHTML LSP for VSCode");
    const target_output = b.addInstallArtifact(super_wasm_lsp, .{
        .dest_dir = .{ .override = .{ .custom = "" } },
    });
    wasm.dependOn(&target_output.step);

    const super_fuzz_name = b.fmt("superfuzz{s}", .{target.result.exeFileExt()});
    const super_fuzz = b.addObject(.{
        .name = super_fuzz_name,
        .root_source_file = b.path("src/fuzz.zig"),
        // .target = b.resolveTargetQuery(.{ .cpu_model = .baseline }),
        .target = target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    super_fuzz.root_module.addImport("super", super);

    super_fuzz.root_module.stack_check = false; // not linking with compiler-rt
    super_fuzz.root_module.link_libc = true; // afl runtime depends on libc
    _ = super_fuzz.getEmittedBin(); // hack around build system bug

    const afl_clang_fast_path = b.findProgram(
        &.{ "afl-clang-fast", "afl-clang" },
        if (b.option([]const u8, "afl-path", "Path to AFLplusplus")) |afl_path|
            &.{afl_path}
        else
            &.{},
    ) catch "afl-clang-fast";

    const fuzz = b.step("fuzz", "Generate an executable to fuzz html/Parser");
    const run_afl_clang_fast = b.addSystemCommand(&.{
        afl_clang_fast_path,
        "-o",
    });
    // run_afl_clang_fast.setEnvironmentVariable("AFL_NO_FORKSRV", "1");

    const prog_exe = run_afl_clang_fast.addOutputFileArg(super_fuzz_name);
    run_afl_clang_fast.addFileArg(b.path("src/fuzz.c"));
    run_afl_clang_fast.addFileArg(super_fuzz.getEmittedLlvmBc());
    fuzz.dependOn(&b.addInstallBinFile(prog_exe, super_fuzz_name).step);

    const fuzz_tests = b.addTest(.{
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "nesting",
    });

    fuzz_tests.root_module.addImport("super", super);
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);
}
