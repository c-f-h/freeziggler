const std = @import("std");
const board_mod = @import("board.zig");
const card_mod = @import("card.zig");

const Board = board_mod.Board;
const Move = board_mod.Move;
const Card = card_mod.Card;
const CARD_NONE = card_mod.CARD_NONE;
const canMoveBelow = card_mod.canMoveBelow;
const NUM_COLUMNS = board_mod.NUM_COLUMNS;
const makeCard = board_mod.makeCard;

pub const Path = std.ArrayList(Move);

pub fn isWon(board: *const Board) bool {
    return board.piles[0] == 13 and board.piles[1] == 13 and board.piles[2] == 13 and board.piles[3] == 13;
}

const BoardNode = struct { board_hash: u64, num_moves: u16, heuristic_value: u16 };

const heuristic = heuristic_numNonMatching;

fn heuristic_numBlocked(board: *const Board) u16 {
    var blocked: u16 = 0;
    for (board.columns) |col| {
        const num_in_col = col[1] - col[0];
        if (num_in_col > 1) {
            blocked += num_in_col - 1;
        }
    }
    return board.numRemainingCards() + 2 * blocked;
}

fn heuristic_numNonMatching(board: *const Board) u16 {
    var count: u16 = 0;
    for (board.columns) |col| {
        const num_in_col = col[1] - col[0];
        if (num_in_col > 1) {
            for (col[0]..col[1] - 1) |idx| {
                if (!canMoveBelow(board.cards[idx + 1], board.cards[idx]))
                    count += 1;
            }
        }
    }
    return heuristic_numBlocked(board) + 1 * count;
}

fn bpCompare(_: void, a: BoardNode, b: BoardNode) std.math.Order {
    const a_priority = @as(u16, a.num_moves) + a.heuristic_value;
    const b_priority = @as(u16, b.num_moves) + b.heuristic_value;
    if (a_priority > b_priority) {
        return std.math.Order.gt;
    } else if (a_priority < b_priority) {
        return std.math.Order.lt;
    } else {
        return std.math.Order.eq;
    }
}

fn solveAStar(starting_board: *Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator, path: *Path) !bool {
    var pqueue = std.PriorityQueue(BoardNode, void, bpCompare).initContext({});

    var open_set = std.AutoHashMap(u64, Board).init(allocator);
    defer open_set.deinit();

    // Track best known distance to each state
    var best_cost = std.AutoHashMap(u64, u16).init(allocator);
    defer best_cost.deinit();

    // Track parent hash and move for path reconstruction
    const PathNode = struct { parent_hash: u64, move: Move };
    var parent_map = std.AutoHashMap(u64, PathNode).init(allocator);
    defer parent_map.deinit();

    const start_hash = starting_board.hash();
    try pqueue.push(allocator, BoardNode{ .board_hash = start_hash, .num_moves = 0, .heuristic_value = heuristic(starting_board) });
    try open_set.put(start_hash, starting_board.*);
    try best_cost.put(start_hash, 0);

    var move_buffer: [128]Move = undefined;

    var num_iter: u32 = 0;
    var solution_hash: u64 = 0;

    while (pqueue.pop()) |cur_node| {
        const cur_hash = cur_node.board_hash;
        const board = &open_set.get(cur_hash).?;

        if (isWon(board)) {
            solution_hash = cur_hash;
            break;
        }

        if (visited.contains(cur_hash)) {
            continue;
        }

        // Only continue if this is the best path we have found to this node so far
        if (best_cost.get(cur_hash)) |known_cost| {
            if (cur_node.num_moves > known_cost) {
                continue;
            }
        }

        try visited.put(cur_hash, {});

        const valid_moves = board.findValidMoves(&move_buffer);

        num_iter += 1;
        if (num_iter % 100000 == 0) {
            std.debug.print("Iteration {d}, queue length {d}, {d} hashes, found {d} valid moves:\n", .{ num_iter, pqueue.count(), visited.count(), valid_moves.len });
            board.print();
            printMoves(valid_moves);
        }

        for (valid_moves) |move| {
            var new_board = board.*;
            new_board.makeMove(move);

            const new_hash = new_board.hash();
            const new_cost = cur_node.num_moves + 1;

            // Only add to queue if we found a better path (or haven't seen this state)
            if (best_cost.get(new_hash)) |known_cost| {
                if (new_cost < known_cost) {
                    try best_cost.put(new_hash, new_cost);
                    try parent_map.put(new_hash, PathNode{ .parent_hash = cur_node.board_hash, .move = move });
                    try pqueue.push(allocator, BoardNode{ .board_hash = new_hash, .num_moves = new_cost, .heuristic_value = heuristic(&new_board) });
                }
            } else if (!visited.contains(new_hash)) {
                try best_cost.put(new_hash, new_cost);
                try open_set.put(new_hash, new_board);
                try parent_map.put(new_hash, PathNode{ .parent_hash = cur_node.board_hash, .move = move });
                try pqueue.push(allocator, BoardNode{ .board_hash = new_hash, .num_moves = new_cost, .heuristic_value = heuristic(&new_board) });
            }
        }
    }

    // Reconstruct path by tracing back through parent pointers
    if (solution_hash != 0) {
        var current_hash = solution_hash;
        while (parent_map.get(current_hash)) |path_node| {
            try path.append(allocator, path_node.move);
            current_hash = path_node.parent_hash;
        }
        return true;
    }

    return false;
}

const MovePair = struct { move: Move, heuristic: u16 };

fn compareMoves(_: void, a: MovePair, b: MovePair) bool {
    return a.heuristic < b.heuristic;
}

fn solveDFS(board: *Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator, path: *Path) !bool {
    if (isWon(board)) {
        return true;
    }

    const board_hash = board.hash();
    if (visited.contains(board_hash)) {
        return false;
    }
    try visited.put(board_hash, {});

    var move_buffer: [64]Move = undefined;
    const valid_moves = board.findValidMoves(&move_buffer);

    for (valid_moves) |move| {
        var new_board = board.*;
        new_board.makeMove(move);
        if (try solveDFS(&new_board, visited, allocator, path)) {
            try path.append(allocator, move);
            return true;
        }
    }

    return false;
}

fn solveBestFirstSearch(board: *Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator, path: *Path) !bool {
    const DFS_BUFFER_SIZE = 512;
    if (isWon(board)) {
        return true;
    }

    const board_hash = board.hash();
    if (visited.contains(board_hash)) {
        return false;
    }
    try visited.put(board_hash, {});

    var stack_buf: [DFS_BUFFER_SIZE]u8 = undefined;
    var stack_alloc = std.heap.FixedBufferAllocator.init(&stack_buf);

    const move_buffer = stack_alloc.allocator().alloc(Move, 128) catch @panic("DFS stack buffer overflow");
    const valid_moves = board.findValidMoves(move_buffer);
    var move_heuristic = stack_alloc.allocator().alloc(MovePair, valid_moves.len) catch @panic("DFS stack buffer overflow");

    for (valid_moves, 0..) |move, i| {
        var new_board = board.*;
        new_board.makeMove(move);
        move_heuristic[i] = MovePair{ .move = move, .heuristic = heuristic(&new_board) };
    }

    std.mem.sort(MovePair, move_heuristic, {}, compareMoves);

    for (move_heuristic) |*move_pair| {
        const move = move_pair.move;
        var new_board = board.*;
        new_board.makeMove(move);
        if (try solveBestFirstSearch(&new_board, visited, allocator, path)) {
            try path.append(allocator, move);
            return true;
        }
    }

    return false;
}

pub fn solveFreeCell(initial_board: Board, allocator: std.mem.Allocator, path: *Path) !struct { bool, usize } {
    var board = initial_board;
    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();

    const found = try solveAStar(&board, &visited, allocator, path);
    if (found) {
        std.mem.reverse(Move, path.items);
    }
    return .{ found, visited.count() };
}

fn printMoves(moves: []const Move) void {
    for (moves) |move| {
        std.debug.print("  slot {d} -> slot {d}\n", .{ move.from, move.to });
    }
}
