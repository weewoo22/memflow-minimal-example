const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const logger = std.log.scoped(.example);
pub const log_level: std.log.Level = .debug;

const mf = @import("./memflow.zig");

pub fn main() !void {
    const allocator = std.testing.allocator;

    var inventory: *mf.Inventory = undefined;
    var os_instance: mf.OsInstance = undefined;

    mf.log_init(mf.Level_Info);

    // Statically compiled directory path for memflow connector inventory
    const inv_scan_paths = build_options.memflow_connector_inventory_paths orelse {
        @compileError("The \"MEMFLOW_CONNECTOR_INVENTORY_PATHS\" build option or environment " ++
            "variable is required");
    };

    // Has the memflow connector inventory been given an initial scan path?
    var first_path = false;
    // Iterator for the different directory paths holding memflow connector plugins
    var inv_path_iter = std.mem.split(u8, inv_scan_paths, ";");

    // Loop through each given memflow connector directory
    while (inv_path_iter.next()) |path| {
        logger.debug("Adding memflow inventory path \"{s}\"", .{path});

        // Allocate and copy path to a new a null terminated string slice
        const path_str = try allocator.dupeZ(u8, path);
        defer allocator.free(path_str);

        // If this is the first path being added to the memflow connector inventory then use the
        // "scan_path" function to initialize a new connector inventory
        if (!first_path) {
            inventory = mf.inventory_scan_path(path_str) orelse {
                // If it returns null pointer treat this as an error
                return error.MemflowInventoryScanError;
            };
            // We're done scanning the initial plugin path
            first_path = true;
            // Skip to the next path now
            continue;
        }

        // Otherwise try to add an additional connector plugin to the inventory using "add_dir"
        try mf.tryError(
            mf.inventory_add_dir(inventory, path_str),
            error.MemflowInventoryScanError,
        );
    }

    // Create a new memflow connector instance from the current inventory of plugins (using KVM)
    var con_inst: mf.ConnectorInstance = undefined;
    try mf.tryError(
        mf.inventory_create_connector(
            inventory,
            "kvm",
            "",
            &con_inst,
        ),
        error.ConnectorCreationError,
    );

    // Now using the KVM connector instance create an OS instance (using win32)
    try mf.tryError(
        mf.inventory_create_os(inventory, "win32", "", &con_inst, &os_instance),
        error.OsInstanceCreationError,
    );

    var notepad_proc_inst: mf.ProcessInstance = undefined;

    while (true) {
        // Search for the target process name
        mf.tryError(
            mf.mf_osinstance_process_by_name(
                &os_instance,
                mf.slice("notepad.exe"),
                &notepad_proc_inst,
            ),
            error.MemflowProcessLookupError,
        ) catch {
            logger.info("Waiting for guest process...", .{});
            std.time.sleep(std.time.ns_per_s * 1);
            continue;
        };

        break;
    }

    const calc_proc_info: *const mf.ProcessInfo = mf.mf_processinstance_info(&notepad_proc_inst) orelse {
        logger.err("Failed to find process. Are you sure it's running?", .{});
        return error.MemflowProcessInfoError;
    };
    logger.info("Found process as PID {}", .{calc_proc_info.pid});

    var calc_mod_info: mf.ModuleInfo = undefined;
    logger.debug("Looking up main module info of process", .{});
    try mf.tryError(
        mf.mf_intoprocessinstance_primary_module(
            &notepad_proc_inst,
            &calc_mod_info,
        ),
        error.MemflowModuleLookupError,
    );
}
