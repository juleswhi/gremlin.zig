const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the parser dependency
    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    }).module("gremlin");

    const protobuf = ProtoGenStep.create(
        b,
        .{
            .proto_sources = b.path("proto"),
            .target = b.path("src/gen"),
        },
    );

    // Create binary
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the parser module
    exe.root_module.addImport("gremlin", gremlin_dep);
    exe.step.dependOn(&protobuf.step);

    b.installArtifact(exe);

    // Tests
    const lib_test = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the parser module to tests
    lib_test.root_module.addImport("gremlin", gremlin_dep);

    const run_tests = b.addRunArtifact(lib_test);
    run_tests.step.dependOn(&protobuf.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
