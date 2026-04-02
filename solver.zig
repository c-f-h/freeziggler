const std = @import("std");
const board_mod = @import("board.zig");
const card_mod = @import("card.zig");
const freecell_mod = @import("freecell.zig");

const Board = board_mod.Board;
const Move = board_mod.Move;
const Card = card_mod.Card;
const CARD_NONE = card_mod.CARD_NONE;
const canMoveBelow = card_mod.canMoveBelow;
const NUM_COLUMNS = board_mod.NUM_COLUMNS;
const makeCard = board_mod.makeCard;

const verbose = freecell_mod.verbose;

pub const Path = std.ArrayList(Move);

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

pub noinline fn solveAStar(starting_board: *const Board, allocator: std.mem.Allocator, path: *Path) !struct { bool, usize } {
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

        if (board.isWon()) {
            solution_hash = cur_hash;
            break;
        }

        const valid_moves = board.findValidMoves(&move_buffer);

        num_iter += 1;
        if (verbose and num_iter % 100000 == 0) {
            std.debug.print("Iteration {d}, queue length {d}, {d} hashes, found {d} valid moves\n", .{ num_iter, pqueue.count(), closed_set.count(), valid_moves.len });
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
        std.mem.reverse(Move, path.items);
        return .{ true, open_set.count() + closed_set.count() };
    }

    return .{ false, open_set.count() + closed_set.count() };
}

const MovePair = struct { move: Move, heuristic: u16 };

fn compareMoves(_: void, a: MovePair, b: MovePair) bool {
    return a.heuristic < b.heuristic;
}

fn solveDFSRecursive(board: *const Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator, path: *Path) !bool {
    if (board.isWon()) {
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
        if (try solveDFSRecursive(&new_board, visited, allocator, path)) {
            try path.append(allocator, move);
            return true;
        }
    }

    return false;
}

pub fn solveDFS(board: *const Board, allocator: std.mem.Allocator, path: *Path) !struct { bool, usize } {
    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const solved = try solveDFSRecursive(board, &visited, allocator, path);
    if (solved) {
        std.mem.reverse(Move, path.items);
    }
    return .{ solved, visited.count() };
}

fn solveBestFirstSearchRecursive(board: *const Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator, path: *Path) !bool {
    const DFS_BUFFER_SIZE = 512;
    if (board.isWon()) {
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
        if (try solveBestFirstSearchRecursive(&new_board, visited, allocator, path)) {
            try path.append(allocator, move);
            return true;
        }
    }

    return false;
}

pub fn solveBestFirstSearch(board: *const Board, allocator: std.mem.Allocator, path: *Path) !struct { bool, usize } {
    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const solved = try solveBestFirstSearchRecursive(board, &visited, allocator, path);
    if (solved) {
        std.mem.reverse(Move, path.items);
    }
    return .{ solved, visited.count() };
}

fn printMoves(moves: []const Move) void {
    for (moves) |move| {
        std.debug.print("  slot {d} -> slot {d}\n", .{ move.from, move.to });
    }
}

pub fn improvePath(board: *const Board, path: *Path, max_attempts: usize, allocator: std.mem.Allocator) !bool {
    var known_nodes = std.AutoHashMap(u64, AStarNode).init(allocator);
    defer known_nodes.deinit();

    var path_hashes = try allocator.alloc(u64, path.items.len + 1);
    defer allocator.free(path_hashes);

    // init known nodes and path_hashes
    {
        var current_board = board.*;
        var prev_hash: u64 = current_board.hash();

        // insert a node for the original board state
        try known_nodes.put(prev_hash, AStarNode{
            .board = current_board,
            .heuristic_value = 1, // 1 = node known to lead to a solution
            .best_cost = 0,
            .parent_hash = 0,
            .move = Move{ .from = 0, .to = 0 },
        });

        // path_hashes[i] = hash of board state after making moves path[0..i]
        path_hashes[0] = prev_hash;

        // insert nodes for the current best known path
        for (path.items, 1..) |move, state_index| {
            current_board.makeMove(move);
            const board_hash = current_board.hash();
            path_hashes[state_index] = board_hash;

            try known_nodes.put(board_hash, AStarNode{
                .board = current_board,
                .heuristic_value = 1, // node known to lead to a solution
                .best_cost = @intCast(state_index),
                .parent_hash = prev_hash,
                .move = move,
            });

            prev_hash = board_hash;
        }
    }

    var queue = try std.Deque(u64).initCapacity(allocator, 1024);
    defer queue.deinit(allocator);

    // seed breadth-first search from a subset of nodes on the known solution path
    var i: usize = 0;
    while (i < path_hashes.len) : (i += 15) {
        try queue.pushFront(allocator, path_hashes[i]);
    }

    var attempt: u32 = 0;
    var success = false;

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();

    // use breadth-first search to try to find a shortcut to a node on the known solution path
    outer_loop: while (attempt < max_attempts) : (attempt += 1) {
        // pop a node from the queue and explore its neighbors
        const cur_hash = queue.popBack() orelse break;
        // NB: cannot use getPtr here as put() later on may invalidate the pointer
        const cur_node = known_nodes.get(cur_hash) orelse @panic("Hash from queue not found in known nodes");
        const cur_board = &cur_node.board;

        if ((try visited.getOrPut(cur_hash)).found_existing) {
            continue;
        }

        var move_buffer: [64]Move = undefined;
        const valid_moves = cur_board.findValidMoves(&move_buffer);

        for (valid_moves) |move| {
            // compute board state and hash after move
            var new_board = cur_board.*;
            new_board.makeMove(move);
            const new_hash = new_board.hash();

            if (visited.contains(new_hash)) {
                continue;
            }

            // have we seen this board state before?
            if (known_nodes.getPtr(new_hash)) |existing| {
                // already known node - check if this is a shorter path to a solution
                if (cur_node.best_cost + 1 < existing.best_cost) {
                    if (existing.heuristic_value != 0) {
                        std.debug.print("Found improved path to node with hash {x} after {d} attempts: old cost = {d}, new cost = {d}\n", .{ new_hash & 0xffff, attempt, existing.best_cost, cur_node.best_cost + 1 });
                        success = true;
                    }

                    existing.best_cost = cur_node.best_cost + 1;
                    existing.parent_hash = cur_hash;
                    existing.move = move;

                    if (success) {
                        break :outer_loop;
                    }
                }
            } else {
                // new node - add to known nodes
                try known_nodes.put(new_hash, AStarNode{
                    .board = new_board,
                    .heuristic_value = 0,
                    .best_cost = cur_node.best_cost + 1,
                    .parent_hash = cur_hash,
                    .move = move,
                });
            }
            try queue.pushFront(allocator, new_hash);
        }
    }

    if (success) {
        // reconstruct improved path
        var idx: usize = 0;
        var hash = path_hashes[path_hashes.len - 1];
        while (true) {
            const node = known_nodes.getPtr(hash) orelse @panic("Failed to reconstruct improved path");
            if (node.parent_hash == 0) break;
            path.items[idx] = node.move;
            idx += 1;
            hash = node.parent_hash;
        }
        if (idx > path.items.len) @panic("Improved path is longer than original path");
        try path.resize(allocator, idx);
        std.mem.reverse(Move, path.items);
        return true;
    } else {
        std.debug.print("No improved path found after {d} attempts\n", .{attempt});
        return false;
    }
}

/// Given the original and the sorted game board, remap the path for the sorted board back to the original board's column indices.
pub fn remapPath(original_board: *const Board, remapped_board: *const Board, path: []Move, orig_path: *[]Move) void {
    if (orig_path.len < path.len) @panic("Real path buffer too small");
    orig_path.len = 0;
    var orig = original_board.*;
    var remapped = remapped_board.*;
    for (path) |move| {
        const card = remapped.cardInSlot(move.from);
        const orig_from = orig.findSlotContainingCard(card) orelse @panic("Card not found in original board");

        var orig_to: u8 = undefined;
        if (move.to < NUM_COLUMNS) {
            const below_card = remapped.cardInSlot(move.to);
            if (below_card != CARD_NONE) {
                orig_to = orig.findSlotContainingCard(below_card) orelse @panic("Below card not found in original board");
            } else {
                // Moving to an empty column - find the first empty column in the original board
                orig_to = orig.findEmptyColumn() orelse @panic("No empty column found in original board");
            }
        } else if (move.to < NUM_COLUMNS + 4) {
            // Moving to a free cell - find the first empty free cell in the original board
            orig_to = orig.findEmptyFreeCell() orelse @panic("No empty free cell found in original board");
        } else {
            orig_to = move.to; // Moving to a foundation pile - same index in original and remapped board
        }

        const orig_move = Move{ .from = orig_from, .to = orig_to };
        if (!orig.isValidMove(orig_move)) @panic("Invalid move in original board");
        orig_path.len += 1;
        orig_path.*[orig_path.len - 1] = orig_move;
        orig.makeMove_noSorting(orig_move);
        remapped.makeMove(move);
    }
}
