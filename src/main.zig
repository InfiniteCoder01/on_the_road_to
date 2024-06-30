const std = @import("std");
const rl = @import("raylib");

pub fn main() anyerror!void {
    rl.initWindow(1080, 720, "On the road to...");
    defer rl.closeWindow();
    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    rl.setTargetFPS(60);

    var gpa = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    defer gpa.deinit();

    var level = try @import("level.zig").Level.init(gpa.allocator(), "assets/level/simplified/level_0");
    defer level.deinit();

    const start_checkpoint = 0;
    var player = try @import("player.zig").Player.init(&gpa.allocator(), rl.Vector2.init(level.data.value.entities.checkpoint[start_checkpoint].x, level.data.value.entities.checkpoint[start_checkpoint].y));
    defer player.deinit(&gpa.allocator());

    var camera = rl.Vector2.init(-10.0, 0.0);
    const scale = 4.0;

    while (!rl.windowShouldClose()) {
        const delta_time = rl.getFrameTime();
        if (player.dying > player.death_time) {
            player.reset();
            level.reset();
            player.death_time = 2.0;
        }

        player.update(&level, delta_time);
        const render_size = rl.Vector2.init(@floatFromInt(rl.getRenderWidth()), @floatFromInt(rl.getRenderHeight())).scale(1.0 / scale);

        var camera_target = player.position.add(player.sprite.tile.scale(0.5));
        for (level.data.value.entities.camera_zone) |camera_zone| {
            const camera_zone_rect = rl.Rectangle.init(camera_zone.x, camera_zone.y, camera_zone.width, camera_zone.height);
            if (camera_zone_rect.checkCollision(player.rect())) {
                camera_target.x = camera_zone.x + camera_zone.width / 2.0;
            }
        }

        camera = camera.add(camera_target
            .subtract(render_size.scale(0.5))
            .clamp(rl.Vector2.zero(), level.size.multiply(level.tileset.tile_size).subtract(render_size))
            .subtract(camera).scale(0.1));

        level.update(delta_time);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.sky_blue);
        level.draw(camera, scale);
        player.draw(camera, scale);
        rl.drawFPS(10, 10);
    }
}
