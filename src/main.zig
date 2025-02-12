const std = @import("std");
const rl = @import("raylib");

const FRAME_RATE = 60;

const WINDOW_SIZE = Vec2(u16){ .x = 960, .y = 960 };

const INITIAL_SNAKE_LENGTH: u8 = 4;
const SNAKE_SPEED = 3;

const WINDOW_GRID_SIZE = Vec2(i8){ .x = 32, .y = 32 };
const SNAKE_GRID_SIZE = WINDOW_GRID_SIZE.plus(&Vec2(i8){ .x = -2, .y = -2 });

const CELL_SIZE = Vec2(u16){
    .x = WINDOW_SIZE.x / WINDOW_GRID_SIZE.x,
    .y = WINDOW_SIZE.y / WINDOW_GRID_SIZE.y,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    rl.initWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, "Snake");
    defer rl.closeWindow();

    rl.setTargetFPS(FRAME_RATE);

    var score: u16 = 0;
    var game_over = false;

    var frame_modulus: u8 = 1;

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    const initial_snake_x = SNAKE_GRID_SIZE.x / 4 +
        random.intRangeLessThan(i8, 0, SNAKE_GRID_SIZE.x / 2);
    const initial_snake_y = SNAKE_GRID_SIZE.y / 4 +
        random.intRangeLessThan(i8, 0, SNAKE_GRID_SIZE.y / 2);

    const initial_snake_position = Vec2(i8){
        .x = initial_snake_x,
        .y = initial_snake_y,
    };

    var snake_position = std.ArrayList(Vec2(i8)).init(allocator);
    defer snake_position.deinit();

    var snake_direction = Vec2(i8).POS_X;

    try snake_position.append(initial_snake_position);
    for (1..INITIAL_SNAKE_LENGTH) |i| {
        try snake_position.append(.{
            .x = initial_snake_x - @as(i8, @intCast(i)),
            .y = initial_snake_y,
        });
    }

    std.log.debug("Initial snake position: {any}", .{snake_position.items});

    var fruit_positions = std.ArrayList(Vec2(i8)).init(allocator);
    defer fruit_positions.deinit();

    try addFruit(&random, &fruit_positions, snake_position.items);

    const font = try rl.getFontDefault();

    var queued_direction: ?Vec2(i8) = null;

    while (!rl.windowShouldClose()) {
        if (!game_over) {
            frame_modulus = (frame_modulus + 1) % (FRAME_RATE / SNAKE_SPEED);

            if (rl.isKeyPressed(rl.KeyboardKey.w)) {
                queued_direction = Vec2(i8).NEG_Y;
            }
            if (rl.isKeyPressed(rl.KeyboardKey.s)) {
                queued_direction = Vec2(i8).POS_Y;
            }
            if (rl.isKeyPressed(rl.KeyboardKey.a)) {
                queued_direction = Vec2(i8).NEG_X;
            }
            if (rl.isKeyPressed(rl.KeyboardKey.d)) {
                queued_direction = Vec2(i8).POS_X;
            }

            if (frame_modulus == 0) {
                if (queued_direction) |qd| {
                    const is_axis_change = (snake_direction.x == 0 and qd.x != 0) or (snake_direction.y == 0 and qd.y != 0);

                    if (is_axis_change) {
                        snake_direction = qd;
                    }
                }
                queued_direction = null;

                const popped_position = snake_position.pop();
                const head_position = snake_position.items[0];
                try snake_position.insert(
                    0,
                    head_position.plus(&snake_direction),
                );

                const new_head_position = snake_position.items[0];

                if (indexOfPosition(fruit_positions.items, &new_head_position)) |i| {
                    score += 1;
                    _ = fruit_positions.orderedRemove(i);

                    try snake_position.append(popped_position);

                    try addFruit(&random, &fruit_positions, snake_position.items);
                }

                if (new_head_position.x < 0 or
                    new_head_position.x > SNAKE_GRID_SIZE.x or
                    new_head_position.y < 0 or
                    new_head_position.y > SNAKE_GRID_SIZE.y or
                    indexOfPosition(snake_position.items[1..], &new_head_position) != null)
                {
                    game_over = true;
                }
            }
        }

        try draw(&font, snake_position.items, fruit_positions.items, &score, &game_over);
    }
}

fn indexOfPosition(slice: []const Vec2(i8), position: *const Vec2(i8)) ?usize {
    return for (slice, 0..) |item, i| {
        if (std.meta.eql(item, position.*)) {
            break i;
        }
    } else null;
}

fn addFruit(
    random: *const std.Random,
    fruit_positions: *std.ArrayList(Vec2(i8)),
    snake_position: []const Vec2(i8),
) !void {
    outer_while: while (true) {
        const random_x = random.intRangeLessThan(i8, 0, SNAKE_GRID_SIZE.x) + 1;
        const random_y = random.intRangeLessThan(i8, 0, SNAKE_GRID_SIZE.y) + 1;
        const random_position = Vec2(i8){ .x = random_x, .y = random_y };

        if (indexOfPosition(snake_position, &random_position)) |_| {
            continue :outer_while;
        }
        if (indexOfPosition(fruit_positions.items, &random_position)) |_| {
            continue :outer_while;
        }

        try fruit_positions.append(random_position);
        break;
    }
}

fn draw(
    font: *const rl.Font,
    snake_position: []const Vec2(i8),
    fruit_positions: []const Vec2(i8),
    score: *const u16,
    game_over: *const bool,
) !void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.black);

    const inset_background_rectangle = rl.Rectangle.init(
        CELL_SIZE.x,
        CELL_SIZE.y,
        WINDOW_SIZE.x - CELL_SIZE.x * 2,
        WINDOW_SIZE.y - CELL_SIZE.y * 2,
    );
    rl.drawRectangleRounded(
        inset_background_rectangle,
        0.02,
        8,
        rl.Color.ray_white,
    );

    var title_buffer: [20]u8 = undefined;
    const title_slice = try std.fmt.bufPrintZ(&title_buffer, "Snake - Score: {}", .{score.*});

    rl.drawTextEx(
        font.*,
        title_slice,
        rl.Vector2.init(CELL_SIZE.x + 8, 8),
        16,
        1,
        rl.Color.white,
    );

    for (fruit_positions) |fp| {
        rl.drawRectangle(
            @as(i32, @intCast(fp.x)) * CELL_SIZE.x,
            @as(i32, @intCast(fp.y)) * CELL_SIZE.y,
            CELL_SIZE.x,
            CELL_SIZE.y,
            rl.Color.red,
        );
    }

    for (snake_position) |sp| {
        rl.drawRectangle(
            @as(i32, @intCast(sp.x)) * CELL_SIZE.x,
            @as(i32, @intCast(sp.y)) * CELL_SIZE.y,
            CELL_SIZE.x,
            CELL_SIZE.y,
            rl.Color.green,
        );
    }

    if (game_over.*) {
        const game_over_font_size = 48;
        const game_over_spacing = 1;
        rl.drawRectangle(
            0,
            0,
            WINDOW_SIZE.x,
            WINDOW_SIZE.y,
            rl.Color.alpha(rl.Color.black, 0.5),
        );
        const text_size = rl.measureTextEx(
            font.*,
            "GAME OVER",
            game_over_font_size,
            game_over_spacing,
        );
        rl.drawTextEx(
            font.*,
            "GAME OVER",
            rl.Vector2.init(
                WINDOW_SIZE.x / 2 - text_size.x / 2,
                WINDOW_SIZE.y / 2 - text_size.y / 2,
            ),
            game_over_font_size,
            game_over_spacing,
            rl.Color.red,
        );
    }
}

fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        const POS_X = Self{ .x = 1, .y = 0 };
        const POS_Y = Self{ .x = 0, .y = 1 };
        const NEG_X = Self{ .x = -1, .y = 0 };
        const NEG_Y = Self{ .x = 0, .y = -1 };

        fn plus(self: *const Self, other: *const Self) Self {
            return .{
                .x = self.x + other.x,
                .y = self.y + other.y,
            };
        }
    };
}
