const std = @import("std");

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
pub const TABLEAU_SIZE = 64;

pub const Board = struct {
    cells: [4]Card = [_]Card{CARD_NONE} ** 4, // Free cells
    piles: [4]u8 = [_]u8{0} ** 4, // Foundation piles (top card rank)
    columns: [NUM_COLUMNS][2]u8 = .{ .{ 0, 7 }, .{ 8, 15 }, .{ 16, 23 }, .{ 24, 31 }, .{ 32, 38 }, .{ 40, 46 }, .{ 48, 54 }, .{ 56, 62 } }, // Column ranges (start, end)
    cards: [TABLEAU_SIZE]Card = [_]Card{CARD_NONE} ** TABLEAU_SIZE, // Cards in the tableau

    pub fn init(board: *Board, deck: *[52]Card) void {
        board.* = .{};
        var i: u8 = 0;
        var j: u8 = 0;
        var idx: u8 = 0;
        while (idx < 52) : (idx += 1) {
            board.cards[i + j * 8] = deck[idx];
            i += 1;
            const col_size: u8 = if (j < 4) 7 else 6; // First 4 columns get 7 cards, last 4 get 6
            if (i == col_size) {
                i = 0;
                j += 1;
            }
        }
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
        if (column == NUM_COLUMNS - 1) {
            return board.columns[column][1] == TABLEAU_SIZE;
        } else {
            return board.columns[column][1] == board.columns[column + 1][0];
        }
    }

    /// Guarantees that there are free spaces between columns for moving cards around
    pub fn reallocateColumns(board: *Board) void {
        const old_cards = board.cards;
        const old_columns = board.columns;
        const num_free_places = TABLEAU_SIZE - board.numCardsOnTableau();
        const free_per_column = @divTrunc(num_free_places, NUM_COLUMNS);
        var idx: u8 = 0;
        for (&board.columns, 0..) |*col, j| {
            col[0] = idx;
            col[1] = idx + old_columns[j][1] - old_columns[j][0];
            @memcpy(board.cards[col[0]..col[1]], old_cards[old_columns[j][0]..old_columns[j][1]]);
            idx = col[1] + free_per_column; // Add free spaces between columns
        }
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
            //std.mem.sort(u8, &board.cells, {}, comptime std.sort.asc(u8)); // Keep free cells sorted for easier move generation
            //std.debug.print("Placed card {d} in free cell slot {d}, sorted free cells: {any}", .{ card, slot - NUM_COLUMNS, &board.cells });
        } else if (slot < NUM_COLUMNS + 8) {
            // Putting into a foundation pile
            const pileIndex = slot - NUM_COLUMNS - 4;
            board.piles[pileIndex] += 1;
        }
    }

    pub fn makeMove(board: *Board, from: u8, to: u8) void {
        const card = board.takeCardFromSlot(from);
        if (card == CARD_NONE) return; // No card to move
        board.putCardInSlot(to, card);
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

    /// Find all valid moves (from any slot to any other slot) as pairs (from, to) of u8
    /// Takes a buffer of u8 pairs and returns a slice into it containing the move pairs
    /// allow_foundation_moves: if true, allows moving cards FROM foundation piles (non-standard)
    pub fn findValidMoves(board: *const Board, buffer: [][2]u8, allow_foundation_moves: bool) [][2]u8 {
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
                        buffer[count] = .{ from, to };
                        count += 1;
                    } else {
                        @panic("findValidMoves: insufficient buffer space");
                    }
                }
            }
        }

        // If enabled, also check moves FROM foundation piles (non-standard)
        if (allow_foundation_moves) {
            var from_foundation: u8 = NUM_COLUMNS + 4;
            while (from_foundation < NUM_COLUMNS + 8) : (from_foundation += 1) {
                const card = board.cardInSlot(from_foundation);
                if (card == CARD_NONE) continue;

                // Check destinations for foundation cards
                var to: u8 = 0;
                while (to < NUM_COLUMNS + 4) : (to += 1) {
                    if (from_foundation == to) continue;

                    const target = board.cardInSlot(to);
                    var is_valid = false;

                    if (to < NUM_COLUMNS + 4) {
                        // Destination is column or free cell
                        if (target == CARD_NONE) {
                            // Can move to empty slot
                            is_valid = true;
                        } else if (to < NUM_COLUMNS and canMoveBelow(card, target)) {
                            // Can move to column if alternating color and descending rank
                            is_valid = true;
                        }
                    }

                    if (is_valid) {
                        if (count < buffer.len) {
                            buffer[count] = .{ from_foundation, to };
                            count += 1;
                        } else {
                            @panic("findValidMoves: insufficient buffer space");
                        }
                    }
                }
            }
        }

        return buffer[0..count];
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

/// A path/solution is represented as a count and array of moves
pub const Path = struct {
    moves: [1000]Move = [_]Move{undefined} ** 1000,
    count: u16 = 0,

    pub fn append(path: *Path, move: Move) bool {
        if (path.count >= path.moves.len) return false;
        path.moves[path.count] = move;
        path.count += 1;
        return true;
    }

    pub fn pop(path: *Path) ?Move {
        if (path.count == 0) return null;
        path.count -= 1;
        return path.moves[path.count];
    }

    pub fn items(path: *const Path) []const Move {
        return path.moves[0..path.count];
    }
};

/// Check if the board is in a winning state (all 52 cards in foundation piles)
pub fn isWon(board: *const Board) bool {
    return board.piles[0] == 13 and board.piles[1] == 13 and board.piles[2] == 13 and board.piles[3] == 13;
}

/// Undo a move by taking a card from destination and putting it back at source
pub fn undoMove(board: *Board, move: Move) void {
    const card = board.takeCardFromSlot(move.to);
    if (card != CARD_NONE) {
        board.putCardInSlot(move.from, card);
    }
}

/// Check if a move targets a foundation pile
fn isFoundationMove(move_pair: [2]u8) bool {
    // Slots 12-15 are foundation piles
    return move_pair[1] >= NUM_COLUMNS + 4;
}

/// Core DFS solver: tries to find a sequence of moves to win from current board state
/// Returns true if a solution is found (path will contain the moves)
/// Prioritizes foundation moves to guide search toward solution
/// allow_foundation_moves: if true, allows moving cards FROM foundation piles (non-standard)
/// Modifies the path and board state during search; restores board on backtrack
fn solve(board: *Board, visited: *std.AutoHashMap(u64, void), path: *Path) bool {
    // Base case 1: Check if we've already won
    if (isWon(board)) {
        std.debug.print("Found winning board at depth {d}!\n", .{path.count});
        return true;
    }

    // Base case 2: Check if we've visited this state before
    const state_hash = board.hash();
    if (visited.contains(state_hash)) {
        return false;
    }

    // Mark current state as visited
    visited.put(state_hash, {}) catch {
        @panic("hashmap out of memory");
    };

    // Generate all valid moves from this position
    var move_buffer: [128][2]u8 = undefined;
    const valid_moves = board.findValidMoves(&move_buffer, false);

    std.debug.print("At depth {d}, found {d} valid moves\n", .{ path.count, valid_moves.len });

    for (valid_moves) |move_pair| {
        const move = Move{ .from = move_pair[0], .to = move_pair[1] };

        // Apply the move
        board.makeMove(move.from, move.to);
        //if (!path.append(move)) return false; // Path is full
        path.count += 1; // Increment path count without storing move to save memory

        // Recursively try to solve from this position
        if (solve(board, visited, path)) {
            return true;
        }

        // Backtrack: undo the move
        //_ = path.pop();
        path.count -= 1; // Decrement path count without storing move
        undoMove(board, move);
    }

    return false;
}

const BoardNode = struct { board_hash: u64, num_moves: u16, heuristic_value: u32 };

fn heuristic(board: *const Board) u32 {
    // Count cards blocked under other cards in columns
    var blocked: u32 = 0;
    for (board.columns) |col| {
        // All but the top card in each column are blocked
        const num_in_col = col[1] - col[0];
        if (num_in_col > 1) {
            blocked += num_in_col - 1;
        }
    }

    // Remaining cards on tableau are a baseline
    const remaining = board.numRemainingCards();

    // Blocked cards have higher penalty since they're harder to move
    return remaining + (blocked * 2);
}

fn bpCompare(_: void, a: BoardNode, b: BoardNode) std.math.Order {
    const a_priority = @as(u32, a.num_moves) + a.heuristic_value;
    const b_priority = @as(u32, b.num_moves) + b.heuristic_value;
    if (a_priority > b_priority) {
        return std.math.Order.gt;
    } else if (a_priority < b_priority) {
        return std.math.Order.lt;
    } else {
        return std.math.Order.eq;
    }
}

fn solveAStar(starting_board: *Board, visited: *std.AutoHashMap(u64, void), allocator: std.mem.Allocator) !bool {
    var pqueue = std.PriorityQueue(BoardNode, void, bpCompare).initContext({});

    // Store boards in a map keyed by their hash to avoid storing full boards in queue nodes
    var open_set = std.AutoHashMap(u64, Board).init(allocator);
    defer open_set.deinit();

    const start_hash = starting_board.hash();
    try pqueue.push(allocator, BoardNode{ .board_hash = start_hash, .num_moves = 0, .heuristic_value = heuristic(starting_board) });
    try open_set.put(start_hash, starting_board.*);

    var move_buffer: [128][2]u8 = undefined;

    var num_iter: u32 = 0;

    while (pqueue.pop()) |cur_node| {
        // Look up the board from the open_set
        const board_entry = open_set.get(cur_node.board_hash);
        if (board_entry == null) {
            continue; // Board not found
        }
        var board = board_entry.?;

        // Check if we've already won
        if (isWon(&board)) {
            std.debug.print("Found winning board at iteration {d}!\n", .{num_iter});
            return true;
        }

        // Check if we've visited this state before
        if (visited.contains(cur_node.board_hash)) {
            continue;
        }

        // Mark current state as visited
        try visited.put(cur_node.board_hash, {});

        // Generate all valid moves from this position
        const valid_moves = board.findValidMoves(&move_buffer, false);

        num_iter += 1;
        if (num_iter % 100000 == 0) {
            std.debug.print("Iteration {d}, queue length {d}, {d} hashes, found {d} valid moves:\n", .{ num_iter, pqueue.count(), visited.count(), valid_moves.len });
            board.print();
            printMoves(valid_moves);
        }

        for (valid_moves) |move_pair| {
            var new_board = board;
            new_board.makeMove(move_pair[0], move_pair[1]);

            // Check if this new state was already visited BEFORE adding to queue
            const new_hash = new_board.hash();
            if (!visited.contains(new_hash)) {
                try pqueue.push(allocator, BoardNode{ .board_hash = new_hash, .num_moves = cur_node.num_moves + 1, .heuristic_value = heuristic(&new_board) });
                try open_set.put(new_hash, new_board);
            }
        }
    }
    return false;
}

/// Main solver entry point: attempts to solve the freecell puzzle
/// Modifies path to contain the solution moves if found
/// Returns true if a solution is found
/// allow_foundation_moves: if true, allows moving cards FROM foundation piles (non-standard)
pub fn solveFreeCell(initial_board: Board, allocator: std.mem.Allocator, path: *Path) !bool {
    var board = initial_board;
    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();

    //return solve(&board, &visited, path);
    _ = path; // Unused in BFS version
    return solveAStar(&board, &visited, allocator);
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
    var board = Board{};
    board.init(&deck);
    return board;
}

/// Create a shuffled board by making random moves from foundation to columns
pub fn createShuffledBoard(num_moves: u16, seed: u64) Board {
    // Start with a solved board (all cards in foundation)
    var board = createSolvedBoard();
    var rng = std.Random.DefaultPrng.init(seed);

    for (0..num_moves) |i| {
        // Pick a random foundation pile that has cards
        var foundation_index: u8 = undefined;
        var found_with_cards = false;

        // Try up to 4 times to find a foundation with cards
        for (0..4) |_| {
            foundation_index = @intCast(rng.random().uintLessThan(u8, 4));
            if (board.piles[foundation_index] > 0) {
                found_with_cards = true;
                break;
            }
        }

        if (!found_with_cards) {
            std.debug.print("  No foundation piles have cards at iteration {d}\n", .{i});
            break;
        }

        // Pick a random column destination
        const column_dest = rng.random().uintLessThan(u8, NUM_COLUMNS);

        // The foundation slot is NUM_COLUMNS + 4 + foundation_index
        const foundation_slot: u8 = NUM_COLUMNS + 4 + foundation_index;

        // Apply the move without validity check
        board.makeMove(foundation_slot, column_dest);
    }

    for (board.columns) |col| {
        std.Random.shuffle(rng.random(), u8, board.cards[col[0]..col[1]]);
    }
    std.debug.print("Created semi-shuffled board after {d} random moves...\n\n", .{num_moves});

    return board;
}

fn printMoves(moves: [][2]u8) void {
    for (moves) |move_pair| {
        std.debug.print("  slot {d} -> slot {d}\n", .{ move_pair[0], move_pair[1] });
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //const random_move_count: u16 = 40;
    //const board = createShuffledBoard(random_move_count, 1);
    const board = createRandomBoard(3);

    std.debug.print("Initial board state:\n", .{});
    board.print();

    var move_buffer: [128][2]u8 = undefined;
    const test_moves = board.findValidMoves(&move_buffer, false);
    std.debug.print(" {d} valid moves available\n\n", .{test_moves.len});
    printMoves(test_moves);

    // Now try to solve it
    std.debug.print("=== ATTEMPTING TO SOLVE ===\n", .{});

    var solution_path: Path = .{};
    const found = try solveFreeCell(board, allocator, &solution_path);

    std.debug.print("Solver completed. Found solution: {}. Path length: {d}\n", .{ found, solution_path.count });

    if (found) {
        std.debug.print("SUCCESS! Puzzle solved!\n", .{});

        // Show first 20 moves of solution
        //std.debug.print("\nFirst 20 moves of solution:\n", .{});
        //for (solution_path.items()[0..@min(20, solution_path.count)], 0..) |move, i| {
        //    std.debug.print("  {d}: slot {d} -> slot {d}\n", .{ i + 1, move.from, move.to });
        //}
        //if (solution_path.count > 20) {
        //    std.debug.print("  ... and {d} more moves\n", .{solution_path.count - 20});
        //}

        //// Verify solution
        //var verify_board = board;
        //for (solution_path.items()) |move| {
        //    verify_board.makeMove(move.from, move.to);
        //}
        //std.debug.print("\nVerification: Final board is solved: {}\n", .{isWon(&verify_board)});
    } else {
        std.debug.print("FAIL! Could not solve puzzle.\n", .{});
        std.debug.print("Foundation piles: {} {} {} {}\n", .{ board.piles[0], board.piles[1], board.piles[2], board.piles[3] });
    }
}
