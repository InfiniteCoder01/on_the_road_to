const std = @import("std");
const rl = @import("raylib");
const rendering = @import("rendering.zig");
const level_mod = @import("level.zig");

pub const Player = struct {
    sprite: rendering.MappedImage,
    position: rl.Vector2,
    velocity: rl.Vector2,
    direction: f32,

    checkpoint: rl.Vector2,
    palette: f32,
    dash_time: f32,
    dash_particle_effect: f32,
    jumps: u32,
    drowning: f32,
    drowning_particle_effect: f32,
    dying: f32,

    speed: f32,
    max_dash_time: f32,
    max_jumps: u32,
    swimming: bool,
    death_time: f32,

    pub fn init(alloc: *const std.mem.Allocator, position: rl.Vector2) anyerror!Player {
        return Player{
            .sprite = try rendering.MappedImage.init(alloc, "assets/player.png", rl.Vector2.init(24.0, 29.0), rl.Vector2.init(10.0, 8.0)),
            .position = position,
            .velocity = rl.Vector2.zero(),
            .direction = 0.0,

            .checkpoint = position,
            .palette = 0.0,
            .dash_particle_effect = 0.0,
            .dash_time = 0.0,
            .jumps = 0,
            .drowning = 0.0,
            .drowning_particle_effect = 0.0,
            .dying = -1.0,

            .speed = 150.0,
            .max_dash_time = 0.0,
            .max_jumps = 0,
            .swimming = false,
            .death_time = 5.0,
        };
    }

    pub fn reset(self: *Player) void {
        self.position = self.checkpoint;
        self.velocity = rl.Vector2.zero();
        self.dash_time = 0.0;
        self.drowning = 0.0;
        self.drowning_particle_effect = 0.0;
        self.dying = -1.0;
    }

    pub fn rect(self: *const Player) rl.Rectangle {
        return rl.Rectangle.init(self.position.x, self.position.y, self.sprite.tile.x, self.sprite.tile.y);
    }

    pub fn update(self: *Player, level: *level_mod.Level, delta_time: f32) void {
        if (self.dying < 0.0 and self.dash_time >= 0.0 and self.dash_time < self.max_dash_time and rl.isKeyDown(rl.KeyboardKey.key_tab)) {
            if (self.dash_time == 0.0) rl.playSound(level.dash);
            self.dash_time += delta_time;
            self.velocity.y = 0.0;
            self.velocity.x += (self.speed * self.direction - self.velocity.x) * 0.1;

            self.dash_particle_effect += delta_time;
            if (self.dash_particle_effect > 0.1) {
                // zig fmt: off
                level.particles.append(level_mod.Particle.init(
                    self.position.add(self.sprite.tile.multiply(rl.Vector2.init(0.5, 1.0))),
                    rl.Vector2.init(1, 0))
                ) catch std.log.err("Can't spawn particle, might be running low on RAM!", .{});
                // zig fmt: on
                self.dash_particle_effect = 0.0;
            }
        } else if (self.dying < 0.0 and self.jumps > 0 and rl.isKeyPressed(rl.KeyboardKey.key_space)) {
            rl.playSound(level.jump);
            self.jumps -= 1;
            self.velocity.y = -100.0;
        } else {
            if (self.dash_time > 0.0) {
                rl.stopSound(level.dash);
                self.dash_time = -self.dash_time;
            } else if (self.dash_time < 0.0) {
                self.dash_time = @min(self.dash_time + delta_time, 0.0);
            }
            if (self.dying < 0.0) {
                const joy =
                    @as(f32, if (rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isKeyDown(rl.KeyboardKey.key_right)) 1.0 else 0.0) -
                    @as(f32, if (rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isKeyDown(rl.KeyboardKey.key_left)) 1.0 else 0.0);
                if (joy != 0) {
                    self.direction = joy;
                }
                self.velocity.x += (joy * self.speed - self.velocity.x) * 0.1;
            } else self.velocity.x = 0.0;
            self.velocity.y += @as(f32, if (self.drowning > 0.0) 160.0 else 280.0) * delta_time;
        }

        const motion = self.velocity.scale(delta_time);
        if (self.move(motion.multiply(rl.Vector2.init(0.0, 1.0)), level, delta_time)) self.velocity.y = 0.0;
        if (self.move(motion.multiply(rl.Vector2.init(1.0, 0.0)), level, delta_time)) self.velocity.x = 0.0;

        {
            var drowning = false;
            const tl = self.position.add(rl.Vector2.init(10, 0)).divide(level.tileset.tile_size);
            const br = self.position.add(rl.Vector2.init(18, self.sprite.tile.y - 5)).divide(level.tileset.tile_size);
            for (@intFromFloat(@max(@floor(tl.y), 0))..@intFromFloat(@ceil(br.y))) |y| {
                for (@intFromFloat(@max(@floor(tl.x), 0))..@intFromFloat(@ceil(br.x))) |x| {
                    if (x >= level.water_map.width or y >= level.water_map.height) continue;
                    if (level.water_map.getColor(@intCast(x), @intCast(y)).a >= 128) {
                        drowning = true;
                    }
                }
            }
            if (drowning) {
                self.drowning += delta_time;
                self.drowning_particle_effect += delta_time;
                if (self.drowning_particle_effect > 0.5) {
                    var bubble = level_mod.Particle.init(if (self.dying < 0.0)
                        self.position.add(rl.Vector2.init(11, 9))
                    else
                        self.position.add(rl.Vector2.init(14, 21)), rl.Vector2.init(0, 0));
                    bubble.velocity.x = level.rand.random().float(f32) * 40.0 - 20.0;
                    level.particles.append(bubble) catch std.log.err("Can't spawn particle, might be running low on RAM!", .{});
                    self.drowning_particle_effect = 0.0;
                }
                if (self.drowning > 1.0 and self.dying < 0.0 and !self.swimming) {
                    self.dying = 0.0;
                    rl.playSound(level.death);
                }
                if (self.swimming) self.jumps = self.max_jumps;
            } else {
                self.drowning = 0.0;
            }
        }

        for (level.data.value.entities.checkpoint) |checkpoint| {
            const checkpoint_rect = rl.Rectangle.init(checkpoint.x, checkpoint.y, checkpoint.width, checkpoint.height);
            if (checkpoint_rect.checkCollision(self.rect())) {
                self.checkpoint = rl.Vector2.init(checkpoint.x, checkpoint.y);
            }
        }

        var i: usize = 0;
        while (i < level.data.value.entities.card.len) {
            var card = &level.data.value.entities.card[i];
            const card_rect = rl.Rectangle.init(card.x, card.y, card.width, card.height);
            if (card_rect.checkCollision(self.rect())) {
                if (std.mem.eql(u8, card.customFields.card, "dash")) {
                    self.max_dash_time = 1.4;
                    self.palette = 1.0;
                    level.hint = "Use TAB to dash through the air!";
                } else if (std.mem.eql(u8, card.customFields.card, "jump")) {
                    self.max_jumps = 1;
                    self.palette = 2.0;
                    level.hint = "Use Space to jump!";
                } else if (std.mem.eql(u8, card.customFields.card, "swim")) {
                    self.swimming = true;
                    self.palette = 3.0;
                    level.hint = "You can swim now,\nthis is the end of the game!";
                }
                level.hint_timer = 3.0;
                rl.playSound(level.card);
                card.y = -1024.0;
            }
            i += 1;
        }

        if (self.dying >= 0.0) {
            self.dying += delta_time;
            self.sprite.render(rl.Vector2.init(@min(@max(@floor((self.dying - 1.0) * 5.0), 0.0), 3.0) + 6.0, self.palette), rl.Vector2.init(@min(@floor(self.dying * 5.0), 2.0) + 1.0, 1.0));
        } else {
            const animation = if (@abs(self.velocity.x) > 50.0) 2.0 else if (@abs(self.velocity.x) > 4.0) @as(f32, 1.0) else 0.0;
            self.sprite.render(rl.Vector2.init(6.0, self.palette), rl.Vector2.init(3.0 + animation * @as(f32, if (self.velocity.x > 0.0) 1.0 else -1.0), 0.0));
        }
    }

    fn move(self: *Player, motion: rl.Vector2, level: *const level_mod.Level, delta_time: f32) bool {
        const step = rl.Vector2.init(
            if (motion.x > 0.0) 1.0 else if (motion.x < 0.0) -1.0 else 0.0,
            if (motion.y > 0.0) 1.0 else if (motion.y < 0.0) -1.0 else 0.0,
        ).scale(0.1);
        const steps: u32 = @intFromFloat(if (step.x != 0) motion.x / step.x else if (step.y != 0) motion.y / step.y else 0);

        for (0..steps) |_| {
            self.position = self.position.add(step);
            if (self.collides(level)) {
                var resolved = false;
                if (motion.y == 0.0) {
                    const old_position = self.position;
                    for (0..15) |_| {
                        self.position = self.position.add(rl.Vector2.init(0.0, -0.1));
                        if (!self.collides(level)) {
                            resolved = true;
                            break;
                        }
                    }
                    if (!resolved) {
                        self.position = old_position;
                    } else {
                        self.velocity.y += (self.position.y - old_position.y) / delta_time * 0.1;
                    }
                }

                if (!resolved) {
                    self.position = self.position.subtract(step);
                    if (motion.y > 0) self.jumps = self.max_jumps;
                    return true;
                }
            }
        }
        return false;
    }

    fn collides(self: *Player, level: *const level_mod.Level) bool {
        for (0..@intFromFloat(self.sprite.tile.y)) |y| {
            for (8..16) |x| {
                const level_x: c_int = @intFromFloat(self.position.x + @as(f32, @floatFromInt(x)));
                const level_y: c_int = @intFromFloat(self.position.y + @as(f32, @floatFromInt(y)));
                if (level_x < 0 or level_y < 0 or level_x >= level.tiles_image.width or level_y >= level.tiles_image.height) {
                    return true;
                }
                if (level.tiles_image.getColor(level_x, level_y).a >= 128) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn draw(self: *const Player, camera: rl.Vector2, scale: f32) void {
        rl.drawTextureEx(self.sprite.rendered, self.position.subtract(camera).scale(scale), 0.0, scale, rl.Color.white);
    }

    pub fn deinit(self: *Player, alloc: *const std.mem.Allocator) void {
        self.sprite.deinit(alloc);
    }
};
