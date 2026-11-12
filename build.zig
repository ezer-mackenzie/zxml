const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zxml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zxml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_parser_tests = b.addRunArtifact(parser_tests);
    const json_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/json.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_json_tests = b.addRunArtifact(json_tests);
    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    const run_cli_tests = b.addRunArtifact(cli_tests);
    const report_metrics_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/report/metrics.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    const run_report_metrics_tests = b.addRunArtifact(report_metrics_tests);
    const report_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/report/report.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    const run_report_tests = b.addRunArtifact(report_tests);
    const reader_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/reader.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_reader_tests = b.addRunArtifact(reader_tests);
    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_json_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_report_metrics_tests.step);
    test_step.dependOn(&run_report_tests.step);
    test_step.dependOn(&run_reader_tests.step);
}
