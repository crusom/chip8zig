const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const C = @cImport({
    @cInclude("SDL2/SDL.h");
});

const RATIO_WIDTH: usize = 64;
const RATIO_HEIGHT: usize = 32;
const SIZE: usize = 15;

const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8 = 0xff,
};

pub const Renderer = struct {
    const Self = @This();
    renderer: *C.SDL_Renderer = undefined,
    screen: *C.SDL_Window = undefined,
    surf: *C.SDL_Surface = undefined,
    texture: ?*C.SDL_Texture = undefined,
    framebuffer: [32 * 64]u32 = undefined,
    window_width: i32 = undefined,
    window_height: i32 = undefined,

    key_pressed: [16]bool = .{false} ** 16,
    last_key_pressed: u8 = 0xff,

    pub fn init(self: *Self) anyerror!void {
        if (C.SDL_Init(C.SDL_INIT_VIDEO) != 0) {
            C.SDL_Log("Unable to initialize SDL: %s", C.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        self.window_width = RATIO_WIDTH * (SIZE);
        self.window_height = RATIO_HEIGHT * (SIZE);

        self.screen = C.SDL_CreateWindow(
            "Chip-8",
            C.SDL_WINDOWPOS_UNDEFINED,
            C.SDL_WINDOWPOS_UNDEFINED,
            @intCast(c_int, self.window_width),
            @intCast(c_int, self.window_height),
            C.SDL_WINDOW_SHOWN | C.SDL_WINDOW_RESIZABLE,
        ) orelse {
            C.SDL_Log("Unable to create window: %s", C.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        self.renderer = C.SDL_CreateRenderer(self.screen, -1, C.SDL_RENDERER_ACCELERATED | C.SDL_RENDERER_PRESENTVSYNC) orelse {
            C.SDL_Log("Unable to create renderer: %s", C.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        _ = C.SDL_RenderSetLogicalSize(self.renderer, RATIO_WIDTH, RATIO_HEIGHT);

        self.texture = C.SDL_CreateTexture(self.renderer, C.SDL_PIXELFORMAT_ABGR8888, C.SDL_TEXTUREACCESS_TARGET, RATIO_WIDTH, RATIO_HEIGHT);
        _ = C.SDL_RenderSetScale(self.renderer, 1, 2);
    }

    pub fn pollEvent(self: *Self) void {
        var e: C.SDL_Event = undefined;
        while (C.SDL_PollEvent(&e) != 0) {
            switch (e.window.event) {
                C.SDL_WINDOWEVENT_SIZE_CHANGED => {
                    self.window_width = e.window.data1;
                    self.window_height = e.window.data2;
                    self.updateTexture();
                },
                else => {},
            }
            switch (e.type) {
                C.SDL_QUIT => std.process.exit(0),
                C.SDL_KEYDOWN => {
                    if (e.key.keysym.sym == C.SDLK_ESCAPE) std.process.exit(0);

                    self.last_key_pressed = 0xff;
                    var key_index = get_key(e.key.keysym.sym);
                    if (key_index == 0xff) return;
                    self.key_pressed[key_index] = true;
                    self.last_key_pressed = key_index;
                },
                C.SDL_KEYUP => {
                    self.last_key_pressed = 0xff;
                    var key_index = get_key(e.key.keysym.sym);
                    if (key_index == 0xff) return;
                    self.key_pressed[key_index] = false;
                },
                else => {},
            }
        }
    }
    pub fn get_key(key_code: i32) u8 {
        var k_inx: u8 = undefined;
        switch (key_code) {
            C.SDLK_x => k_inx = 0,
            C.SDLK_1 => k_inx = 1,
            C.SDLK_2 => k_inx = 2,
            C.SDLK_3 => k_inx = 3,

            C.SDLK_q => k_inx = 4,
            C.SDLK_w => k_inx = 5,
            C.SDLK_e => k_inx = 6,

            C.SDLK_a => k_inx = 7,
            C.SDLK_s => k_inx = 8,
            C.SDLK_d => k_inx = 9,

            C.SDLK_z => k_inx = 10,
            C.SDLK_c => k_inx = 11,
            C.SDLK_4 => k_inx = 12,

            C.SDLK_r => k_inx = 13,
            C.SDLK_f => k_inx = 14,
            C.SDLK_v => k_inx = 15,
            else => k_inx = 0xff,
        }
        return k_inx;
    }

    pub fn updateTexture(self: *Self) void {
        //        var render_quad = C.SDL_Rect{
        //            .x = 0,
        //            .y = 0,
        //            .w = @intCast(c_int, self.window_width),
        //            .h = @divFloor(@intCast(c_int, self.window_height), 2),
        //        };
        _ = C.SDL_UpdateTexture(self.texture, null, &self.framebuffer, 64 * @sizeOf(@TypeOf(self.framebuffer[0])));
        _ = C.SDL_RenderClear(self.renderer);
        _ = C.SDL_RenderCopy(self.renderer, self.texture, null, null);
        // _ = C.SDL_RenderCopy(self.renderer, self.texture, &render_quad, null);

        C.SDL_RenderPresent(self.renderer);
    }

    pub fn destroy(self: *Self) void {
        C.SDL_DestroyRenderer(self.renderer);
        C.SDL_DestroyWindow(self.screen);
        C.SDL_Quit();
    }

    pub fn clear(self: *Self) void {
        std.mem.set(@TypeOf(self.framebuffer[0]), &self.framebuffer, 0);
        _ = C.SDL_RenderClear(self.renderer);
        _ = C.SDL_RenderPresent(self.renderer);
    }
};
