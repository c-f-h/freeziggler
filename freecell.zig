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
    pub fn findValidMoves(board: *const Board, buffer: [][2]u8) [][2]u8 {
        var count: usize = 0;

        // Check all source slots (columns 0-7, free cells 8-11)
        var from: u8 = 0;
        while (from < NUM_COLUMNS + 4) : (from += 1) {
            const card = board.cardInSlot(from);
            if (card == CARD_NONE) continue;

            // Check all destination slots (columns, free cells, foundation)
            var to: u8 = 0;
            while (to < NUM_COLUMNS + 8) : (to += 1) {
                if (from == to) continue;

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

/// Core DFS solver: tries to find a sequence of moves to win from current board state
/// Returns true if a solution is found (path will contain the moves)
/// Modifies the path and board state during search; restores board on backtrack
fn solve(board: *Board, visited: *std.AutoHashMap(u64, void), path: *Path) bool {
    // Base case 1: Check if we've already won
    if (isWon(board)) {
        return true;
    }

    // Base case 2: Check if we've visited this state before
    const state_hash = board.hash();
    if (visited.contains(state_hash)) {
        return false;
    }

    // Mark current state as visited
    visited.put(state_hash, {}) catch return false;

    // Generate all valid moves from this position
    var move_buffer: [128][2]u8 = undefined;
    const valid_moves = board.findValidMoves(&move_buffer);

    // Try each valid move
    for (valid_moves) |move_pair| {
        const move = Move{ .from = move_pair[0], .to = move_pair[1] };

        // Apply the move
        board.makeMove(move.from, move.to);
        if (!path.append(move)) return false; // Path is full

        // Recursively try to solve from this position
        if (solve(board, visited, path)) {
            return true;
        }

        // Backtrack: undo the move
        _ = path.pop();
        undoMove(board, move);
    }

    return false;
}

/// Main solver entry point: attempts to solve the freecell puzzle
/// Modifies path to contain the solution moves if found
/// Returns true if a solution is found
pub fn solveFreeCell(initial_board: Board, allocator: std.mem.Allocator, path: *Path) !bool {
    var board = initial_board;
    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();

    return solve(&board, &visited, path);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a solved board (all 52 cards in foundation piles)
    var solved_board = Board{};
    solved_board.piles = .{ 13, 13, 13, 13 }; // All foundation piles full

    std.debug.print("=== SOLVED BOARD ===\n", .{});
    solved_board.print();
    std.debug.print("Is won: {}\n\n", .{isWon(&solved_board)});

    // Now create an "unsolved" board by moving a few cards off the foundation
    // To do this, we'll place some cards on the tableau instead
    var test_board = solved_board;

    // Remove S13 (King of Spades) from foundation and put it in a column
    const ks = makeCard(Suit.Spades, 13);
    test_board.piles[0] = 12; // Foundation now has ranks 1-12
    test_board.cards[0] = ks;
    test_board.columns[0] = .{ 0, 1 };

    // Remove H13 (King of Hearts) from foundation and put it in another column
    const kh = makeCard(Suit.Hearts, 13);
    test_board.piles[2] = 12;
    test_board.cards[10] = kh;
    test_board.columns[1] = .{ 10, 11 };

    // Remove C13 (King of Clubs) and place in third column
    const kc = makeCard(Suit.Clubs, 13);
    test_board.piles[1] = 12;
    test_board.cards[20] = kc;
    test_board.columns[2] = .{ 20, 21 };

    std.debug.print("=== NEAR-SOLVED BOARD (3 moves away from solution) ===\n", .{});
    test_board.print();
    std.debug.print("Is won: {}\n", .{isWon(&test_board)});

    std.debug.print("\nValid moves available: ", .{});
    var move_buffer: [128][2]u8 = undefined;
    const valid_moves = test_board.findValidMoves(&move_buffer);
    std.debug.print("{d}\n", .{valid_moves.len});
    for (valid_moves[0..@min(5, valid_moves.len)], 0..) |move, i| {
        std.debug.print("  {d}: slot {d} -> slot {d}\n", .{ i, move[0], move[1] });
    }
    if (valid_moves.len > 5) {
        std.debug.print("  ... and {} more\n", .{valid_moves.len - 5});
    }

    std.debug.print("\n=== ATTEMPTING TO SOLVE ===\n", .{});
    std.debug.print("Starting solver from near-solved board...\n", .{});

    var solution_path: Path = .{};
    const found = try solveFreeCell(test_board, allocator, &solution_path);

    std.debug.print("Solver completed. Found solution: {}\n", .{found});
    std.debug.print("Solution path length: {d}\n", .{solution_path.count});

    if (found) {
        std.debug.print("\n✓ SUCCESS! Solution found in {d} moves!\n\n", .{solution_path.count});

        var current_board = test_board;
        for (solution_path.items(), 0..) |move, i| {
            std.debug.print("Move {d}: slot {d} -> slot {d}\n", .{ i + 1, move.from, move.to });
            current_board.makeMove(move.from, move.to);
        }

        std.debug.print("\nFinal board state (should be solved):\n", .{});
        current_board.print();
        std.debug.print("Is won: {}\n", .{isWon(&current_board)});
    } else {
        std.debug.print("\n✗ FAILED: No solution found from near-solved board!\n", .{});
        std.debug.print("This suggests a problem with the solver.\n", .{});
    }
}
