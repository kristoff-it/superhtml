const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scripty = b.dependency("scripty", .{});
    const superhtml = b.addModule("superhtml", .{
        .root_source_file = b.path("src/root.zig"),
    });
    superhtml.addImport("scripty", scripty.module("scripty"));

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "nesting",
    });

    unit_tests.root_module.addImport("superhtml", superhtml);

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

    super_wasm_lsp.root_module.addImport("superhtml", superhtml);
    super_wasm_lsp.root_module.addImport("lsp", lsp.module("lsp"));
    super_wasm_lsp.root_module.addOptions("build_options", options);

    const wasm = b.step("wasm", "Generate a WASM build of the SuperHTML LSP for VSCode");
    const target_output = b.addInstallArtifact(super_wasm_lsp, .{
        .dest_dir = .{ .override = .{ .custom = "" } },
    });
    wasm.dependOn(&target_output.step);

    const afl_fuzz_name = b.fmt("superfuzz-afl{s}", .{target.result.exeFileExt()});
    const afl_fuzz = b.addStaticLibrary(.{
        .name = afl_fuzz_name,
        .root_source_file = b.path("src/fuzz/afl.zig"),
        // .target = b.resolveTargetQuery(.{ .ofmt = .c }),
        .target = target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    afl_fuzz.root_module.addImport("superhtml", superhtml);
    afl_fuzz.root_module.stack_check = false; // not linking with compiler-rt
    afl_fuzz.root_module.link_libc = true; // afl runtime depends on libc
    _ = afl_fuzz.getEmittedBin(); // hack around build system bug

    const afl_clang_fast_path = b.findProgram(
        &.{ "afl-clang-fast", "afl-clang" },
        if (b.option([]const u8, "afl-path", "Path to AFLplusplus")) |afl_path|
            &.{afl_path}
        else
            &.{},
    ) catch "afl-clang-fast";

    const fuzz = b.step("fuzz", "Generate an executable for AFL++ (persistent mode) plus extra tooling");
    const run_afl_clang_fast = b.addSystemCommand(&.{
        afl_clang_fast_path,
        "-o",
    });

    const prog_exe = run_afl_clang_fast.addOutputFileArg(afl_fuzz_name);
    run_afl_clang_fast.addFileArg(b.path("src/fuzz/afl.c"));
    // run_afl_clang_fast.addFileArg(afl_fuzz.getEmittedBin());
    // run_afl_clang_fast.addArg("-I/Users/kristoff/zig/0.13.0/files/lib/");
    run_afl_clang_fast.addFileArg(afl_fuzz.getEmittedLlvmBc());
    fuzz.dependOn(&b.addInstallBinFile(prog_exe, afl_fuzz_name).step);

    const super_fuzz = b.addExecutable(.{
        .name = "superfuzz",
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    super_fuzz.root_module.addImport("superhtml", superhtml);
    fuzz.dependOn(&b.addInstallArtifact(super_fuzz, .{}).step);

    const supergen = b.addExecutable(.{
        .name = "supergen",
        .root_source_file = b.path("src/fuzz/astgen.zig"),
        .target = target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    supergen.root_module.addImport("superhtml", superhtml);
    fuzz.dependOn(&b.addInstallArtifact(supergen, .{}).step);

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
