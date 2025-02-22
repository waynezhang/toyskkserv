const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = "toyskkserv";
    const deps = &[_]Dep{
        .{ .name = "zig-cli" },
        .{ .name = "zon_get_fields" },
        .{ .name = "percent_encoding" },
        .{ .name = "jdz_allocator" },
        .{ .name = "network" },
        .{ .name = "temp" },
        .{
            .name = "euc-jis-2004-zig",
            .module = "euc-jis-2004",
        },
        .{
            .name = "btree-zig",
            .module = "btree_c_zig",
            .link = "btree-zig",
        },
    };
    const test_deps = &[_]Dep{
        .{ .name = "protest" },
    };

    prepareExe(name, b, target, optimize, deps);

    const combined = deps ++ test_deps;
    prepareTestExe(b, target, optimize, combined);
}

fn getBuildOptions(b: *std.Build) *std.Build.Step.Options {
    const options = b.addOptions();

    const version = b.run(&[_][]const u8{
        "git",
        "describe",
        "--tags",
        "--abbrev=0",
    });
    options.addOption([]const u8, "version", std.mem.trim(u8, version, " \n"));

    const commit = b.run(&[_][]const u8{
        "git",
        "rev-parse",
        "HEAD",
    })[0..8];
    options.addOption([]const u8, "commit", std.mem.trim(u8, commit, " \n"));

    return options;
}

fn prepareExe(name: []const u8, b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, deps: []const Dep) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const opts = getBuildOptions(b);
    opts.addOption([]const u8, "name", name);
    exe.root_module.addOptions("build_options", opts);

    for (deps) |d| {
        const module = d.module orelse d.name;
        const dep = b.dependency(d.name, .{ .target = target, .optimize = optimize });
        const mod = dep.module(module);
        exe.root_module.addImport(d.name, mod);

        if (d.link) |l| {
            exe.linkLibrary(dep.artifact(l));
        }
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn prepareTestExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, deps: []const Dep) void {
    const exe = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    for (deps) |d| {
        const module = d.module orelse d.name;
        const dep = b.dependency(d.name, .{ .target = target, .optimize = optimize });
        const mod = dep.module(module);
        exe.root_module.addImport(d.name, mod);

        if (d.link) |l| {
            exe.linkLibrary(dep.artifact(l));
        }
    }
    const run_exe_unit_tests = b.addRunArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

const Dep = struct {
    name: []const u8,
    module: ?[]const u8 = null,
    link: ?[]const u8 = null,
};
