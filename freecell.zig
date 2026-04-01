const std = @import("std");

const card = @import("card.zig");
const board = @import("board.zig");
const solver = @import("solver.zig");
const game = @import("game.zig");

const Board = board.Board;
const Move = board.Move;
const Card = board.Card;
const cardName = card.cardName;
const solveFreeCell = solver.solveFreeCell;
const Path = solver.Path;

const verbose = true;
const IMPROVE_PATH_ATTEMPTS: u32 = 1000000;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_board = try game.parseJsonGame(allocator);

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const time_start = std.Io.Clock.now(std.Io.Clock.real, init.io);

    var seed: u32 = 29;
    var total_length: u64 = 0;
    var total_iters: u64 = 0;
    while (seed < 30) : (seed += 1) {
        var game_board = input_board;
        if (board.KEEP_COLUMNS_SORTED) {
            game_board.sortColumns();
        }
        game_board.reallocateColumns();

        if (verbose) {
            std.debug.print("Initial board state:\n", .{});
            input_board.print();
            std.debug.print("=== ATTEMPTING TO SOLVE ===\n", .{});
        }

        var solution_path: Path = .empty;
        const found, const iters = try solver.solveDFS(&game_board, allocator, &solution_path);
        total_length += solution_path.items.len;
        total_iters += iters;

        if (found and IMPROVE_PATH_ATTEMPTS > 0) {
            while (try solver.improvePath(&game_board, &solution_path, IMPROVE_PATH_ATTEMPTS, allocator)) {
                std.debug.print("Found improved path! New length: {d}\n", .{solution_path.items.len});
            }
        }

        const path_length = solution_path.items.len;
        var true_path = try allocator.alloc(Move, path_length);
        solver.remapPath(&input_board, &game_board, solution_path.items, &true_path);

        if (verbose) {
            std.debug.print("Solver completed. Found solution: {}. Path length: {d}. Iterations: {d}\n", .{ found, path_length, iters });

            if (found) {
                var verify_board = input_board;
                for (true_path, 0..) |move, i| {
                    std.debug.print("  {d:>3}: slot {d:>2} -> slot {d:>2}    {s}\n", .{ i + 1, move.from, move.to, cardName(verify_board.cardInSlot(move.from)) });
                    if (!verify_board.isValidMove(move)) {
                        std.debug.print("    INVALID MOVE!\n", .{});
                        break;
                    }
                    verify_board.makeMove_noSorting(move);
                }
                std.debug.print("\nVerification: Final board is solved: {}\n", .{verify_board.isWon()});
            } else {
                std.debug.print("FAIL! Could not solve board.\n", .{});
                std.debug.print("Foundation piles: {} {} {} {}\n", .{ game_board.piles[0], game_board.piles[1], game_board.piles[2], game_board.piles[3] });
            }
        } else {
            try stdout.print(" {d:04}: {} {d:>5} {d:>7}\n", .{ seed, found, path_length, iters });
            try stdout.flush();
        }

        _ = arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
    }
    const time_end = std.Io.Clock.now(std.Io.Clock.real, init.io);
    try stdout.print("Total path length: {}, total iterations: {}, reallocs: {}\n", .{ total_length, total_iters, board.num_reallocations });
    try stdout.print("Total time: {} ms\n", .{@as(f64, @floatFromInt(time_end.toMicroseconds() - time_start.toMicroseconds())) / 1000.0});
    try stdout.flush();
}
