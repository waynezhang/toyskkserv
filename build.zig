const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "toyskkserv",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const Dep = struct {
        name: []const u8,
        module: ?[]const u8 = null,
        link: ?[]const u8 = null,
    };
    const deps = [_]Dep{
        .{
            .name = "zig-cli",
        },
        .{
            .name = "zon_get_fields",
        },
        .{
            .name = "percent_encoding",
        },
        .{
            .name = "jdz_allocator",
        },
        .{
            .name = "network",
            .module = "network",
        },
        .{
            .name = "btree-zig",
            .module = "btree_c_zig",
            .link = "btree-zig",
        },
    };
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protest_mod = b.dependency("protest", .{ .target = target, .optimize = optimize }).module("protest");
    exe_unit_tests.root_module.addImport("protest", protest_mod);

    for (deps) |d| {
        const module = d.module orelse d.name;
        const dep = b.dependency(d.name, .{ .target = target, .optimize = optimize });
        const mod = dep.module(module);
        exe.root_module.addImport(d.name, mod);
        exe_unit_tests.root_module.addImport(d.name, mod);

        if (d.link) |l| {
            exe.linkLibrary(dep.artifact(l));
            exe_unit_tests.linkLibrary(dep.artifact(l));
        }
    }

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
