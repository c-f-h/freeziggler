const std = @import("std");
const freecell = @import("freecell.zig");

// Import types and functions from main module
const Card = freecell.Card;
const Suit = freecell.Suit;
const Board = freecell.Board;
const CARD_NONE = freecell.CARD_NONE;
const RED_BIT = freecell.RED_BIT;
const NUM_COLUMNS = freecell.NUM_COLUMNS;
const TABLEAU_SIZE = freecell.TABLEAU_SIZE;

// Import functions
const color = freecell.color;
const suitIndex = freecell.suitIndex;
const makeCard = freecell.makeCard;
const suitString = freecell.suitString;
const rankName = freecell.rankName;
const canMoveBelow = freecell.canMoveBelow;
const makeDeck = freecell.makeDeck;

// ============================================================================
// Unit Tests
// ============================================================================

test "makeCard and basic card properties" {
    const card_h5 = makeCard(Suit.Hearts, 5);
    const card_s1 = makeCard(Suit.Spades, 1);
    const card_d13 = makeCard(Suit.Diamonds, 13);
    const card_c10 = makeCard(Suit.Clubs, 10);

    // Verify card creation
    try std.testing.expect(card_h5 & 0b0000_1111 == 5);
    try std.testing.expect(card_s1 & 0b0000_1111 == 1);
    try std.testing.expect(card_d13 & 0b0000_1111 == 13);
    try std.testing.expect(card_c10 & 0b0000_1111 == 10);
}

test "color function - red cards" {
    const hearts_5 = makeCard(Suit.Hearts, 5);
    const diamonds_10 = makeCard(Suit.Diamonds, 10);

    try std.testing.expect(color(hearts_5) == RED_BIT);
    try std.testing.expect(color(diamonds_10) == RED_BIT);
}

test "color function - black cards" {
    const spades_5 = makeCard(Suit.Spades, 5);
    const clubs_10 = makeCard(Suit.Clubs, 10);

    try std.testing.expect(color(spades_5) == 0);
    try std.testing.expect(color(clubs_10) == 0);
}

test "suitIndex function" {
    try std.testing.expect(suitIndex(Suit.Spades) == 0);
    try std.testing.expect(suitIndex(Suit.Clubs) == 1);
    try std.testing.expect(suitIndex(Suit.Hearts) == 2);
    try std.testing.expect(suitIndex(Suit.Diamonds) == 3);
}

test "canMoveBelow - valid moves" {
    const red_5 = makeCard(Suit.Hearts, 5);
    const black_6 = makeCard(Suit.Spades, 6);
    const red_6 = makeCard(Suit.Diamonds, 6);

    // Can move red 5 below black 6
    try std.testing.expect(canMoveBelow(red_5, black_6) == true);
    // Can move black 5 below red 6
    const black_5 = makeCard(Suit.Clubs, 5);
    try std.testing.expect(canMoveBelow(black_5, red_6) == true);
}

test "canMoveBelow - invalid moves (same color)" {
    const red_5 = makeCard(Suit.Hearts, 5);
    const red_6 = makeCard(Suit.Diamonds, 6);

    try std.testing.expect(canMoveBelow(red_5, red_6) == false);
}

test "canMoveBelow - invalid moves (wrong rank)" {
    const red_5 = makeCard(Suit.Hearts, 5);
    const black_7 = makeCard(Suit.Spades, 7);

    try std.testing.expect(canMoveBelow(red_5, black_7) == false);
}

test "canMoveBelow - with Ace and King" {
    const black_ace = makeCard(Suit.Spades, 1);
    const red_2 = makeCard(Suit.Hearts, 2);
    const red_king = makeCard(Suit.Diamonds, 13);

    try std.testing.expect(canMoveBelow(black_ace, red_2) == true);
    try std.testing.expect(canMoveBelow(red_king, black_ace) == false);
}

test "Board.init - distributes cards correctly" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // First 4 columns should have 7 cards each (4 * 7 = 28)
    var total_first_four: u8 = 0;
    for (board.columns[0..4]) |col| {
        total_first_four += col[1] - col[0];
    }

    // Last 4 columns should have 6 cards each (4 * 6 = 24)
    var total_last_four: u8 = 0;
    for (board.columns[4..8]) |col| {
        total_last_four += col[1] - col[0];
    }

    try std.testing.expect(total_first_four == 28);
    try std.testing.expect(total_last_four == 24);
    try std.testing.expect(board.numCardsOnTableau() == 52);
}

test "Board.numCardsInColumn" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

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
    var board = Board{};
    board.init(&deck);

    try std.testing.expect(board.numCardsOnTableau() == 52);
}

test "Board.cardInSlot - columns" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Get top card of first column (slot 0)
    const card_col0 = board.cardInSlot(0);
    try std.testing.expect(card_col0 != CARD_NONE);

    // Get top card of last column (slot 7)
    const card_col7 = board.cardInSlot(7);
    try std.testing.expect(card_col7 != CARD_NONE);
}

test "Board.cardInSlot - free cells (empty)" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Free cells are initially empty (slots 8-11)
    try std.testing.expect(board.cardInSlot(8) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(9) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(10) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(11) == CARD_NONE);
}

test "Board.cardInSlot - foundation piles (empty)" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Foundation piles are initially empty (slots 12-15)
    try std.testing.expect(board.cardInSlot(12) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(13) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(14) == CARD_NONE);
    try std.testing.expect(board.cardInSlot(15) == CARD_NONE);
}

test "Board.cardInSlot - free cells (with cards)" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const test_card = makeCard(Suit.Hearts, 5);
    board.cells[0] = test_card;

    try std.testing.expect(board.cardInSlot(8) == test_card);
}

test "Board.cardInSlot - foundation piles (with cards)" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    board.piles[2] = 3; // Hearts pile with 3 cards

    const returned_card = board.cardInSlot(14); // Hearts foundation (slot 14)
    const expected_card = makeCard(Suit.Hearts, 3);

    try std.testing.expect(returned_card == expected_card);
}

test "Board.columnIsFull - new board" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Columns are not full initially (they are packed but not filled to max)
    try std.testing.expect(!board.columnIsFull(0));
    try std.testing.expect(!board.columnIsFull(7));
}

test "Board.columnIsFull - after filling" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Manually make a column full by moving its end to the next column's start
    board.columns[0][1] = board.columns[1][0];

    try std.testing.expect(board.columnIsFull(0));
}

test "Board.reallocateColumns - preserves all cards" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

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
    var board = Board{};
    board.init(&deck);

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
    var board = Board{};
    board.init(&deck);

    for (board.cells) |cell| {
        try std.testing.expect(cell == CARD_NONE);
    }
}

test "Board.init - empty foundation piles initially" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    for (board.piles) |pile| {
        try std.testing.expect(pile == 0);
    }
}

test "Board - complex scenario: move cards between free cells and foundation" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

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

test "rankName function" {
    try std.testing.expect(rankName(1) == 'A');
    try std.testing.expect(rankName(10) == '0');
    try std.testing.expect(rankName(11) == 'J');
    try std.testing.expect(rankName(12) == 'Q');
    try std.testing.expect(rankName(13) == 'K');
    try std.testing.expect(rankName(2) == '2');
    try std.testing.expect(rankName(9) == '9');
}

test "suitString function" {
    try std.testing.expectEqualSlices(u8, suitString(Suit.Spades), "S");
    try std.testing.expectEqualSlices(u8, suitString(Suit.Clubs), "C");
    try std.testing.expectEqualSlices(u8, suitString(Suit.Hearts), "H");
    try std.testing.expectEqualSlices(u8, suitString(Suit.Diamonds), "D");
}

test "makeDeck - creates full deck of 52 cards" {
    const deck = makeDeck();

    // Verify we have 52 cards
    var filled_count: usize = 0;
    for (deck) |card| {
        if (card != CARD_NONE) {
            filled_count += 1;
        }
    }
    try std.testing.expect(filled_count == 52);
}

test "makeDeck - all suits present" {
    const deck = makeDeck();

    var suit_counts: [4]u8 = .{ 0, 0, 0, 0 };
    for (deck) |card| {
        const suit = suitIndex(@as(Suit, @enumFromInt(card & 0b1100_0000)));
        suit_counts[suit] += 1;
    }

    // Each suit should have exactly 13 cards
    for (suit_counts) |count| {
        try std.testing.expect(count == 13);
    }
}

test "makeDeck - all ranks present in each suit" {
    const deck = makeDeck();

    var ranks_per_suit: [4][14]bool = .{ .{false} ** 14, .{false} ** 14, .{false} ** 14, .{false} ** 14 };

    for (deck) |card| {
        const suit = suitIndex(@as(Suit, @enumFromInt(card & 0b1100_0000)));
        const rank = card & 0b0000_1111;
        ranks_per_suit[suit][rank] = true;
    }

    // Each suit should have ranks 1-13 (skip 0 and 14)
    for (ranks_per_suit) |ranks| {
        for (1..14) |rank| {
            try std.testing.expect(ranks[rank] == true);
        }
    }
}

test "CARD_NONE constant" {
    try std.testing.expect(CARD_NONE == 0);
}

test "Board initialization idempotent" {
    var deck1 = makeDeck();
    var deck2 = makeDeck();
    var board1 = Board{};
    var board2 = Board{};

    board1.init(&deck1);
    board2.init(&deck2);

    // Both boards should have same number of cards in same positions
    for (board1.columns, board2.columns) |col1, col2| {
        try std.testing.expect((col1[1] - col1[0]) == (col2[1] - col2[0]));
    }
}

test "Board - all columns contain valid cards" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

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
    var board = Board{};
    board.init(&deck);

    const top_card = board.cardInSlot(0);
    const initial_count = board.numCardsInColumn(0);

    board.makeMove(0, 8); // Move from column 0 to free cell 0 (slot 8)

    try std.testing.expect(board.cardInSlot(8) == top_card);
    try std.testing.expect(board.numCardsInColumn(0) == initial_count - 1);
}

test "makeMove - from free cell to column" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const test_card = makeCard(Suit.Hearts, 3);
    board.cells[0] = test_card;

    const initial_count = board.numCardsInColumn(1);

    board.makeMove(8, 1); // Move from free cell 0 (slot 8) to column 1

    try std.testing.expect(board.cardInSlot(1) == test_card);
    try std.testing.expect(board.numCardsInColumn(1) == initial_count + 1);
    try std.testing.expect(board.cells[0] == CARD_NONE);
}

test "makeMove - from column to foundation" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Set up: place an ace of hearts in a free cell
    const ace_hearts = makeCard(Suit.Hearts, 1);
    board.cells[0] = ace_hearts;

    board.makeMove(8, 14); // Move from free cell 0 to hearts foundation (slot 14)

    try std.testing.expect(board.piles[2] == 1); // Hearts pile now has 1 card (rank 1)
    try std.testing.expect(board.cardInSlot(14) == ace_hearts);
    try std.testing.expect(board.cells[0] == CARD_NONE);
}

test "makeMove - from foundation to free cell" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Set up: place cards in foundation
    board.piles[0] = 3; // Spades pile with 3 cards

    const spadesCard = makeCard(Suit.Spades, 3);

    board.makeMove(12, 8); // Move from spades foundation (slot 12) to free cell (slot 8)

    try std.testing.expect(board.piles[0] == 2); // Spades pile now has 2 cards
    try std.testing.expect(board.cells[0] == spadesCard);
}

test "makeMove - from empty slot (should do nothing)" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const initial_cards = board.numCardsOnTableau();

    board.makeMove(8, 0); // Try to move from empty free cell 0

    try std.testing.expect(board.numCardsOnTableau() == initial_cards); // No change
}

test "makeMove - preserves total card count" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const initial_cards = board.numCardsOnTableau();

    board.makeMove(0, 8); // Move from column to free cell

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
    var board = Board{};
    board.init(&deck);

    const test_card = makeCard(Suit.Diamonds, 7);
    board.cells[0] = test_card;

    board.makeMove(8, 9); // Move from free cell 0 to free cell 1

    try std.testing.expect(board.cells[0] == CARD_NONE);
    try std.testing.expect(board.cells[1] == test_card);
}

test "makeMove - column to column, removes from source" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const col0_count = board.numCardsInColumn(0);
    const col1_count = board.numCardsInColumn(1);

    board.makeMove(0, 1); // Move from column 0 to column 1

    try std.testing.expect(board.numCardsInColumn(0) == col0_count - 1);
    try std.testing.expect(board.numCardsInColumn(1) == col1_count + 1);
}

test "makeMove - reallocation ensures space" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Get initial card count
    const initial_cards = board.numCardsOnTableau();

    // Make multiple moves to fill up a column
    // Move several cards from different columns to column 0
    for (0..4) |i| {
        const source_slot: u8 = @intCast(1 + i);
        board.makeMove(source_slot, 0);
    }

    // After these moves, column 0 should be full
    try std.testing.expect(board.columnIsFull(0));

    // Verify cards were moved and no cards were lost
    try std.testing.expect(board.numCardsOnTableau() == initial_cards);

    // Verify we can still make more moves without issues
    const card = board.cardInSlot(2);
    board.makeMove(2, 0);
    try std.testing.expect(board.numCardsOnTableau() == initial_cards);
    try std.testing.expect(board.cardInSlot(0) == card);
}

test "makeMove - multiple sequential moves" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    const initial_count = board.numCardsOnTableau();

    const card1 = board.cardInSlot(0);
    board.makeMove(0, 8); // Move to free cell 0

    const card2 = board.cardInSlot(1);
    board.makeMove(1, 9); // Move to free cell 1

    try std.testing.expect(board.cells[0] == card1);
    try std.testing.expect(board.cells[1] == card2);
    try std.testing.expect(board.numCardsOnTableau() == initial_count - 2);
}

test "makeMove - all foundation piles" {
    var deck = makeDeck();
    var board = Board{};
    board.init(&deck);

    // Set up: place aces in free cells
    board.cells[0] = makeCard(Suit.Spades, 1);
    board.cells[1] = makeCard(Suit.Clubs, 1);
    board.cells[2] = makeCard(Suit.Hearts, 1);
    board.cells[3] = makeCard(Suit.Diamonds, 1);

    // Move each ace to foundation
    board.makeMove(8, 12); // Spades ace to spades foundation
    board.makeMove(9, 13); // Clubs ace to clubs foundation
    board.makeMove(10, 14); // Hearts ace to hearts foundation
    board.makeMove(11, 15); // Diamonds ace to diamonds foundation

    try std.testing.expect(board.piles[0] == 1); // Spades
    try std.testing.expect(board.piles[1] == 1); // Clubs
    try std.testing.expect(board.piles[2] == 1); // Hearts
    try std.testing.expect(board.piles[3] == 1); // Diamonds

    for (board.cells) |cell| {
        try std.testing.expect(cell == CARD_NONE);
    }
}
