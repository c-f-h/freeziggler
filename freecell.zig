const std = @import("std");

const Card = u8;
const CARD_NONE: Card = 0; // Represents no card or an empty slot

// hearts (♥), diamonds (♦), clubs (♣), spades (♠)

const RED_BIT: u8 = 1 << 7;

fn color(c: Card) u8 {
    return c & RED_BIT;
}

const Suit = enum(u8) {
    Spades = 0,
    Clubs = (1 << 6),
    Hearts = RED_BIT | (0),
    Diamonds = RED_BIT | (1 << 6),
};

// index in the suit order (0-3)
fn suitIndex(suit: Suit) usize {
    return @intFromEnum(suit) >> 6;
}

fn makeCard(suit: Suit, rank: u8) Card {
    return @intFromEnum(suit) | rank;
}

fn suitString(suit: Suit) []const u8 {
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

fn rankName(rank: u8) u8 {
    return switch (rank) {
        1 => 'A',
        10 => '0',
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        else => '0' + rank,
    };
}

fn canMoveBelow(card: Card, target: Card) bool {
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

const NUM_COLUMNS = 8;
const TABLEAU_SIZE = 64;

const Board = struct {
    cells: [4]Card = [_]Card{CARD_NONE} ** 4, // Free cells
    piles: [4]u8 = [_]u8{0} ** 4, // Foundation piles (top card rank)
    columns: [NUM_COLUMNS][2]u8 = .{ .{ 0, 7 }, .{ 8, 15 }, .{ 16, 23 }, .{ 24, 31 }, .{ 32, 38 }, .{ 40, 46 }, .{ 48, 54 }, .{ 56, 62 } }, // Column ranges (start, end)
    cards: [TABLEAU_SIZE]Card = [_]Card{CARD_NONE} ** TABLEAU_SIZE, // Cards in the tableau

    fn init(board: *Board, deck: *[52]Card) void {
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

    fn cardInSlot(board: *const Board, slot: u8) Card {
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

    // TODO: fix
    fn makeMove(board: *Board, from: u8, to: u8) void {
        const card = board.cardInSlot(from);
        if (card == CARD_NONE) return; // No card to move
    }

    fn print(board: *const Board) void {
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

    fn findValidMoves(board: *const Board) void {
        var i: u8 = 0;
        while (i < NUM_COLUMNS - 1) : (i += 1) {
            const card_i = board.cardInSlot(i);
            if (card_i == CARD_NONE) continue; // Skip empty columns

            var j: u8 = i + 1;
            while (j < NUM_COLUMNS) : (j += 1) {
                const card_j = board.cardInSlot(j);
                if (card_j == CARD_NONE) continue; // Skip empty columns

                if (canMoveBelow(card_i, card_j)) {
                    std.debug.print("Can move from column {d} to column {d}\n", .{ i, j });
                } else if (canMoveBelow(card_j, card_i)) {
                    std.debug.print("Can move from column {d} to column {d}\n", .{ j, i });
                }
            }

            //// Check moves to free cells
            //for (self.cells) |cell| {
            //    if (cell == CARD_NONE) {
            //        std.debug.print("Can move {c} to free cell\n", .{card});
            //    }
            //}
            //// Check moves to foundation piles
            //for (self.piles, 0..) |pile, j| {
            //    if (canMoveBelow(card, makeCard(@enumFromInt(j << 6), pile + 1))) {
            //        std.debug.print("Can move {c} to foundation pile {s}\n", .{card, suitString(@enumFromInt(j << 6))});
            //    }
            //}
        }
    }
};

fn makeDeck() [52]Card {
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

pub fn main() void {
    var deck = makeDeck();
    var rng = std.Random.DefaultPrng.init(0); // Initialize RNG with a seed (0 for deterministic)
    std.Random.shuffle(rng.random(), Card, &deck);

    var board = Board{};
    board.init(&deck);

    board.print(); // Example: print the entire board
    board.findValidMoves(); // Example: find and print valid moves
}
