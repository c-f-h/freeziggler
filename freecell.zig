const std = @import("std");

const verbose = true;

pub const KEEP_FREECELLS_SORTED = true; // If true, keeps free cells sorted by card value to deduplicate equivalent states
pub const KEEP_COLUMNS_SORTED = true; // If true, keeps columns sorted by anchor card (rear-most) to deduplicate equivalent states

const heuristic = heuristic_numNonMatching;

var num_reallocations: u64 = 0;

pub const Card = u8;
pub const CARD_NONE: Card = 0; // Represents no card or an empty slot

// hearts (♥), diamonds (♦), clubs (♣), spades (♠)

pub const RED_BIT: u8 = 1 << 7;

pub fn color(c: Card) u8 {
    return c & RED_BIT;
}

pub const Suit = enum(u8) {
    Spades = 0,
    Clubs = (1 << 6),
    Hearts = RED_BIT | (0),
    Diamonds = RED_BIT | (1 << 6),
};

// index in the suit order (0-3)
pub fn suitIndex(suit: Suit) usize {
    return @intFromEnum(suit) >> 6;
}

pub fn makeCard(suit: Suit, rank: u8) Card {
    return @intFromEnum(suit) | rank;
}

pub fn suitString(suit: Suit) []const u8 {
    return switch (suit) {
        .Spades => "S",
        .Clubs => "C",
        .Hearts => "H",
        .Diamonds => "D",
        //.Spades => "♠",
        //.Clubs => "♣",
        //.Hearts => "♥",
        //.Diamonds => "♦",
    };
}

pub fn rankName(rank: u8) u8 {
    return switch (rank) {
        1 => 'A',
        10 => '0',
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        else => '0' + rank,
    };
}

pub fn canMoveBelow(card: Card, target: Card) bool {
    const cardRank = card & 0b0000_1111;
    const targetRank = target & 0b0000_1111;

    return (color(card) != color(target)) and (cardRank == targetRank - 1);
}

fn printCard(card: Card) void {
    if (card == CARD_NONE) {
        std.debug.print("  ", .{});
        return;
    }
    const rank = card & 0b0000_1111; // lower 4 bits for rank
    const suit: Suit = @enumFromInt(card & 0b1100_0000); // upper 2 bits for suit

    std.debug.print("{s}{c}", .{ suitString(suit), rankName(rank) });
}

pub fn bubbleIntoPlace(arr: *[4]u8, index: u8) void {
    var i = index;
    while (i > 0 and arr[i - 1] > arr[i]) : (i -= 1) {
        const temp = arr[i - 1];
        arr[i - 1] = arr[i];
        arr[i] = temp;
    }
    while (i < 3 and arr[i + 1] < arr[i]) : (i += 1) {
        const temp = arr[i + 1];
        arr[i + 1] = arr[i];
        arr[i] = temp;
    }
}

var str_buffer: [8]u8 = undefined; // Temporary buffer for card name

fn cardName(card: Card) []const u8 {
    if (card == CARD_NONE) {
        return "  ";
    }
    const rank = card & 0b0000_1111; // lower 4 bits for rank
    const suit: Suit = @enumFromInt(card & 0b1100_0000); // upper 2 bits for suit

    if (std.fmt.bufPrint(&str_buffer, "{s}{c}", .{ suitString(suit), rankName(rank) })) |name| {
        return name;
    } else |_| {
        return "  ";
    }
}

pub const NUM_COLUMNS = 8;
pub const TABLEAU_SIZE = 64; // should be at least 60

pub const Board = struct {
    cells: [4]Card = [_]Card{CARD_NONE} ** 4, // Free cells
    piles: [4]u8 = [_]u8{0} ** 4, // Foundation piles (top card rank)
    columns: [NUM_COLUMNS][2]u8 = .{ .{ 0, 7 }, .{ 7, 14 }, .{ 14, 21 }, .{ 21, 28 }, .{ 28, 34 }, .{ 34, 40 }, .{ 40, 46 }, .{ 46, 52 } }, // Column ranges (start, end)
    cards: [TABLEAU_SIZE]Card = [_]Card{CARD_NONE} ** TABLEAU_SIZE, // Cards in the tableau

    pub fn init(deck: *[52]Card) Board {
        var board: Board = .{};
        var idx: u8 = 0;
        while (idx < 52) : (idx += 1) {
            board.cards[idx] = deck[idx];
        }
        if (KEEP_COLUMNS_SORTED) {
            board.sortColumns();
        }
        return board;
    }

    pub fn initFromColumns(columns: [NUM_COLUMNS][]Card) Board {
        var board: Board = .{};
        var idx: u8 = 0;
        var j: u8 = 0;
        while (j < NUM_COLUMNS) : (j += 1) {
            const col = columns[j];
            board.columns[j][0] = idx;
            for (col) |card| {
                if (idx < TABLEAU_SIZE) {
                    board.cards[idx] = card;
                    idx += 1;
                } else {
                    @panic("Too many cards in tableau");
                }
            }
            board.columns[j][1] = idx;
        }
        if (KEEP_COLUMNS_SORTED) {
            board.sortColumns();
        }
        return board;
    }

    // slots: columns 0-7, free cells 8-11, foundation piles 12-15

    pub fn cardInSlot(board: *const Board, slot: u8) Card {
        if (slot < NUM_COLUMNS) {
            const col = board.columns[slot];
            if (col[0] < col[1]) {
                return board.cards[col[1] - 1]; // Top card of the column
            }
        } else if (slot < NUM_COLUMNS + 4) {
            return board.cells[slot - NUM_COLUMNS]; // Free cell
        } else if (slot < NUM_COLUMNS + 8) {
            const pileIndex = slot - NUM_COLUMNS - 4;
            if (board.piles[pileIndex] > 0) {
                return makeCard(@enumFromInt(pileIndex << 6), board.piles[pileIndex]); // Top card of the foundation pile
            }
        }
        return CARD_NONE; // Empty slot
    }

    pub fn numCardsInColumn(board: *const Board, column: u8) u8 {
        return board.columns[column][1] - board.columns[column][0];
    }

    pub fn numCardsOnTableau(board: *const Board) u8 {
        var total: u8 = 0;
        for (board.columns) |col| {
            total += col[1] - col[0];
        }
        return total;
    }

    pub fn numRemainingCards(board: *const Board) u8 {
        return 52 - board.piles[0] - board.piles[1] - board.piles[2] - board.piles[3];
    }

    /// Checks if the column is full (i.e., has no free spaces for moving cards into it
    pub fn columnIsFull(board: *const Board, column: u8) bool {

        // Original implementation: relies on columns being stored in increasing order
        //if (column == NUM_COLUMNS - 1) {
        //    return board.columns[column][1] == TABLEAU_SIZE;
        //} else {
        //    return board.columns[column][1] == board.columns[column + 1][0];
        //}

        const next_idx = board.columns[column][1];
        if (next_idx >= TABLEAU_SIZE) {
            return true;
        }

        // A column is full when extending it would overwrite any occupied tableau slot.
        for (board.columns, 0..) |other_col, i| {
            if (i == column) continue;
            if (other_col[0] <= next_idx and next_idx < other_col[1]) {
                return true;
            }
        }

        return false;
    }

    /// Guarantees that there are free spaces between columns for moving cards around
    pub fn reallocateColumns(board: *Board) void {
        const old_cards = board.cards;
        const old_columns = board.columns;
        const num_free_places = TABLEAU_SIZE - board.numCardsOnTableau();
        const free_per_column = @divTrunc(num_free_places, NUM_COLUMNS);
        if (free_per_column == 0) {
            @panic("Cannot reallocate columns: no free space available");
        }
        var idx: u8 = 0;
        for (&board.columns, 0..) |*col, j| {
            col[0] = idx;
            col[1] = idx + old_columns[j][1] - old_columns[j][0];
            @memcpy(board.cards[col[0]..col[1]], old_cards[old_columns[j][0]..old_columns[j][1]]);
            idx = col[1] + free_per_column; // Add free spaces between columns
        }
        num_reallocations += 1;
    }

    pub fn takeCardFromSlot(board: *Board, slot: u8) Card {
        const card = board.cardInSlot(slot);
        if (card == CARD_NONE) return CARD_NONE; // No card to take

        // Remove card from source
        if (slot < NUM_COLUMNS) {
            // Taking from a column
            board.columns[slot][1] -= 1;
        } else if (slot < NUM_COLUMNS + 4) {
            // Taking from a free cell
            board.cells[slot - NUM_COLUMNS] = CARD_NONE;
            if (KEEP_FREECELLS_SORTED)
                bubbleIntoPlace(&board.cells, slot - NUM_COLUMNS);
        } else if (slot < NUM_COLUMNS + 8) {
            // Taking from a foundation pile
            const pileIndex = slot - NUM_COLUMNS - 4;
            board.piles[pileIndex] -= 1;
        }

        return card;
    }

    pub fn putCardInSlot(board: *Board, slot: u8, card: Card) void {
        if (slot < NUM_COLUMNS) {
            // Putting into a column
            // Check if target column is full and reallocate if needed
            if (board.columnIsFull(slot)) {
                board.reallocateColumns();
            }
            board.cards[board.columns[slot][1]] = card;
            board.columns[slot][1] += 1;
        } else if (slot < NUM_COLUMNS + 4) {
            // Putting into a free cell
            board.cells[slot - NUM_COLUMNS] = card;
            if (KEEP_FREECELLS_SORTED)
                bubbleIntoPlace(&board.cells, slot - NUM_COLUMNS);
        } else if (slot < NUM_COLUMNS + 8) {
            // Putting into a foundation pile
            const pileIndex = slot - NUM_COLUMNS - 4;
            board.piles[pileIndex] += 1;
        }
    }

    pub fn makeMove(board: *Board, move: Move) void {
        const card = board.takeCardFromSlot(move.from);
        if (card == CARD_NONE) @panic("invalid move"); // No card to move
        board.putCardInSlot(move.to, card);

        if (KEEP_COLUMNS_SORTED and !board.columnsAreSorted()) {
            board.sortColumns();
        }
    }

    pub fn print(board: *const Board) void {
        std.debug.print("  |", .{});
        for (board.cells) |cell| {
            printCard(cell);
            std.debug.print("|", .{});
        }

        std.debug.print("         |", .{});
        for (board.piles, 0..) |pile, i| {
            if (pile > 0) {
                const suit: Suit = @enumFromInt(i << 6); // Get suit from pile index
                printCard(makeCard(suit, pile)); // Print top card of the pile
            } else {
                std.debug.print("  ", .{});
            }
            std.debug.print("|", .{});
        }

        std.debug.print("\n\nColumns:\n", .{});
        var row: u8 = 0;
        var more = true;
        while (more) : (row += 1) {
            more = false;
            var col: u8 = 0;
            while (col < 8) : (col += 1) {
                if (row < board.columns[col][1] - board.columns[col][0]) {
                    printCard(board.cards[board.columns[col][0] + row]);
                    more = true;
                } else {
                    std.debug.print("  ", .{});
                }
                std.debug.print(" ", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn isValidMove(board: *const Board, move: Move) bool {
        const from = move.from;
        const to = move.to;

        if (from == to)
            return false;

        const card = board.cardInSlot(from);
        if (card == CARD_NONE)
            return false;

        const target = board.cardInSlot(to);

        if (to < NUM_COLUMNS) {
            // Destination is column - either empty or can move if alternating color and descending rank
            return target == CARD_NONE or canMoveBelow(card, target);
        } else if (to < NUM_COLUMNS + 4) {
            // Destination is free cell - must be empty
            return target == CARD_NONE;
        } else {
            // Destination is foundation pile
            const pile_index = to - NUM_COLUMNS - 4;
            const card_rank = card & 0b0000_1111;
            const card_suit_bits = card & 0b1100_0000;

            // Can move if the card rank is one more than current pile top and suits match
            return (card_rank == board.piles[pile_index] + 1 and card_suit_bits == @as(u8, @intCast(pile_index << 6)));
        }
    }

    /// Find all valid moves (from any slot to any other slot).
    /// Takes a buffer of Move structs and returns a slice into it containing the valid moves
    pub fn findValidMoves(board: *const Board, buffer: []Move) []Move {
        var count: usize = 0;

        // Check source slots from columns and free cells (always 0-11)
        var from: u8 = 0;
        while (from < NUM_COLUMNS + 4) : (from += 1) {
            const card = board.cardInSlot(from);
            if (card == CARD_NONE) continue;

            // Check all destination slots (columns, free cells, foundation)
            var to: u8 = 0;
            // For free cells and free columns, generate only one move to avoid duplicates
            var free_cell_move_generated = false;
            var free_column_move_generated = false;

            while (to < NUM_COLUMNS + 8) : (to += 1) {
                if (from == to) continue;

                const target = board.cardInSlot(to);
                var is_valid = false;

                if (to < NUM_COLUMNS) {
                    // Destination is column
                    if ((target == CARD_NONE and !free_column_move_generated) or (target != CARD_NONE and canMoveBelow(card, target))) {
                        // Can move to column if alternating color and descending rank
                        is_valid = true;
                        if (target == CARD_NONE) {
                            free_column_move_generated = true;
                        }
                    }
                } else if (to < NUM_COLUMNS + 4) {
                    // Destination is free cell
                    if (target == CARD_NONE and !free_cell_move_generated) {
                        // Can move to free cell if it's empty
                        is_valid = true;
                        free_cell_move_generated = true;
                    }
                } else {
                    // Destination is foundation pile
                    const pile_index = to - NUM_COLUMNS - 4;
                    const card_rank = card & 0b0000_1111;
                    const card_suit_bits = card & 0b1100_0000;

                    // Can move if the card rank is one more than current pile top and suits match
                    if (card_rank == board.piles[pile_index] + 1 and card_suit_bits == @as(u8, @intCast(pile_index << 6))) {
                        is_valid = true;
                    }
                }

                if (is_valid) {
                    if (count < buffer.len) {
                        buffer[count] = Move{ .from = from, .to = to };
                        count += 1;
                    } else {
                        @panic("findValidMoves: insufficient buffer space");
                    }
                }
            }
        }

        return buffer[0..count];
    }

    /// The "anchor card" is the rear-most card in a column, i.e., the card that is hardest to move.
    pub fn anchorCard(board: *const Board, col: u8) Card {
        if (board.columns[col][0] < board.columns[col][1]) {
            return board.cards[board.columns[col][0]];
        } else {
            return CARD_NONE;
        }
    }

    /// Check if the columns are sorted w.r.t. their anchor cards
    pub fn columnsAreSorted(board: *const Board) bool {
        for (0..NUM_COLUMNS - 1) |col| {
            const j: u8 = @intCast(col);
            if (board.anchorCard(j) > board.anchorCard(j + 1)) {
                return false;
            }
        }
        return true;
    }

    pub fn sortColumns(board: *Board) void {
        // Simple bubble sort since NUM_COLUMNS is small
        for (0..NUM_COLUMNS) |i| {
            for (0..NUM_COLUMNS - 1 - i) |jj| {
                const j: u8 = @intCast(jj);
                if (board.anchorCard(j) > board.anchorCard(j + 1)) {
                    const temp = board.columns[j];
                    board.columns[j] = board.columns[j + 1];
                    board.columns[j + 1] = temp;
                }
            }
        }
    }

    /// Returns a hash of the board state for use in hash maps or detecting duplicate positions
    pub fn hash(board: *const Board) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Hash free cells
        hasher.update(&board.cells);

        // Hash foundation piles
        hasher.update(&board.piles);

        const delimiter = [1]u8{0xFF};

        // Hash only the cards that are on the tableau (between start and end of each column)
        for (board.columns) |col| {
            const start = col[0];
            const end = col[1];
            if (start < end) {
                hasher.update(board.cards[start..end]);
            }
            // hash column delimiter
            hasher.update(&delimiter);
        }

        return hasher.final();
    }
};

pub fn makeDeck() [52]Card {
    var cards: [52]Card = undefined;
    var index: usize = 0;

    for (std.enums.values(Suit)) |suit| {
        var rank: u8 = 1;
        while (rank <= 13) : (rank += 1) {
            cards[index] = makeCard(suit, rank);
            index += 1;
        }
    }

    return cards;
}

// ============================================================================
// Freecell Solver
// ============================================================================

pub const Move = struct {
    from: u8,
    to: u8,
};

pub const Path = std.ArrayList(Move);

/// Check if the board is in a winning state (all 52 cards in foundation piles)
pub fn isWon(board: *const Board) bool {
    return board.piles[0] == 13 and board.piles[1] == 13 and board.piles[2] == 13 and board.piles[3] == 13;
}

const BoardNode = struct { board_hash: u64, num_moves: u16, heuristic_value: u16 };

const heuristic_naive = Board.numRemainingCards;

fn heuristic_numBlocked(board: *const Board) u16 {
    // Count cards blocked under other cards in columns
    var blocked: u16 = 0;
    for (board.columns) |col| {
        // All but the top card in each column are blocked
        const num_in_col = col[1] - col[0];
        if (num_in_col > 1) {
            blocked += num_in_col - 1;
        }
    }

    // Blocked cards have higher penalty since they're harder to move
    return board.numRemainingCards() + 2 * blocked;
}

fn heuristic_numNonMatching(board: *const Board) u16 {
    // Count cards that are not yet in the foundation piles and are not Aces (i.e., not yet "free")
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

    // Store boards in a map keyed by their hash to avoid storing full boards in queue nodes
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
        // Look up the board from the open_set
        const cur_hash = cur_node.board_hash;
        const board = &open_set.get(cur_hash).?;

        // Check if we've already won
        if (isWon(board)) {
            solution_hash = cur_hash;
            break;
        }

        // Check if we've visited this state before
        if (visited.contains(cur_hash)) {
            continue;
        }

        // Check if this is an outdated entry (we found a better path since adding it)
        if (best_cost.get(cur_hash)) |known_cost| {
            if (cur_node.num_moves > known_cost) {
                continue; // Skip this outdated entry
            }
        }

        // Mark current state as visited
        try visited.put(cur_hash, {});

        // Generate all valid moves from this position
        const valid_moves = board.findValidMoves(&move_buffer);

        num_iter += 1;
        if (verbose and num_iter % 100000 == 0) {
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
                    // Have found this state as a neighbor before, but found a shorter path - update it
                    try best_cost.put(new_hash, new_cost);
                    try parent_map.put(new_hash, PathNode{ .parent_hash = cur_node.board_hash, .move = move });
                    try pqueue.push(allocator, BoardNode{ .board_hash = new_hash, .num_moves = new_cost, .heuristic_value = heuristic(&new_board) });
                }
            } else if (!visited.contains(new_hash)) {
                // Haven't seen this state yet
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

    // compute heuristic value for each valid move
    for (valid_moves, 0..) |move, i| {
        var new_board = board.*;
        new_board.makeMove(move);
        move_heuristic[i] = MovePair{ .move = move, .heuristic = heuristic(&new_board) };
    }

    // Sort moves by heuristic value (lowest first)
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

/// Main solver entry point: attempts to solve the freecell puzzle
/// Modifies path to contain the solution moves if found
/// Returns true if a solution is found
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

/// Create a solved board state (all 52 cards in foundation piles, no cards on tableau)
pub fn createSolvedBoard() Board {
    return Board{
        .piles = .{ 13, 13, 13, 13 },
        .columns = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
    };
}

pub fn createRandomBoard(seed: u64) Board {
    var rng = std.Random.DefaultPrng.init(seed);
    var deck = makeDeck();
    std.Random.shuffle(rng.random(), u8, &deck);
    var board = Board.init(&deck);
    board.reallocateColumns(); // Ensure we have free space between columns to allow all moves
    return board;
}

fn printMoves(moves: []const Move) void {
    for (moves) |move| {
        std.debug.print("  slot {d} -> slot {d}\n", .{ move.from, move.to });
    }
}

const example_json =
    \\[
    \\  [ "12_s", "6_d", "9_s", "9_c", "5_c", "12_d", "7_d" ],
    \\  [ "1_c", "2_s", "10_s", "1_d", "13_s", "4_h", "6_c" ],
    \\  [ "5_h", "11_c", "13_c", "3_h", "13_h", "2_c", "10_c" ],
    \\  [ "7_s", "7_h", "9_d", "5_s", "11_d", "11_h", "3_s" ],
    \\  [ "4_s", "6_s", "8_d", "1_s", "8_s", "11_s" ],
    \\  [ "10_h", "10_d", "3_c", "6_h", "7_c", "8_c" ],
    \\  [ "2_d", "4_c", "9_h", "8_h", "12_c", "4_d" ],
    \\  [ "2_h", "5_d", "13_d", "3_d", "1_h", "12_h" ]
    \\]
;

pub fn parseCardString(s: []const u8) !Card {
    const rank_part = s[0 .. s.len - 2];
    const suit_part = s[s.len - 1];

    const rank: u8 = try std.fmt.parseInt(u8, rank_part, 10);
    const suit =
        try switch (suit_part) {
            's' => Suit.Spades,
            'c' => Suit.Clubs,
            'h' => Suit.Hearts,
            'd' => Suit.Diamonds,
            else => error.InvalidCardString,
        };

    return makeCard(suit, rank);
}

pub fn parseJsonGame(allocator: std.mem.Allocator) !Board {
    const input_data = std.json.parseFromSlice([][][]u8, allocator, example_json, .{}) catch |err| {
        std.debug.print("Failed to parse JSON game: {s}\n", .{@errorName(err)});
        return err;
    };
    if (input_data.value.len != NUM_COLUMNS) {
        std.debug.print("Invalid JSON game: expected {d} columns, got {d}\n", .{ NUM_COLUMNS, input_data.value.len });
        return error.InvalidJsonGame;
    }
    var card_buffer: [52]Card = undefined;
    var idx: u8 = 0;
    var columns: [NUM_COLUMNS][]Card = undefined;
    for (input_data.value, 0..) |column, j| {
        const col_start = idx;
        for (column) |card_str| {
            const card = parseCardString(card_str) catch |err| {
                std.debug.print("Failed to parse card string '{s}': {s}\n", .{ card_str, @errorName(err) });
                return err;
            };
            if (idx >= card_buffer.len) {
                std.debug.print("Too many cards in JSON game: exceeded {d}\n", .{card_buffer.len});
                return error.InvalidJsonGame;
            }
            card_buffer[idx] = card;
            idx += 1;
        }
        columns[j] = card_buffer[col_start..idx];
    }
    var board = Board.initFromColumns(columns);
    board.reallocateColumns();
    return board;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_board = try parseJsonGame(allocator);

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const time_start = std.Io.Clock.now(std.Io.Clock.real, init.io);

    var seed: u32 = 29;
    var total_length: u64 = 0;
    var total_iters: u64 = 0;
    while (seed < 30) : (seed += 1) {
        //const board = createRandomBoard(seed);
        const board = input_board;

        if (verbose) {
            std.debug.print("Initial board state (seed {d}):\n", .{seed});
            board.print();
            std.debug.print("=== ATTEMPTING TO SOLVE ===\n", .{});
        }

        var solution_path: Path = .empty;
        const found, const iters = try solveFreeCell(board, allocator, &solution_path);
        const path_length = solution_path.items.len;
        total_length += path_length;
        total_iters += iters;

        if (verbose) {
            std.debug.print("Solver completed. Found solution: {}. Path length: {d}. Iterations: {d}\n", .{ found, path_length, iters });

            if (found) {
                // Verify solution
                var verify_board = board;
                for (solution_path.items, 0..) |move, i| {
                    std.debug.print("  {d:>3}: slot {d:>2} -> slot {d:>2}    {s}\n", .{ i + 1, move.from, move.to, cardName(verify_board.cardInSlot(move.from)) });
                    if (!verify_board.isValidMove(move)) {
                        std.debug.print("    INVALID MOVE!\n", .{});
                        break;
                    }
                    verify_board.makeMove(move);
                }
                std.debug.print("\nVerification: Final board is solved: {}\n", .{isWon(&verify_board)});
            } else {
                std.debug.print("FAIL! Could not solve board.\n", .{});
                std.debug.print("Foundation piles: {} {} {} {}\n", .{ board.piles[0], board.piles[1], board.piles[2], board.piles[3] });
            }
        } else {
            try stdout.print(" {d:04}: {} {d:>5} {d:>7}\n", .{ seed, found, path_length, iters });
            try stdout.flush();
        }

        _ = arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
    }
    const time_end = std.Io.Clock.now(std.Io.Clock.real, init.io);
    try stdout.print("Total path length: {}, total iterations: {}, reallocs: {}\n", .{ total_length, total_iters, num_reallocations });
    try stdout.print("Total time: {} ms\n", .{@as(f64, @floatFromInt(time_end.toMicroseconds() - time_start.toMicroseconds())) / 1000.0});
    try stdout.flush();
}
