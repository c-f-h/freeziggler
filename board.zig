const std = @import("std");
const card_mod = @import("card.zig");

const Card = card_mod.Card;
const CARD_NONE = card_mod.CARD_NONE;
const Suit = card_mod.Suit;
const color = card_mod.color;
const makeCard = card_mod.makeCard;
const canMoveBelow = card_mod.canMoveBelow;
const printCard = card_mod.printCard;

pub const NUM_COLUMNS = 8;
pub const TABLEAU_SIZE = 64;

pub var num_reallocations: u64 = 0;

pub const Move = struct {
    from: u8,
    to: u8,
};

/// If true, keeps free cells sorted by card value to deduplicate equivalent states
pub const KEEP_FREECELLS_SORTED = true;

/// If true, keeps columns sorted by anchor card (rear-most) to deduplicate equivalent states
pub const KEEP_COLUMNS_SORTED = true;

fn bubbleIntoPlace(arr: *[4]u8, index: u8) void {
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

pub const Board = struct {
    cells: [4]Card = [_]Card{CARD_NONE} ** 4,
    piles: [4]u8 = [_]u8{0} ** 4,
    columns: [NUM_COLUMNS][2]u8 = .{ .{ 0, 7 }, .{ 7, 14 }, .{ 14, 21 }, .{ 21, 28 }, .{ 28, 34 }, .{ 34, 40 }, .{ 40, 46 }, .{ 46, 52 } },
    cards: [TABLEAU_SIZE]Card = [_]Card{CARD_NONE} ** TABLEAU_SIZE,

    pub fn init(deck: *[52]Card) Board {
        var board: Board = .{};
        var idx: u8 = 0;
        while (idx < 52) : (idx += 1) {
            board.cards[idx] = deck[idx];
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
            for (col) |c| {
                if (idx < TABLEAU_SIZE) {
                    board.cards[idx] = c;
                    idx += 1;
                } else {
                    @panic("Too many cards in tableau");
                }
            }
            board.columns[j][1] = idx;
        }
        return board;
    }

    /// Slots: columns 0-7, free cells 8-11, foundation piles 12-15
    pub fn cardInSlot(board: *const Board, slot: u8) Card {
        if (slot < NUM_COLUMNS) {
            const col = board.columns[slot];
            if (col[0] < col[1]) {
                return board.cards[col[1] - 1];
            }
        } else if (slot < NUM_COLUMNS + 4) {
            return board.cells[slot - NUM_COLUMNS];
        } else if (slot < NUM_COLUMNS + 8) {
            const pileIndex = slot - NUM_COLUMNS - 4;
            if (board.piles[pileIndex] > 0) {
                return makeCard(@enumFromInt(pileIndex << 6), board.piles[pileIndex]);
            }
        }
        return CARD_NONE;
    }

    pub fn findSlotContainingCard(board: *const Board, target: Card) ?u8 {
        for (board.cells, 0..) |cell, i| {
            if (cell == target) {
                return NUM_COLUMNS + @as(u8, @intCast(i));
            }
        }

        const suit = card_mod.suitIndex(card_mod.cardSuit(target));
        if (board.piles[suit] == card_mod.cardRank(target)) {
            return NUM_COLUMNS + 4 + suit;
        }

        for (board.columns, 0..) |col, j| {
            const start = col[0];
            const end = col[1];
            if (start < end and board.cards[end - 1] == target)
                return @truncate(j);
        }
        return null;
    }

    pub fn findEmptyColumn(board: *const Board) ?u8 {
        for (board.columns, 0..) |col, j| {
            if (col[0] == col[1]) {
                return @truncate(j);
            }
        }
        return null;
    }

    pub fn findEmptyFreeCell(board: *const Board) ?u8 {
        for (board.cells, 0..) |cell, i| {
            if (cell == CARD_NONE) {
                return NUM_COLUMNS + @as(u8, @intCast(i));
            }
        }
        return null;
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

    pub fn isWon(board: *const Board) bool {
        return board.piles[0] == 13 and board.piles[1] == 13 and board.piles[2] == 13 and board.piles[3] == 13;
    }

    pub fn columnIsFull(board: *const Board, column: u8) bool {
        // NB: This implementation does not rely on the order in which the columns are stored, since
        // we want to be able to reorder the columns.
        const next_idx = board.columns[column][1];
        if (next_idx >= TABLEAU_SIZE) {
            return true;
        }
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
            idx = col[1] + free_per_column;
        }
        num_reallocations += 1;
    }

    pub fn takeCardFromSlot(board: *Board, slot: u8, no_sorting: bool) Card {
        const card = board.cardInSlot(slot);
        if (card == CARD_NONE) return CARD_NONE;

        if (slot < NUM_COLUMNS) {
            board.columns[slot][1] -= 1;
        } else if (slot < NUM_COLUMNS + 4) {
            board.cells[slot - NUM_COLUMNS] = CARD_NONE;
            if (KEEP_FREECELLS_SORTED and !no_sorting)
                bubbleIntoPlace(&board.cells, slot - NUM_COLUMNS);
        } else if (slot < NUM_COLUMNS + 8) {
            const pileIndex = slot - NUM_COLUMNS - 4;
            board.piles[pileIndex] -= 1;
        }

        return card;
    }

    pub fn putCardInSlot(board: *Board, slot: u8, c: Card, no_sorting: bool) void {
        if (slot < NUM_COLUMNS) {
            if (board.columnIsFull(slot)) {
                board.reallocateColumns();
            }
            board.cards[board.columns[slot][1]] = c;
            board.columns[slot][1] += 1;
        } else if (slot < NUM_COLUMNS + 4) {
            board.cells[slot - NUM_COLUMNS] = c;
            if (KEEP_FREECELLS_SORTED and !no_sorting)
                bubbleIntoPlace(&board.cells, slot - NUM_COLUMNS);
        } else if (slot < NUM_COLUMNS + 8) {
            const pileIndex = slot - NUM_COLUMNS - 4;
            board.piles[pileIndex] += 1;
        }
    }

    /// Make the given move. This may reorder the free cells or columns.
    pub fn makeMove(board: *Board, move: Move) void {
        const c = board.takeCardFromSlot(move.from, false);
        if (c == CARD_NONE) @panic("invalid move");
        board.putCardInSlot(move.to, c, false);

        if (KEEP_COLUMNS_SORTED and !board.columnsAreSorted()) {
            board.sortColumns();
        }
    }

    /// Make the given move. This may reorder the free cells or columns.
    pub fn makeMove_noSorting(board: *Board, move: Move) void {
        const c = board.takeCardFromSlot(move.from, true);
        if (c == CARD_NONE) @panic("invalid move");
        board.putCardInSlot(move.to, c, true);
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
                const suit: Suit = @enumFromInt(i << 6);
                printCard(makeCard(suit, pile));
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

    /// Check if the given move is valid in the current board state.
    pub fn isValidMove(board: *const Board, move: Move) bool {
        const from = move.from;
        const to = move.to;

        if (from == to)
            return false;

        const c = board.cardInSlot(from);
        if (c == CARD_NONE)
            return false;

        const target = board.cardInSlot(to);

        if (to < NUM_COLUMNS) {
            // Destination is column - either empty or can move if alternating color and descending rank
            return target == CARD_NONE or canMoveBelow(c, target);
        } else if (to < NUM_COLUMNS + 4) {
            // Destination is free cell - must be empty
            return target == CARD_NONE;
        } else {
            // Destination is foundation pile
            const pile_index = to - NUM_COLUMNS - 4;
            return (card_mod.cardRank(c) == board.piles[pile_index] + 1 and card_mod.cardSuitIndex(c) == pile_index);
        }
    }

    /// Find all valid moves (from any slot to any other slot).
    pub fn findValidMoves(board: *const Board, buffer: []Move) []Move {
        var count: usize = 0;

        // Check source slots: columns and free cells (0-11)
        var from: u8 = 0;
        while (from < NUM_COLUMNS + 4) : (from += 1) {
            const c = board.cardInSlot(from);
            if (c == CARD_NONE) continue;

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
                    if ((target == CARD_NONE and !free_column_move_generated) or (target != CARD_NONE and canMoveBelow(c, target))) {
                        is_valid = true;
                        if (target == CARD_NONE) {
                            free_column_move_generated = true;
                        }
                    }
                } else if (to < NUM_COLUMNS + 4) {
                    if (target == CARD_NONE and !free_cell_move_generated) {
                        is_valid = true;
                        free_cell_move_generated = true;
                    }
                } else {
                    const pile_index = to - NUM_COLUMNS - 4;
                    if (card_mod.cardRank(c) == board.piles[pile_index] + 1 and card_mod.cardSuitIndex(c) == pile_index) {
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

    /// Sort the columns w.r.t. their anchor cards.
    /// Only updates the column slices; does not change the memory layout of the cards.
    pub fn sortColumns(board: *Board) void {
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

    /// Compute hash of the board state. Is invariant to different memory representations of the same logical state.
    pub fn hash(board: *const Board) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(&board.cells);
        hasher.update(&board.piles);
        const delimiter = [1]u8{0xFF};
        for (board.columns) |col| {
            const start = col[0];
            const end = col[1];
            if (start < end) {
                hasher.update(board.cards[start..end]);
            }
            hasher.update(&delimiter);
        }
        return hasher.final();
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const makeDeck = card_mod.makeDeck;

test "Board.init - distributes cards correctly" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // First 4 columns should have 7 cards each (4 * 7 = 28)
    for (board.columns[0..4]) |col| {
        try std.testing.expect(col[1] - col[0] == 7);
    }

    // Last 4 columns should have 6 cards each (4 * 6 = 24)
    for (board.columns[4..8]) |col| {
        try std.testing.expect(col[1] - col[0] == 6);
    }

    try std.testing.expect(board.numCardsOnTableau() == 52);
}

test "Board.numCardsInColumn" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Column 0-3 should have 7 cards
    try std.testing.expect(board.numCardsInColumn(0) == 7);
    try std.testing.expect(board.numCardsInColumn(1) == 7);
    try std.testing.expect(board.numCardsInColumn(2) == 7);
    try std.testing.expect(board.numCardsInColumn(3) == 7);

    // Column 4-7 should have 6 cards
    try std.testing.expect(board.numCardsInColumn(4) == 6);
    try std.testing.expect(board.numCardsInColumn(5) == 6);
    try std.testing.expect(board.numCardsInColumn(6) == 6);
    try std.testing.expect(board.numCardsInColumn(7) == 6);
}

test "Board.numCardsOnTableau" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    try std.testing.expect(board.numCardsOnTableau() == 52);
}

test "Board.cardInSlot - columns" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Get top card of first column (slot 0)
    const card_col0 = board.cardInSlot(0);
    try std.testing.expect(card_col0 != CARD_NONE);

    // Get top card of last column (slot 7)
    const card_col7 = board.cardInSlot(7);
    try std.testing.expect(card_col7 != CARD_NONE);
}

test "Board.cardInSlot - free cells (empty)" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Free cells are initially empty (slots 8-11)
    try std.testing.expect(board.cardInSlot(8) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(9) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(10) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(11) == CARD_NONE);
}

test "Board.cardInSlot - foundation piles (empty)" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Foundation piles are initially empty (slots 12-15)
    try std.testing.expect(board.cardInSlot(12) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(13) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(14) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(15) == CARD_NONE);
}

test "Board.cardInSlot - free cells (with cards)" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const test_card = makeCard(Suit.Hearts, 5);
    board.cells[0] = test_card;

    try std.testing.expect(board.cardInSlot(8) == test_card);
}

test "Board.cardInSlot - foundation piles (with cards)" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    board.piles[2] = 3; // Hearts pile with 3 cards

    const returned_card = board.cardInSlot(14); // Hearts foundation (slot 14)
    const expected_card = makeCard(Suit.Hearts, 3);

    try std.testing.expect(returned_card == expected_card);
}

test "Board.columnIsFull - new board" {
    var deck = makeDeck();
    var board = Board.init(&deck);
    board.reallocateColumns();

    // Columns are not full after reallocation (they are packed but not filled to max)
    try std.testing.expect(!board.columnIsFull(0));
    try std.testing.expect(!board.columnIsFull(7));
}

test "Board.columnIsFull - after filling" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Manually make a column full by moving its end to the next column's start
    board.columns[0][1] = board.columns[1][0];

    try std.testing.expect(board.columnIsFull(0));
}

test "Board.columnIsFull - independent of logical column order" {
    var board = Board{
        .columns = .{
            .{ 10, 13 },
            .{ 30, 35 },
            .{ 13, 20 },
            .{ 40, 44 },
            .{ 44, 48 },
            .{ 48, 52 },
            .{ 52, 56 },
            .{ 56, 60 },
        },
    };

    // Column 0 would overwrite column 2 if extended, even though column 1 is far away.
    try std.testing.expect(board.columnIsFull(0));
    try std.testing.expect(!board.columnIsFull(1));
}

test "Board.reallocateColumns - preserves all cards" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Count cards before reallocation
    const cards_before = board.numCardsOnTableau();

    // Store card values before reallocation
    var cards_before_list: [52]Card = undefined;
    var idx: usize = 0;
    for (board.columns) |col| {
        for (board.cards[col[0]..col[1]]) |card| {
            cards_before_list[idx] = card;
            idx += 1;
        }
    }

    board.reallocateColumns();

    // Count cards after reallocation
    const cards_after = board.numCardsOnTableau();
    try std.testing.expect(cards_before == cards_after);

    // Verify the same cards still exist
    idx = 0;
    for (board.columns) |col| {
        for (board.cards[col[0]..col[1]]) |card| {
            try std.testing.expect(card == cards_before_list[idx]);
            idx += 1;
        }
    }
}

test "Board.reallocateColumns - adds spacing" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Manually make columns packed (no spacing)
    board.columns[0][1] = 7;
    board.columns[1][0] = 7;
    board.columns[1][1] = 14;
    board.columns[2][0] = 14;

    board.reallocateColumns();

    // After reallocation, each column should have some space after it
    for (0..NUM_COLUMNS) |j| {
        const col = board.columns[j];
        const next_col_start = if (j == NUM_COLUMNS - 1)
            TABLEAU_SIZE
        else
            board.columns[j + 1][0];

        // Allow some spacing between columns
        try std.testing.expect(col[1] < next_col_start);
    }
}

test "Board.init - empty cells initially" {
    var deck = makeDeck();
    const board = Board.init(&deck);

    for (board.cells) |cell| {
        try std.testing.expect(cell == CARD_NONE);
    }
}

test "Board.init - empty foundation piles initially" {
    var deck = makeDeck();
    const board = Board.init(&deck);

    for (board.piles) |pile| {
        try std.testing.expect(pile == 0);
    }
}

test "Board - complex scenario: move cards between free cells and foundation" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Manually set up a scenario
    board.cells[0] = makeCard(Suit.Hearts, 1); // Ace of hearts
    board.piles[2] = 0; // Hearts pile empty

    // Manually simulate moving ace to foundation
    board.cells[0] = CARD_NONE;
    board.piles[2] = 1;

    try std.testing.expect(board.cells[0] == CARD_NONE);
    try std.testing.expect(board.piles[2] == 1);
    try std.testing.expect(board.cardInSlot(14) == makeCard(Suit.Hearts, 1));
}

test "Board initialization idempotent" {
    var deck1 = makeDeck();
    var deck2 = makeDeck();
    const board1 = Board.init(&deck1);
    const board2 = Board.init(&deck2);

    // Both boards should have same number of cards in same positions
    for (board1.columns, board2.columns) |col1, col2| {
        try std.testing.expect((col1[1] - col1[0]) == (col2[1] - col2[0]));
    }
}

test "Board - all columns contain valid cards" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    for (board.columns) |col| {
        for (board.cards[col[0]..col[1]]) |card| {
            try std.testing.expect(card != CARD_NONE);
            const rank = card & 0b0000_1111;
            try std.testing.expect(rank >= 1 and rank <= 13);
        }
    }
}

// ============================================================================
// makeMove Tests
// ============================================================================

test "makeMove - from column to free cell" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const top_card = board.cardInSlot(0);
    const initial_count = board.numCardsInColumn(0);

    board.makeMove(.{ .from = 0, .to = 8 }); // Move from column 0 to free cell 0 (slot 8)

    var found_card = false;
    for (board.cells) |cell| {
        if (cell == top_card) found_card = true;
    }
    try std.testing.expect(found_card);
    try std.testing.expect(board.numCardsInColumn(0) == initial_count - 1);
}

test "makeMove - from free cell to column" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const test_card = makeCard(Suit.Hearts, 3);
    board.cells[0] = test_card;

    const initial_count = board.numCardsInColumn(1);

    board.makeMove(.{ .from = 8, .to = 1 }); // Move from free cell 0 (slot 8) to column 1

    try std.testing.expect(board.cardInSlot(1) == test_card);
    try std.testing.expect(board.numCardsInColumn(1) == initial_count + 1);
    try std.testing.expect(board.cells[0] == CARD_NONE);
}

test "makeMove - from column to foundation" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Set up: place an ace of hearts in a free cell
    const ace_hearts = makeCard(Suit.Hearts, 1);
    board.cells[0] = ace_hearts;

    board.makeMove(.{ .from = 8, .to = 14 }); // Move from free cell 0 to hearts foundation (slot 14)

    try std.testing.expect(board.piles[2] == 1); // Hearts pile now has 1 card (rank 1)
    try std.testing.expect(board.cardInSlot(14) == ace_hearts);
    try std.testing.expect(board.cells[0] == CARD_NONE);
}

test "makeMove - from foundation to free cell" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Set up: place cards in foundation
    board.piles[0] = 3; // Spades pile with 3 cards

    const spadesCard = makeCard(Suit.Spades, 3);

    board.makeMove(.{ .from = 12, .to = 8 }); // Move from spades foundation (slot 12) to free cell (slot 8)

    try std.testing.expect(board.piles[0] == 2); // Spades pile now has 2 cards
    var found_card = false;
    for (board.cells) |cell| {
        if (cell == spadesCard) found_card = true;
    }
    try std.testing.expect(found_card);
}

// this is illegal
//test "makeMove - from empty slot (should do nothing)" {
//    var deck = makeDeck();
//    var board = Board{};
//    board.init(&deck);
//
//    const initial_cards = board.numCardsOnTableau();
//
//    board.makeMove(8, 0); // Try to move from empty free cell 0
//
//    try std.testing.expect(board.numCardsOnTableau() == initial_cards); // No change
//}

test "makeMove - preserves total card count" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const initial_cards = board.numCardsOnTableau();

    board.makeMove(.{ .from = 0, .to = 8 }); // Move from column to free cell

    // Total cards should remain the same
    const tableau_cards = board.numCardsOnTableau();
    var free_cell_cards: u8 = 0;
    for (board.cells) |cell| {
        if (cell != CARD_NONE) free_cell_cards += 1;
    }
    var foundation_cards: u8 = 0;
    for (board.piles) |pile| {
        foundation_cards += pile;
    }

    try std.testing.expect(tableau_cards + free_cell_cards + foundation_cards == initial_cards);
}

test "makeMove - between free cells" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const test_card = makeCard(Suit.Diamonds, 7);
    board.cells[0] = test_card;

    board.makeMove(.{ .from = 8, .to = 9 }); // Move from free cell 0 to free cell 1

    try std.testing.expect(board.cells[0] == CARD_NONE);
    var found_card = false;
    for (board.cells) |cell| {
        if (cell == test_card) found_card = true;
    }
    try std.testing.expect(found_card);
}

test "makeMove - column to column, removes from source" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const col0_count = board.numCardsInColumn(0);
    const col1_count = board.numCardsInColumn(1);

    board.makeMove(.{ .from = 0, .to = 1 }); // Move from column 0 to column 1

    try std.testing.expect(board.numCardsInColumn(0) == col0_count - 1);
    try std.testing.expect(board.numCardsInColumn(1) == col1_count + 1);
}

test "makeMove - reallocation ensures space" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Get initial card count
    const initial_cards = board.numCardsOnTableau();

    // Make multiple moves to fill up a column
    // Move several cards from different columns to column 0
    for (0..4) |i| {
        const source_slot: u8 = @intCast(1 + i);
        board.makeMove(.{ .from = source_slot, .to = 0 });
    }

    // After these moves, column 0 should be full
    try std.testing.expect(board.columnIsFull(0));

    // Verify cards were moved and no cards were lost
    try std.testing.expect(board.numCardsOnTableau() == initial_cards);

    // Verify we can still make more moves without issues
    const card = board.cardInSlot(2);
    board.makeMove(.{ .from = 2, .to = 0 });
    try std.testing.expect(board.numCardsOnTableau() == initial_cards);
    try std.testing.expect(board.cardInSlot(0) == card);
}

test "makeMove - multiple sequential moves" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const initial_count = board.numCardsOnTableau();

    const card1 = board.cardInSlot(0);
    board.makeMove(.{ .from = 0, .to = 8 }); // Move to free cell 0

    const card2 = board.cardInSlot(1);
    board.makeMove(.{ .from = 1, .to = 9 }); // Move to free cell 1

    var found_card1 = false;
    var found_card2 = false;
    for (board.cells) |cell| {
        if (cell == card1) found_card1 = true;
        if (cell == card2) found_card2 = true;
    }
    try std.testing.expect(found_card1);
    try std.testing.expect(found_card2);
    try std.testing.expect(board.numCardsOnTableau() == initial_count - 2);
}

test "makeMove - all foundation piles" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Set up: place aces in free cells
    board.cells[0] = makeCard(Suit.Spades, 1);
    board.cells[1] = makeCard(Suit.Clubs, 1);
    board.cells[2] = makeCard(Suit.Hearts, 1);
    board.cells[3] = makeCard(Suit.Diamonds, 1);

    // Move each ace to foundation
    board.makeMove(.{ .from = 8, .to = 12 }); // Spades ace to spades foundation
    board.makeMove(.{ .from = 9, .to = 13 }); // Clubs ace to clubs foundation
    board.makeMove(.{ .from = 10, .to = 14 }); // Hearts ace to hearts foundation
    board.makeMove(.{ .from = 11, .to = 15 }); // Diamonds ace to diamonds foundation

    try std.testing.expect(board.piles[0] == 1); // Spades
    try std.testing.expect(board.piles[1] == 1); // Clubs
    try std.testing.expect(board.piles[2] == 1); // Hearts
    try std.testing.expect(board.piles[3] == 1); // Diamonds

    for (board.cells) |cell| {
        try std.testing.expect(cell == CARD_NONE);
    }
}

// ============================================================================
// Hash Tests
// ============================================================================

test "Board.hash - same board produces same hash" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const hash1 = board.hash();
    const hash2 = board.hash();

    try std.testing.expect(hash1 == hash2);
}

test "Board.hash - empty board is consistent" {
    var board = Board{};

    const hash1 = board.hash();
    const hash2 = board.hash();

    try std.testing.expect(hash1 == hash2);
}

test "Board.hash - changing free cells changes hash" {
    var deck = makeDeck();
    var board1 = Board.init(&deck);
    var board2 = Board.init(&deck);

    const hash_before = board1.hash();

    // Modify a free cell in board2
    board2.cells[0] = makeCard(Suit.Hearts, 5);
    const hash_after = board1.hash();
    const hash_modified = board2.hash();

    // Hashes should be different
    try std.testing.expect(hash_after == hash_before); // board1 unchanged
    try std.testing.expect(hash_modified != hash_after); // board2 changed
}

test "Board.hash - changing foundation piles changes hash" {
    var deck = makeDeck();
    var board1 = Board.init(&deck);
    var board2 = Board.init(&deck);

    const hash_before = board1.hash();

    // Modify foundation piles
    board2.piles[0] = 5; // Spades pile with 5 cards
    const hash_modified = board2.hash();

    try std.testing.expect(hash_modified != hash_before);
}

test "Board.hash - changing tableau cards changes hash" {
    var deck = makeDeck();
    var board1 = Board.init(&deck);
    var board2 = Board.init(&deck);

    const hash_before = board1.hash();

    // Modify a card on the tableau
    if (board2.columns[0][1] > board2.columns[0][0]) {
        board2.cards[board2.columns[0][0]] = makeCard(Suit.Clubs, 7);
    }
    const hash_modified = board2.hash();

    try std.testing.expect(hash_modified != hash_before);
}

test "Board.hash - identical setup after move sequence" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // Get hash of initial state
    const hash_initial = board.hash();

    // Make a move
    board.makeMove(.{ .from = 0, .to = 8 });
    const hash_after_move = board.hash();

    // Hashes should be different after move
    try std.testing.expect(hash_after_move != hash_initial);

    // Undo the move by moving from first free cell back to column
    if (KEEP_FREECELLS_SORTED) {
        board.makeMove(.{ .from = 11, .to = 0 });
    } else {
        board.makeMove(.{ .from = 8, .to = 0 });
    }

    const hash_undo = board.hash();

    // After undoing, should match initial (if board layout is same)
    try std.testing.expect(hash_undo == hash_initial);
}

test "Board.hash - detects card content differences" {
    var board1 = Board{};
    var board2 = Board{};

    // Set up two boards with same structure but different cards
    board1.columns[0] = .{ 0, 7 };
    board2.columns[0] = .{ 0, 7 };

    // Fill with different cards
    var i: u8 = 0;
    while (i < 7) : (i += 1) {
        board1.cards[i] = makeCard(Suit.Hearts, i + 1);
        board2.cards[i] = makeCard(Suit.Spades, i + 1);
    }

    const hash1 = board1.hash();
    const hash2 = board2.hash();

    try std.testing.expect(hash1 != hash2);
}

test "Board.hash - all free cells filled changes hash" {
    var deck = makeDeck();
    const board1 = Board.init(&deck);
    var board2 = Board.init(&deck);

    const hash_before = board1.hash();

    // Fill all free cells in board2
    board2.cells[0] = makeCard(Suit.Hearts, 1);
    board2.cells[1] = makeCard(Suit.Diamonds, 2);
    board2.cells[2] = makeCard(Suit.Clubs, 3);
    board2.cells[3] = makeCard(Suit.Spades, 4);

    const hash_filled = board2.hash();

    try std.testing.expect(hash_filled != hash_before);
    try std.testing.expect(hash_filled != board1.hash());
}

test "Board.hash - card movement detection" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    const hash_initial = board.hash();

    // Save the initial card at column 0
    const card_col0 = board.cardInSlot(0);

    // Move card to free cell
    board.makeMove(.{ .from = 0, .to = 8 });
    const hash_after_move = board.hash();

    // Verify hashes are different
    try std.testing.expect(hash_after_move != hash_initial);
    try std.testing.expect(board.cells[if (KEEP_FREECELLS_SORTED) 3 else 0] == card_col0);
}

test "Board.hash - reallocate columns preserves hash" {
    var deck = makeDeck();
    var board = Board.init(&deck);

    // make a move such that column 0 is full and requires reallocation
    board.makeMove(.{ .from = 6, .to = 0 });

    const hash_before = board.hash();

    try std.testing.expect(board.columnIsFull(0));
    board.reallocateColumns();
    try std.testing.expect(!board.columnIsFull(0));

    const hash_after = board.hash();

    // Hash should remain the same since card order and state are unchanged
    try std.testing.expect(hash_before == hash_after);
}

// ============================================================================
// findValidMoves Tests
// ============================================================================

test "findValidMoves - empty board" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    const moves = board.findValidMoves(&buffer);

    // Empty board should have no valid moves
    try std.testing.expect(moves.len == 0);
}

test "findValidMoves - move to empty free cell" {
    var deck = makeDeck();
    var board = Board.init(&deck);
    var buffer: [128]Move = undefined;

    const moves = board.findValidMoves(&buffer);

    // Should find many moves (to empty free cells)
    try std.testing.expect(moves.len > 0);

    // Check that at least one move is to a free cell
    var found_free_cell_move = false;
    for (moves) |move| {
        if (move.to >= 8 and move.to < 12) {
            found_free_cell_move = true;
            break;
        }
    }
    try std.testing.expect(found_free_cell_move);
}

test "findValidMoves - move ace to foundation" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: place an ace in a free cell
    const ace_spades = makeCard(Suit.Spades, 1);
    board.cells[0] = ace_spades;
    board.piles[0] = 0; // Spades foundation empty

    const moves = board.findValidMoves(&buffer);

    // Should have at least one move from free cell 8 to foundation slot 12
    var found_ace_move = false;
    for (moves) |move| {
        if (move.from == 8 and move.to == 12) {
            found_ace_move = true;
            break;
        }
    }
    try std.testing.expect(found_ace_move);
}

test "findValidMoves - move to foundation with existing cards" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: place ace and 2 in cells, 1 card in foundation
    board.cells[0] = makeCard(Suit.Hearts, 2);
    board.cells[1] = makeCard(Suit.Hearts, 3);
    board.piles[2] = 1; // Hearts foundation has ace (rank 1)

    const moves = board.findValidMoves(&buffer);

    // Should find move from free cell 8 to hearts foundation 14
    var found_move = false;
    for (moves) |move| {
        if (move.from == 8 and move.to == 14) {
            found_move = true;
            break;
        }
    }
    try std.testing.expect(found_move);
}

test "findValidMoves - alternating colors in columns" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: place red 6 in column 0, black 7 in column 1
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.cards[0] = makeCard(Suit.Hearts, 6); // Red 6
    board.cards[1] = makeCard(Suit.Spades, 7); // Black 7

    const moves = board.findValidMoves(&buffer);

    // Should find valid move from column 0 to column 1
    var found_move = false;
    for (moves) |move| {
        if (move.from == 0 and move.to == 1) {
            found_move = true;
            break;
        }
    }
    try std.testing.expect(found_move);
}

test "findValidMoves - invalid same color move" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: place red 6 in column 0, red 7 in column 1 (same color, invalid)
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.cards[0] = makeCard(Suit.Hearts, 6); // Red 6
    board.cards[1] = makeCard(Suit.Diamonds, 7); // Red 7

    const moves = board.findValidMoves(&buffer);

    // Should NOT find move from column 0 to column 1
    for (moves) |move| {
        try std.testing.expect(!(move.from == 0 and move.to == 1));
    }
}

test "findValidMoves - invalid rank sequence move" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: place red 5 in column 0, black 8 in column 1 (wrong rank)
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.cards[0] = makeCard(Suit.Hearts, 5); // Red 5
    board.cards[1] = makeCard(Suit.Spades, 8); // Black 8

    const moves = board.findValidMoves(&buffer);

    // Should NOT find move from column 0 to column 1
    for (moves) |move| {
        try std.testing.expect(!(move.from == 0 and move.to == 1));
    }
}

test "findValidMoves - move to empty column" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: card in column 0, column 1 empty
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 1 }; // Empty column
    board.cards[0] = makeCard(Suit.Hearts, 5);

    const moves = board.findValidMoves(&buffer);

    // Should find move from column 0 to empty column 1
    var found_move = false;
    for (moves) |move| {
        if (move.from == 0 and move.to == 1) {
            found_move = true;
            break;
        }
    }
    try std.testing.expect(found_move);
}

test "findValidMoves - multiple valid moves from same card" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: a card that can move to multiple destinations
    // Free 6 in free cell of column 0, black 7 in column 1, empty column 2
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.columns[2] = .{ 2, 2 }; // Empty
    board.cells[0] = makeCard(Suit.Hearts, 6); // Free cell
    board.cards[0] = makeCard(Suit.Hearts, 6); // Column 0 top card
    board.cards[1] = makeCard(Suit.Spades, 7); // Column 1 top card

    const moves = board.findValidMoves(&buffer);

    // Should find at least 2 moves from free cell (to column 1 and column 2)
    var move_count: usize = 0;
    for (moves) |move| {
        if (move.from == 8) { // Free cell
            move_count += 1;
        }
    }
    try std.testing.expect(move_count >= 2);
}

test "findValidMoves - no moves from empty slots" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: completely empty board except one card
    board.columns[0] = .{ 0, 1 };
    board.cards[0] = makeCard(Suit.Hearts, 5);

    const moves = board.findValidMoves(&buffer);

    // Should have some moves (at least to empty slots)
    // But should not create moves from empty free cells (8-11)
    for (moves) |move| {
        // From slots 8-11 should not appear (empty free cells)
        try std.testing.expect(!(move.from >= 8 and move.from < 12));
    }
}

test "findValidMoves - returns slice length matches buffer" {
    var deck = makeDeck();
    const board = Board.init(&deck);
    var buffer: [128]Move = undefined;

    const moves = board.findValidMoves(&buffer);

    // Verify slice points to buffer
    try std.testing.expect(moves.len <= buffer.len);
}

test "findValidMoves - king to empty column" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: King in one column, empty column
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 1 }; // Empty
    board.cards[0] = makeCard(Suit.Hearts, 13); // King

    const moves = board.findValidMoves(&buffer);

    // King should be able to move to empty column
    var found_move = false;
    for (moves) |move| {
        if (move.from == 0 and move.to == 1) {
            found_move = true;
            break;
        }
    }
    try std.testing.expect(found_move);
}

test "findValidMoves - ace cannot move below king" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: Ace in column 0, King in column 1
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.cards[0] = makeCard(Suit.Hearts, 1); // Red Ace
    board.cards[1] = makeCard(Suit.Spades, 13); // Black King

    const moves = board.findValidMoves(&buffer);

    // Ace cannot move below King (rank mismatch)
    for (moves) |move| {
        try std.testing.expect(!(move.from == 0 and move.to == 1));
    }
}

test "findValidMoves - sequence of valid descending moves" {
    var board = Board{};
    var buffer: [128]Move = undefined;

    // Set up: sequence 5->6->7 with alternating colors
    board.columns[0] = .{ 0, 1 };
    board.columns[1] = .{ 1, 2 };
    board.columns[2] = .{ 2, 3 };
    board.cards[0] = makeCard(Suit.Hearts, 5); // Red 5
    board.cards[1] = makeCard(Suit.Spades, 6); // Black 6
    board.cards[2] = makeCard(Suit.Diamonds, 7); // Red 7

    const moves = board.findValidMoves(&buffer);

    // Should find move from column 0 to column 1
    var found_move_0_1 = false;
    var found_move_1_2 = false;
    for (moves) |move| {
        if (move.from == 0 and move.to == 1) found_move_0_1 = true;
        if (move.from == 1 and move.to == 2) found_move_1_2 = true;
    }
    try std.testing.expect(found_move_0_1);
    try std.testing.expect(found_move_1_2);
}

// ============================================================================
// findSlotContainingCard Tests
// ============================================================================

test "findSlotContainingCard - finds card in free cell" {
    var board = Board{};
    const test_card = makeCard(Suit.Hearts, 7);
    board.cells[2] = test_card;

    const slot = board.findSlotContainingCard(test_card);

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 10); // Slot 8 + 2
}

test "findSlotContainingCard - finds card at top of foundation pile" {
    var board = Board{};
    board.piles[1] = 5; // Clubs pile has 5 cards (top card is rank 5)

    const test_card = makeCard(Suit.Clubs, 5);
    const slot = board.findSlotContainingCard(test_card);

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 13); // NUM_COLUMNS + 4 + 1
}

test "findSlotContainingCard - finds ace at top of foundation" {
    var board = Board{};
    board.piles[0] = 1; // Spades pile has 1 card (the ace)

    const test_card = makeCard(Suit.Spades, 1);
    const slot = board.findSlotContainingCard(test_card);

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 12);
}

test "findSlotContainingCard - does not find card buried in foundation pile" {
    var board = Board{};
    board.piles[2] = 5; // Hearts pile has 5 cards

    const test_card = makeCard(Suit.Hearts, 3); // Rank 3 is buried
    const slot = board.findSlotContainingCard(test_card);

    try std.testing.expect(slot == null);
}

test "findSlotContainingCard - finds card at top of column" {
    var board = Board{};
    board.columns[3] = .{ 0, 3 };
    board.cards[0] = makeCard(Suit.Diamonds, 2);
    board.cards[1] = makeCard(Suit.Hearts, 8);
    board.cards[2] = makeCard(Suit.Spades, 6); // Top card

    const slot = board.findSlotContainingCard(makeCard(Suit.Spades, 6));

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 3);
}

test "findSlotContainingCard - does not find card buried in column" {
    var board = Board{};
    board.columns[0] = .{ 0, 4 };
    board.cards[0] = makeCard(Suit.Hearts, 3);
    board.cards[1] = makeCard(Suit.Spades, 7);
    board.cards[2] = makeCard(Suit.Clubs, 9);
    board.cards[3] = makeCard(Suit.Hearts, 10); // Top card

    const slot = board.findSlotContainingCard(makeCard(Suit.Hearts, 3));

    try std.testing.expect(slot == null);
}

test "findSlotContainingCard - finds top card of first column" {
    var board = Board{};
    board.columns[0] = .{ 5, 8 };
    board.cards[7] = makeCard(Suit.Hearts, 4); // Top card at index 7

    const slot = board.findSlotContainingCard(makeCard(Suit.Hearts, 4));

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 0);
}

test "findSlotContainingCard - finds top card of last column" {
    var board = Board{};
    board.columns[7] = .{ 40, 45 };
    board.cards[44] = makeCard(Suit.Clubs, 11);

    const slot = board.findSlotContainingCard(makeCard(Suit.Clubs, 11));

    try std.testing.expect(slot != null);
    try std.testing.expect(slot.? == 7);
}

test "findSlotContainingCard - returns null for card not on board" {
    var board = Board{};
    board.cells[0] = makeCard(Suit.Hearts, 7);
    board.columns[0] = .{ 0, 1 };
    board.cards[0] = makeCard(Suit.Spades, 5);

    const slot = board.findSlotContainingCard(makeCard(Suit.Diamonds, 13));

    try std.testing.expect(slot == null);
}

test "findSlotContainingCard - empty board returns null" {
    const board = Board{};

    const slot = board.findSlotContainingCard(makeCard(Suit.Hearts, 1));

    try std.testing.expect(slot == null);
}

test "findSlotContainingCard - all four foundation piles" {
    var board = Board{};
    board.piles[0] = 3; // Spades
    board.piles[1] = 7; // Clubs
    board.piles[2] = 12; // Hearts
    board.piles[3] = 13; // Diamonds (complete)

    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Spades, 3)) == 12);
    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Clubs, 7)) == 13);
    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Hearts, 12)) == 14);
    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Diamonds, 13)) == 15);
}

test "findSlotContainingCard - empty foundation piles return null" {
    var board = Board{};
    board.piles[0] = 0;
    board.piles[1] = 0;
    board.piles[2] = 0;
    board.piles[3] = 0;

    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Spades, 1)) == null);
    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Hearts, 1)) == null);
}

test "findSlotContainingCard - empty columns return null" {
    var board = Board{};
    board.columns[0] = .{ 0, 0 };
    board.columns[1] = .{ 0, 0 };

    try std.testing.expect(board.findSlotContainingCard(makeCard(Suit.Hearts, 1)) == null);
}
