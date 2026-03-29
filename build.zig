const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "freecell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("freecell.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.stack_size = 8 * 1024 * 1024 * 1024; // 8 GiB

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
