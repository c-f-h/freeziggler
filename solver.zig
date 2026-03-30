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

const AStarNode = struct {
    board: Board,
    heuristic_value: u16,
    best_cost: u16, // Shortest known number of moves to reach this state
    parent_hash: u64, // Hash of parent state which achieves the lowest known cost
    move: Move, // Move taken from parent state to reach this state
};

fn nodePriority(node_map: *std.AutoHashMap(u64, AStarNode), hash: u64) u32 {
    if (node_map.getPtr(hash)) |node| {
        return @as(u32, node.best_cost) + @as(u32, node.heuristic_value);
    }
    return std.math.maxInt(u32);
}

fn bpCompare(node_map: *std.AutoHashMap(u64, AStarNode), a: u64, b: u64) std.math.Order {
    const a_priority = nodePriority(node_map, a);
    const b_priority = nodePriority(node_map, b);
    if (a_priority > b_priority) {
        return std.math.Order.gt;
    } else if (a_priority < b_priority) {
        return std.math.Order.lt;
    } else {
        return std.math.Order.eq;
    }
}

// Data for closed nodes - only required to reconstruct solution path
const AStarClosedNode = struct {
    parent_hash: u64,
    move: Move,
};

fn solveAStar(starting_board: *Board, allocator: std.mem.Allocator, path: *Path) !struct { bool, usize } {
    // Hash map of nodes yet to be visited
    var open_set = std.AutoHashMap(u64, AStarNode).init(allocator);
    defer open_set.deinit();

    // Hash map of already visited nodes
    var closed_set = std.AutoHashMap(u64, AStarClosedNode).init(allocator);
    defer closed_set.deinit();

    var pqueue = std.PriorityQueue(u64, *std.AutoHashMap(u64, AStarNode), bpCompare).initContext(&open_set);

    const start_hash = starting_board.hash();
    try open_set.put(start_hash, AStarNode{
        .board = starting_board.*,
        .heuristic_value = heuristic(starting_board),
        .best_cost = 0,
        .parent_hash = 0,
        .move = Move{ .from = 0, .to = 0 },
    });
    try pqueue.push(allocator, start_hash);

    var move_buffer: [128]Move = undefined;

    var num_iter: u32 = 0;
    var solution_hash: u64 = 0;

    while (pqueue.pop()) |cur_hash| {
        // We might have duplicate nodes due to inserting shorter paths to a node afterwards
        const cur_node = open_set.get(cur_hash) orelse continue;

        // move node from open to closed set
        _ = open_set.remove(cur_hash);
        try closed_set.put(cur_hash, .{
            .parent_hash = cur_node.parent_hash,
            .move = cur_node.move,
        });

        const board = &cur_node.board;

        if (isWon(board)) {
            solution_hash = cur_hash;
            break;
        }

        const valid_moves = board.findValidMoves(&move_buffer);

        num_iter += 1;
        if (num_iter % 100000 == 0) {
            std.debug.print("Iteration {d}, queue length {d}, {d} hashes, found {d} valid moves:\n", .{ num_iter, pqueue.count(), closed_set.count(), valid_moves.len });
            board.print();
            printMoves(valid_moves);
        }

        for (valid_moves) |move| {
            var new_board = board.*;
            new_board.makeMove(move);

            const new_hash = new_board.hash();
            const new_cost = cur_node.best_cost + 1;

            // check if we already found another path to this node
            const existing_node = open_set.getPtr(new_hash);

            if (existing_node) |nn| {
                // is already an open node - check if this path is better than the previously known one
                if (new_cost < nn.best_cost) {
                    nn.best_cost = new_cost;
                    nn.parent_hash = cur_hash;
                    nn.move = move;
                    // board state and heuristic are unchanged

                    // push a new (duplicate) entry to the pqueue to force reordering
                    try pqueue.push(allocator, new_hash);
                }
            } else if (!closed_set.contains(new_hash)) {
                // not in closed set - add to open set
                try open_set.put(new_hash, AStarNode{
                    .board = new_board,
                    .heuristic_value = heuristic(&new_board),
                    .best_cost = new_cost,
                    .parent_hash = cur_hash,
                    .move = move,
                });
                try pqueue.push(allocator, new_hash);
            }
        }
    }

    // Reconstruct path by tracing back through parent pointers
    if (solution_hash != 0) {
        var current_hash = solution_hash;
        while (current_hash != start_hash) {
            const path_node = closed_set.getPtr(current_hash) orelse break;
            try path.append(allocator, path_node.move);
            current_hash = path_node.parent_hash;
        }
        return .{ true, open_set.count() + closed_set.count() };
    }

    return .{ false, open_set.count() + closed_set.count() };
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

    const result = try solveAStar(&board, allocator, path);
    if (result[0]) {
        std.mem.reverse(Move, path.items);
    }
    return result;
}

fn printMoves(moves: []const Move) void {
    for (moves) |move| {
        std.debug.print("  slot {d} -> slot {d}\n", .{ move.from, move.to });
    }
}
