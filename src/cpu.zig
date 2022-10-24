const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const mem = std.mem;
const native_endian = @import("builtin").target.cpu.arch.endian();
const RndGen = std.rand.DefaultPrng;
const Renderer = @import("display.zig").Renderer;
const Stack = @import("stack.zig").Stack;

const FileReadError = error{
    FileTooHuge,
};

const ExecError = error{
    PcOutOfRange,
    InvalidInstruction,
    FullStack,
    EmptyStack,
};

const screen_width: u8 = 64;
const screen_height: u8 = 32;
const HERTZ: usize = 600;

pub const CPU = struct {
    const Self = @This();
    const rom_offset: usize = 0x200;
    const fontset = [80]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, //0
        0x20, 0x60, 0x20, 0x20, 0x70, //1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, //2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, //3
        0x90, 0x90, 0xF0, 0x10, 0x10, //4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, //5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, //6
        0xF0, 0x10, 0x20, 0x40, 0x40, //7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, //8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, //9
        0xF0, 0x90, 0xF0, 0x90, 0x90, //A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, //B
        0xF0, 0x80, 0x80, 0x80, 0xF0, //C
        0xE0, 0x90, 0x90, 0x90, 0xE0, //D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, //E
        0xF0, 0x80, 0xF0, 0x80, 0x80, //F
    };
    const Opcode = packed union {
        n: switch (native_endian) {
            .Big => packed struct {
                HB: u4,
                X: u4,
                Y: u4,
                N: u4,
            },
            .Little => packed struct {
                N: u4,
                Y: u4,
                X: u4,
                HB: u4,
            },
        },
        raw_val: u16,
    };
    // I actually just use struct as a namespace for prettier and more modular code, but u can easily change it if u want to :)

    callstack: Stack(u16, 100) = Stack(u16, 100).init(),
    memory: [0x1000]u8 = .{0} ** 0x1000,
    V: [0x10]u8 = .{0} ** 0x10,
    I: u16 = 0x0,
    pc: u16 = 0x200,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    opcode: Opcode = Opcode{ .raw_val = 0x0 },
    rnd: RndGen = RndGen.init(0),
    redraw_screen: bool = false,
    renderer: Renderer = Renderer{},

    delay_temp: usize = 0,

    pub fn loadRom(self: *Self, filename: []const u8) !void {
        _ = try self.renderer.init();
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        const stat = try file.stat();
        print("[INFO] rom size: {d}\n", .{stat.size});
        if (stat.size > self.memory.len - rom_offset) return FileReadError.FileTooHuge;
        const bytes_read = try file.readAll(self.memory[rom_offset..]);
        _ = bytes_read;
        print("[INFO] rom loaded\n", .{});

        mem.copy(u8, &self.memory, &fontset);
    }

    inline fn not_implemented(op: u16) ExecError!void {
        print("[ERORR] not implemented x{x}\n", .{op});
        return ExecError.InvalidInstruction;
    }

    pub fn tick(self: *Self) ExecError!void {
        if (self.pc + 1 >= 0x1000) {
            return ExecError.PcOutOfRange;
        }

        self.opcode.raw_val = blk: {
            var tmp = @as(u16, self.memory[self.pc]) << 8;
            tmp |= @as(u16, self.memory[self.pc + 1]);
            break :blk tmp;
        };

        self.renderer.pollEvent();
        if (self.redraw_screen) {
            self.renderer.updateTexture();
            self.redraw_screen = false;
        }

        std.time.sleep(1000000000 / HERTZ);
        self.delay_temp %= (HERTZ / 60);
        if (self.delay_temp == 0) self.delay_timer -|= 1;

        var NNN: u12 = @truncate(u12, self.opcode.raw_val & 0x0fff);
        var NN: u8 = @truncate(u8, self.opcode.raw_val & 0x00ff);

        self.pc += 2;
        switch (self.opcode.n.HB) {
            // clear screen
            // x0FFF
            0x00 => {
                switch (self.opcode.n.X) {
                    // x00FF
                    0x00 => {
                        switch (NN) {
                            0xE0 => {
                                self.renderer.clear();
                            },
                            // return from the subroutine;
                            0xEE => {
                                if (self.callstack.is_empty()) return;
                                self.pc = try self.callstack.pop();
                            },
                            else => {
                                try not_implemented(self.opcode.raw_val);
                            },
                        }
                    },
                    else => {
                        try not_implemented(self.opcode.raw_val);
                    },
                }
            },
            // jmp
            0x01 => self.pc = NNN,
            // call the subroutine
            0x02 => {
                try self.callstack.push(self.pc);
                self.pc = NNN;
            },
            0x03 => {
                if (self.V[self.opcode.n.X] == NN) self.pc += 2;
            },
            0x04 => {
                if (self.V[self.opcode.n.X] != NN) self.pc += 2;
            },
            0x05 => {
                if (self.V[self.opcode.n.X] == self.V[self.opcode.n.Y]) self.pc += 2;
            },
            0x06 => self.V[self.opcode.n.X] = NN,
            0x07 => self.V[self.opcode.n.X] +%= NN,
            0x08 => {
                switch (self.opcode.n.N) {
                    0x00 => self.V[self.opcode.n.X] = self.V[self.opcode.n.Y],
                    0x01 => self.V[self.opcode.n.X] |= self.V[self.opcode.n.Y],
                    0x02 => self.V[self.opcode.n.X] &= self.V[self.opcode.n.Y],
                    0x03 => self.V[self.opcode.n.X] ^= self.V[self.opcode.n.Y],
                    0x04 => {
                        var temp: u16 = @as(u16, self.V[self.opcode.n.X]) +% @as(u16, self.V[self.opcode.n.Y]);
                        self.V[self.opcode.n.X] = @truncate(u8, temp);
                        self.V[0xf] = if (temp >= 0x100) 1 else 0;
                    },
                    0x05 => {
                        var temp: i16 = @as(i16, self.V[self.opcode.n.X]) -% @as(i16, self.V[self.opcode.n.Y]);
                        self.V[self.opcode.n.X] -%= self.V[self.opcode.n.Y];
                        self.V[0xf] = if (temp >= 0) 1 else 0;
                    },
                    0x06 => {
                        var is_set = self.V[self.opcode.n.X] & 1;
                        self.V[self.opcode.n.X] = (self.V[self.opcode.n.X] >> 1);
                        self.V[0xf] = is_set;
                    },
                    0x07 => {
                        var temp: i16 = @as(i16, self.V[self.opcode.n.Y]) -% @as(i16, self.V[self.opcode.n.X]);
                        self.V[self.opcode.n.X] = self.V[self.opcode.n.Y] -% self.V[self.opcode.n.X];
                        self.V[0xf] = if (temp >= 0) 1 else 0;
                    },
                    0x0E => {
                        var is_set = ((self.V[self.opcode.n.X] & 128) >> 7);
                        self.V[self.opcode.n.X] <<= 1;
                        self.V[0xf] = is_set;
                    },
                    else => {
                        try not_implemented(self.opcode.raw_val);
                    },
                }
            },
            0x09 => {
                if (self.V[self.opcode.n.X] != self.V[self.opcode.n.Y]) self.pc += 2;
            },
            0x0A => {
                self.I = NNN;
            },

            0x0B => self.pc = (NNN + self.V[0]) & 0xfff,
            0x0C => self.V[self.opcode.n.X] = self.rnd.random().int(u8) & NN,
            0x0D => {
                var n: u8 = self.opcode.n.N;
                var x: u8 = self.V[self.opcode.n.X] % screen_width;
                var y: u8 = self.V[self.opcode.n.Y] % screen_height;
                var flipped: bool = false;

                var j: usize = 0;
                while (j < n) : ({
                    j += 1;
                    y += 1;
                }) {
                    // wrap around
                    y %= screen_height;
                    var pixel: u8 = self.memory[self.I + j];
                    var k: u8 = 0;
                    while (k < 8) : (k += 1) {
                        // bits are stored in Big-endian
                        // so read from left to right
                        var bit: u8 = (pixel >> (7 - @intCast(u3, k))) & 0x1;
                        //                        var index: usize = @as(usize, x) + @as(usize, k) + @as(usize, y) * screen_width;
                        var index: usize = (@as(usize, x) + @as(usize, k)) % screen_width + @as(usize, y) * screen_width;
                        if (bit != 0) {
                            if (self.renderer.framebuffer[index] != 0) {
                                flipped = true;
                            }
                            self.renderer.framebuffer[index] ^= 0xFFFFFFFF;
                        }
                    }
                    self.V[0xf] = if (flipped) 1 else 0;
                    self.redraw_screen = true;
                }
            },

            0x0E => {
                switch (NN) {
                    0x9E => {
                        var idx = self.V[self.opcode.n.X];
                        var pressed: bool = false;
                        if (idx < 0x10) {
                            pressed = self.renderer.key_pressed[idx];
                        }
                        if (pressed) {
                            self.pc += 2;
                        }
                    },
                    0xA1 => {
                        var idx = self.V[self.opcode.n.X];
                        var pressed: bool = false;
                        if (idx < 0x10) {
                            pressed = self.renderer.key_pressed[idx];
                        }
                        if (!pressed) {
                            self.pc += 2;
                        }
                    },
                    else => try not_implemented(self.opcode.raw_val),
                }
            },

            0x0F => {
                switch (NN) {
                    0x07 => {
                        self.V[self.opcode.n.X] = self.delay_timer;
                    },
                    0x0A => {
                        if (self.renderer.last_key_pressed == 0xFF) {
                            self.pc -= 2;
                        } else {
                            self.V[self.opcode.n.X] = self.renderer.last_key_pressed;
                        }
                    },
                    0x15 => {
                        self.delay_timer = self.V[self.opcode.n.X];
                    },
                    0x18 => {
                        self.sound_timer = self.V[self.opcode.n.X];
                    },
                    0x1E => {
                        if (self.I + @as(u16, self.V[self.opcode.n.X]) > 4095) self.V[0xf] = 1;
                        self.I += self.V[self.opcode.n.X];
                    },
                    0x29 => {
                        self.I = @as(u16, self.V[self.opcode.n.X]) * 5;
                    },
                    0x33 => {
                        self.memory[self.I] = self.V[self.opcode.n.X] / 100;
                        self.memory[self.I + 1] = (self.V[self.opcode.n.X] / 10) % 10;
                        self.memory[self.I + 2] = self.V[self.opcode.n.X] % 10;
                    },
                    0x55 => {
                        var i: usize = 0;
                        while (i <= self.opcode.n.X) : (i += 1) {
                            self.memory[self.I + i] = self.V[i];
                        }
                    },
                    0x65 => {
                        var i: usize = 0;
                        while (i <= self.opcode.n.X) : (i += 1) {
                            self.V[i] = self.memory[self.I + i];
                        }
                    },
                    else => {
                        try not_implemented(self.opcode.raw_val);
                    },
                }
            },
        }
        //        self.disas();
    }
    pub fn destroy(self: *Self) void {
        self.renderer.destroy();
    }
    pub fn disas(self: *Self) void {
        var NNN: u16 = self.opcode.raw_val & 0x0fff;
        var NN: u16 = self.opcode.raw_val & 0x00ff;

        print("pc: {x} {x} ", .{ self.pc, self.opcode.raw_val });

        switch (self.opcode.n.HB) {
            0x00 => {
                switch (self.opcode.n.X) {
                    0x00 => {
                        switch (NN) {
                            0xE0 => print("CLS\n", .{}),
                            0xEE => print("RET", .{}),
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            0x01 => print("JP {x}", .{NNN}),
            0x02 => print("CALL #{x}", .{NNN}),
            0x03 => print("SE Vx, #{x}", .{NN}),
            0x04 => print("SNE Vx, #{x}", .{NN}),
            0x05 => print("SE Vx, Vy", .{}),
            0x06 => print("LD Vx, #{x}", .{NN}),
            0x07 => print("ADD Vx, #{x}", .{NN}),
            0x08 => {
                switch (self.opcode.n.N) {
                    0x00 => print("LD Vx, Vy", .{}),
                    0x01 => print("OR Vx, Vy", .{}),
                    0x02 => print("AND Vx, Vy", .{}),
                    0x03 => print("XOR Vx, Vy", .{}),
                    0x04 => print("ADDS Vx, Vy", .{}),
                    0x05 => print("SUBS Vx, Vy", .{}),
                    0x06 => print("SHR Vx, Vy", .{}),
                    0x07 => print("SUBNS Vx, Vy", .{}),
                    0x0E => print("SHL Vx, Vy", .{}),
                    else => {},
                }
            },

            0x09 => print("SNE Vx, Vy", .{}),
            0x0A => print("LD I, #{x}", .{NNN}),
            0x0B => print("JP {x}, {x}", .{ self.V[0], NNN }),

            0x0C => print("RND Vx, {x}", .{NN}),
            0x0D => print("\x1B[91mDRW x: {x} y: {x} n: {x}\x1b[0m", .{ self.V[self.opcode.n.X], self.V[self.opcode.n.Y], self.opcode.n.N }),

            0x0E => {
                switch (NN) {
                    0x9E => print("SKP {x} (pressed)", .{self.V[self.opcode.n.X]}),
                    0xA1 => print("SKNP {x} (Not pressed)", .{self.V[self.opcode.n.X]}),
                    else => {},
                }
            },

            0x0F => {
                switch (NN) {
                    0x07 => print("LD Vx, {x} (DelayTimer)", .{self.delay_timer}),
                    0x0A => print("LD Vx, {x} (KeyPressed)", .{self.renderer.last_key_pressed}),
                    0x15 => print("LD DelayTimer, {x}", .{self.V[self.opcode.n.X]}),
                    0x18 => print("LD SoundTimer, {x}", .{self.V[self.opcode.n.X]}),
                    0x1E => print("ADD I, {x}", .{self.V[self.opcode.n.X]}),
                    0x29 => print("LD F, {x} (normal font)", .{self.V[self.opcode.n.X]}),
                    0x33 => print("LD B, {x}", .{self.V[self.opcode.n.X]}),
                    0x55 => print("LD [i], {x}", .{self.V[self.opcode.n.X]}),
                    0x65 => print("LD Vx, [I]", .{}),
                    else => {},
                }
            },
        }
        print(" X: {x}, Y: {x}\n", .{ self.opcode.n.X, self.opcode.n.Y });
        var reg: usize = 0;
        while (reg <= 0xf) : (reg += 1) {
            print("V{x} -> {x}\n", .{ reg, self.V[reg] });
        }
    }
};
