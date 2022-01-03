const std = @import("std");

pub fn build(builder: *std.build.Builder) void {
    const target = builder.standardTargetOptions(.{});
    const mode = builder.standardReleaseOptions();

    const exe = builder.addExecutable("zig", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.linkSystemLibrary("memflow_ffi"); // libmemflow_ffi.a
    const builder_options = builder.addOptions();
    exe.addOptions("build_options", builder_options);
    // Variable name for passing the memflow connector inventory path to compile in
    const inv_path_var = "MEMFLOW_CONNECTOR_INVENTORY_PATHS";
    // First try to use the inventory path defined as a compilation option
    const inv_path_opt = builder.option([]const u8, inv_path_var, "Memflow inventory connector path");
    // Secondly try to use the path passed as an environment variable
    const inv_path = inv_path_opt orelse std.os.getenv(inv_path_var); // FIXME: this does not work on Windows
    builder_options.addOption(
        ?[]const u8,
        "memflow_connector_inventory_paths",
        inv_path,
    );

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(builder.getInstallStep());
    if (builder.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = builder.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var exe_tests = builder.addTest("src/main.zig");
    exe_tests.setBuildMode(mode);

    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
