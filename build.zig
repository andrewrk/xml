const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_module = b.addModule("xml", .{
        .root_source_file = b.path("Xml.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "xml",
        .root_module = main_module,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_module = main_module,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
