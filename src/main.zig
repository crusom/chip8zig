const std = @import("std");
const assert = @import("std").debug.assert;
const CPU = @import("cpu.zig").CPU;

var a: std.mem.Allocator = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    a = arena.allocator();
    var arg_it = try std.process.argsWithAllocator(a);
    _ = arg_it.skip();

    const rom = arg_it.next() orelse {
        std.debug.print("Expected first argument to be ROM path\n", .{});
        return error.InvalidArgs;
    };

    var cpu = comptime CPU{};
    try cpu.loadRom(rom);
    defer cpu.destroy();
    while (true) {
        try cpu.tick();
    }
}
