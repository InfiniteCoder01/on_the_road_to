const std = @import("std");
const rl = @import("raylib");
const rendering = @import("rendering.zig");

pub const Particle = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    texture: rl.Vector2,
    lifetime: f32,
    alive: bool,

    pub fn init(position: rl.Vector2, texture: rl.Vector2) Particle {
        return Particle{
            .position = position,
            .velocity = rl.Vector2.zero(),
            .texture = texture,
            .lifetime = 0.8,
            .alive = true,
        };
    }

    pub fn update(self: *Particle, level: *const Level, delta_time: f32) void {
        self.lifetime -= delta_time;
        const tile = self.position.divide(level.tileset.tile_size);
        if (self.texture.x == 0 and self.texture.y == 0) {
            if (level.water_map.getColor(@intFromFloat(tile.x), @intFromFloat(tile.y)).a < 128) {
                self.alive = false;
            }
            self.velocity = self.velocity.scale(0.99);
            self.velocity.y -= 10.0 * delta_time;
        } else if (self.texture.x == 1 and self.texture.y == 0) {
            if (self.lifetime < 0) self.alive = false;
        }

        self.position = self.position.add(self.velocity.scale(delta_time));
    }
};

pub const Level = struct {
    const LevelData = struct {
        entities: struct {
            checkpoint: []struct {
                x: f32,
                y: f32,
                width: f32,
                height: f32,
            },
            label: []struct {
                x: f32,
                y: f32,
                customFields: struct {
                    text: [:0]u8,
                    scale: f32,
                },
            },
            card: []struct {
                x: f32,
                y: f32,
                width: f32,
                height: f32,
                customFields: struct {
                    card: [:0]u8,
                },
            },
            camera_zone: []struct {
                x: f32,
                y: f32,
                width: f32,
                height: f32,
            },
        },
    };

    data: std.json.Parsed(LevelData),
    size: rl.Vector2,
    tileset: rendering.Tileset,
    particle_tileset: rendering.Tileset,
    cards: rendering.Tileset,
    flag: rl.Texture,

    animation_timer: f32,
    particles: std.ArrayList(Particle),
    rand: std.rand.DefaultPrng,

    hint: [:0]const u8,
    hint_timer: f32,

    decorative: rl.Texture,
    tiles_image: rl.Image,
    tiles: rl.Texture,
    background: rl.Texture,
    water_map: rl.Image,

    jump: rl.Sound,
    dash: rl.Sound,
    death: rl.Sound,
    card: rl.Sound,

    pub fn init(alloc: std.mem.Allocator, comptime path: [:0]const u8) anyerror!Level {
        std.debug.print("0\n", .{});
        const level_file = try std.fs.cwd().readFileAlloc(alloc, path ++ "/data.json", 2048);
        defer alloc.free(level_file);
        std.debug.print("1\n", .{});
        const level_data = try std.json.parseFromSlice(LevelData, alloc, level_file, .{
            .ignore_unknown_fields = true,
        });

        const tiles_image = rl.loadImage(path ++ "/tilesdisplay.png");
        std.debug.print("2\n", .{});
        const tiles = tiles_image.toTexture();
        std.debug.print("3\n", .{});
        const water_map = rl.loadImage(path ++ "/water-int.png");
        std.debug.print("4\n", .{});
        const size = rl.Vector2.init(@floatFromInt(water_map.width), @floatFromInt(water_map.height));
        const tile_size = rl.Vector2.init(@floatFromInt(tiles_image.width), @floatFromInt(tiles_image.height)).divide(size);
        return Level{
            .data = level_data,
            .size = size,
            .tileset = rendering.Tileset.init("assets/tileset.png", tile_size),
            .particle_tileset = rendering.Tileset.init("assets/particles.png", rl.Vector2.init(4, 4)),
            .cards = rendering.Tileset.init("assets/cards.png", rl.Vector2.init(20, 24)),
            .flag = rl.loadTexture("assets/flag.png"),

            .animation_timer = 0.0,
            .particles = std.ArrayList(Particle).init(alloc),
            .rand = std.rand.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            }),

            .hint = "",
            .hint_timer = 0.0,

            .decorative = rl.loadTexture(path ++ "/decorative.png"),
            .tiles_image = tiles_image,
            .tiles = tiles,
            .background = rl.loadTexture(path ++ "/background.png"),
            .water_map = water_map,

            .jump = rl.loadSound("assets/jump.wav"),
            .dash = rl.loadSound("assets/dash.wav"),
            .death = rl.loadSound("assets/death.wav"),
            .card = rl.loadSound("assets/card.wav"),
        };
    }

    pub fn reset(self: *Level) void {
        self.particles.clearAndFree();
    }

    pub fn update(self: *Level, delta_time: f32) void {
        if (self.hint_timer > 0.0) {
            self.hint_timer = @max(self.hint_timer - delta_time, 0.0);
        }
        self.animation_timer += delta_time;
        var i: usize = 0;
        while (i < self.particles.items.len) {
            self.particles.items[i].update(self, delta_time);
            i += 1;
        }
        i = 0;
        while (i < self.particles.items.len) {
            if (!self.particles.items[i].alive) {
                _ = self.particles.swapRemove(i);
            } else i += 1;
        }
    }

    fn draw_tile(self: *const Level, camera: rl.Vector2, scale: f32, position: rl.Vector2, tile: rl.Vector2) void {
        self.tileset.draw_tile(camera, scale, position.multiply(self.tileset.tile_size), tile);
    }

    pub fn draw(self: *const Level, camera: rl.Vector2, scale: f32) void {
        const render_size = rl.Vector2.init(@floatFromInt(rl.getRenderWidth()), @floatFromInt(rl.getRenderHeight())).scale(1.0 / scale).divide(self.tileset.tile_size);
        const tl = camera.divide(self.tileset.tile_size);
        const br = tl.add(render_size);
        var y: i32 = @intFromFloat(@floor(tl.y));
        while (y < @as(i32, @intFromFloat(@ceil(br.y)))) {
            var x: i32 = @intFromFloat(@floor(tl.x));
            while (x < @as(i32, @intFromFloat(@ceil(br.x)))) {
                if (self.water_map.getColor(x, y).a >= 128) {
                    if (self.water_map.getColor(x, y - 1).a < 128) {
                        self.draw_tile(camera, scale, rl.Vector2.init(@floatFromInt(x), @floatFromInt(y)), rl.Vector2.init(3.0 + @rem(@floor(self.animation_timer * 2.0), 2.0), 0.0));
                    } else {
                        self.draw_tile(camera, scale, rl.Vector2.init(@floatFromInt(x), @floatFromInt(y)), rl.Vector2.init(3.0 + @rem(@floor(self.animation_timer + 0.3), 2.0), 1.0));
                    }
                }
                x += 1;
            }
            y += 1;
        }
        rl.drawTextureEx(self.background, camera.negate().scale(scale), 0.0, scale, rl.Color.white);

        for (self.particles.items) |particle| {
            self.particle_tileset.draw_tile(camera, scale, particle.position.subtract(self.particle_tileset.tile_size.scale(0.5)), particle.texture);
        }

        rl.drawTextureEx(self.tiles, camera.negate().scale(scale), 0.0, scale, rl.Color.white);
        rl.drawTextureEx(self.decorative, camera.negate().scale(scale), 0.0, scale, rl.Color.white);
        for (self.data.value.entities.checkpoint) |checkpoint| {
            const position = rl.Vector2.init(checkpoint.x, checkpoint.y).subtract(camera).scale(scale);
            rl.drawTextureEx(self.flag, position, 0.0, scale, rl.Color.white);
        }

        for (self.data.value.entities.card) |card| {
            self.cards.draw_tile(camera, scale, rl.Vector2.init(card.x, card.y),
            // zig fmt: off
                if (std.mem.eql(u8, card.customFields.card, "dash")) rl.Vector2.init(0, 0)
                else if (std.mem.eql(u8, card.customFields.card, "jump")) rl.Vector2.init(1, 0)
                else if (std.mem.eql(u8, card.customFields.card, "swim")) rl.Vector2.init(2, 0)
                else rl.Vector2.init(3, 5)
            // zig fmt: on
            );
        }

        for (self.data.value.entities.label) |label| {
            const font_size = @divTrunc(@as(i32, @intFromFloat(self.tileset.tile_size.scale(scale * label.customFields.scale).y)), @as(i32, @intCast(std.mem.count(u8, label.customFields.text, "\n") + 1)));
            const position = rl.Vector2.init(label.x, label.y).subtract(camera).scale(scale);
            rl.drawText(label.customFields.text, @intFromFloat(position.x), @intFromFloat(position.y), font_size, rl.Color.ray_white);
        }

        if (self.hint_timer > 0.0) {
            const font_size: i32 = @intFromFloat(8.0 * scale);
            rl.drawText(self.hint, rl.getRenderWidth() - rl.measureText(self.hint, font_size) - 10, 10, font_size, rl.Color.ray_white);
        }
    }

    pub fn deinit(self: *Level) void {
        self.data.deinit();
        self.particles.deinit();
    }
};
