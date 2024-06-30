const std = @import("std");
const rl = @import("raylib");

pub const MappedImage = struct {
    source: rl.Image,
    tile: rl.Vector2,
    step: rl.Vector2,
    buffer: []rl.Color,
    rendered: rl.Texture,

    pub fn init(alloc: *const std.mem.Allocator, path: [:0]const u8, tile: rl.Vector2, step: rl.Vector2) anyerror!MappedImage {
        const image = rl.Image.genColor(@intFromFloat(tile.x), @intFromFloat(tile.y), rl.Color.black.alpha(0.0));

        return MappedImage{
            .source = rl.loadImage(path),
            .tile = tile,
            .step = step,
            .buffer = try alloc.alloc(rl.Color, @as(usize, @intFromFloat(tile.x)) * @as(usize, @intFromFloat(tile.y))),
            .rendered = image.toTexture(),
        };
    }

    pub fn render(self: *MappedImage, palette: rl.Vector2, shape: rl.Vector2) void {
        for (0..@intFromFloat(self.tile.y)) |y| {
            for (0..@intFromFloat(self.tile.x)) |x| {
                const shape_pixel = shape.multiply(self.tile).add(rl.Vector2.init(@floatFromInt(x), @floatFromInt(y)));
                const shape_color = self.source.getColor(@intFromFloat(shape_pixel.x), @intFromFloat(shape_pixel.y));
                const palette_pixel = rl.Vector2.init(@floatFromInt(shape_color.r), @floatFromInt(shape_color.g)).divide(self.step).add(palette.multiply(self.tile));
                self.buffer[x + y * @as(usize, @intFromFloat(self.tile.x))] = self.source.getColor(@intFromFloat(palette_pixel.x), @intFromFloat(palette_pixel.y));
            }
        }
        rl.updateTexture(self.rendered, @ptrCast(self.buffer));
    }

    pub fn deinit(self: *MappedImage, alloc: *const std.mem.Allocator) void {
        alloc.free(self.buffer);
    }
};

pub const Tileset = struct {
    texture: rl.Texture,
    tile_size: rl.Vector2,

    pub fn init(path: [:0]const u8, tile_size: rl.Vector2) Tileset {
        return Tileset{
            .texture = rl.loadTexture(path),
            .tile_size = tile_size,
        };
    }

    pub fn draw_tile(self: *const Tileset, camera: rl.Vector2, scale: f32, position: rl.Vector2, tile: rl.Vector2) void {
        const tile_pixels = tile.multiply(self.tile_size);
        const global_tile_pos = position.subtract(camera).scale(scale);
        rl.drawTexturePro(
            self.texture,
            rl.Rectangle.init(
                tile_pixels.x,
                tile_pixels.y,
                self.tile_size.x,
                self.tile_size.y,
            ),
            rl.Rectangle.init(
                global_tile_pos.x,
                global_tile_pos.y,
                self.tile_size.x * scale,
                self.tile_size.y * scale,
            ),
            rl.Vector2.zero(),
            0.0,
            rl.Color.white,
        );
    }
};
