const std = @import("std");
const board_mod = @import("board.zig");
const card_mod = @import("card.zig");
const seedrandom = @import("seedrandom.zig");

const Board = board_mod.Board;
const Card = card_mod.Card;
const Suit = card_mod.Suit;
const makeCard = card_mod.makeCard;
const makeDeck = card_mod.makeDeck;
const cardName = card_mod.cardName;
const NUM_COLUMNS = board_mod.NUM_COLUMNS;

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
    return Board.init(&deck);
}

fn makeDeckFreecellSolitaireDotCom() [52]Card {
    var cards: [52]Card = undefined;
    var index: usize = 0;

    // JS order used by free-freecell-solitaire.com: spades, hearts, clubs, diamonds
    const suit_order = [_]Suit{ .Spades, .Hearts, .Clubs, .Diamonds };
    for (suit_order) |suit| {
        var rank: u8 = 1;
        while (rank <= 13) : (rank += 1) {
            cards[index] = makeCard(suit, rank);
            index += 1;
        }
    }

    return cards;
}

/// Create a random board using the algorithm used at free-freecell-solitaire.com
pub fn createRandomBoardFreecellSolitaireDotCom(game_number: u64) Board {
    const deck = makeDeckFreecellSolitaireDotCom();
    var rng = seedrandom.SeedRandom.initFromGameNumber(game_number);

    var available_indexes: [52]u8 = undefined;
    for (&available_indexes, 0..) |*index, i| {
        index.* = @intCast(i);
    }
    var available_len: usize = available_indexes.len;

    var dealt: [52]Card = undefined;
    var dealt_idx: usize = 0;

    // Freecell (single deck) tableau counts: [7,7,7,7,6,6,6,6]
    const tableau_sizes = [_]u8{ 7, 7, 7, 7, 6, 6, 6, 6 };
    for (tableau_sizes) |cards_to_deal| {
        var i: u8 = 0;
        while (i < cards_to_deal) : (i += 1) {
            const pick = @as(usize, @intFromFloat(@floor(rng.next() * @as(f64, @floatFromInt(available_len)))));
            const deck_index = available_indexes[pick];
            dealt[dealt_idx] = deck[deck_index];
            dealt_idx += 1;

            if (pick + 1 < available_len) {
                available_indexes[pick] = available_indexes[available_len - 1];
            }
            available_len -= 1;
        }
    }

    std.debug.assert(dealt_idx == 52);
    std.debug.assert(available_len == 0);

    return Board.init(&dealt);
}

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
            const c = parseCardString(card_str) catch |err| {
                std.debug.print("Failed to parse card string '{s}': {s}\n", .{ card_str, @errorName(err) });
                return err;
            };
            if (idx >= card_buffer.len) {
                std.debug.print("Too many cards in JSON game: exceeded {d}\n", .{card_buffer.len});
                return error.InvalidJsonGame;
            }
            card_buffer[idx] = c;
            idx += 1;
        }
        columns[j] = card_buffer[col_start..idx];
    }
    return Board.initFromColumns(columns);
}

test "createRandomBoardFreecellSolitaireDotCom is deterministic and deals full deck" {
    const b1 = createRandomBoardFreecellSolitaireDotCom(1);
    const b2 = createRandomBoardFreecellSolitaireDotCom(1);
    const b3 = createRandomBoardFreecellSolitaireDotCom(2);

    try std.testing.expectEqualDeep(b1, b2);
    try std.testing.expect(!std.meta.eql(b1, b3));

    var seen: [256]bool = [_]bool{false} ** 256;
    var count: usize = 0;
    for (b1.columns) |col| {
        for (b1.cards[col[0]..col[1]]) |c| {
            try std.testing.expect(!seen[c]);
            seen[c] = true;
            count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 52), count);
}

test "createRandomBoardFreecellSolitaireDotCom seed 667242 matches screenshot board" {
    const b = createRandomBoardFreecellSolitaireDotCom(667242);

    const expected = [_]Card{
        // Column 1
        makeCard(Suit.Clubs, 3),
        makeCard(Suit.Diamonds, 5),
        makeCard(Suit.Spades, 2),
        makeCard(Suit.Diamonds, 13),
        makeCard(Suit.Spades, 7),
        makeCard(Suit.Spades, 9),
        makeCard(Suit.Spades, 11),

        // Column 2
        makeCard(Suit.Clubs, 10),
        makeCard(Suit.Hearts, 6),
        makeCard(Suit.Spades, 1),
        makeCard(Suit.Hearts, 9),
        makeCard(Suit.Clubs, 4),
        makeCard(Suit.Diamonds, 10),
        makeCard(Suit.Hearts, 10),

        // Column 3
        makeCard(Suit.Diamonds, 9),
        makeCard(Suit.Diamonds, 11),
        makeCard(Suit.Hearts, 11),
        makeCard(Suit.Spades, 10),
        makeCard(Suit.Diamonds, 7),
        makeCard(Suit.Diamonds, 8),
        makeCard(Suit.Hearts, 5),

        // Column 4
        makeCard(Suit.Hearts, 3),
        makeCard(Suit.Spades, 4),
        makeCard(Suit.Hearts, 8),
        makeCard(Suit.Clubs, 2),
        makeCard(Suit.Clubs, 1),
        makeCard(Suit.Diamonds, 3),
        makeCard(Suit.Diamonds, 4),

        // Column 5
        makeCard(Suit.Diamonds, 1),
        makeCard(Suit.Clubs, 9),
        makeCard(Suit.Hearts, 12),
        makeCard(Suit.Hearts, 7),
        makeCard(Suit.Hearts, 2),
        makeCard(Suit.Clubs, 8),

        // Column 6
        makeCard(Suit.Diamonds, 12),
        makeCard(Suit.Spades, 3),
        makeCard(Suit.Hearts, 1),
        makeCard(Suit.Clubs, 7),
        makeCard(Suit.Diamonds, 2),
        makeCard(Suit.Clubs, 6),

        // Column 7
        makeCard(Suit.Clubs, 11),
        makeCard(Suit.Spades, 13),
        makeCard(Suit.Hearts, 13),
        makeCard(Suit.Spades, 5),
        makeCard(Suit.Hearts, 4),
        makeCard(Suit.Diamonds, 6),

        // Column 8
        makeCard(Suit.Clubs, 5),
        makeCard(Suit.Spades, 8),
        makeCard(Suit.Clubs, 12),
        makeCard(Suit.Clubs, 13),
        makeCard(Suit.Spades, 6),
        makeCard(Suit.Spades, 12),
    };

    try std.testing.expectEqual(@as(u8, 7), b.columns[0][1] - b.columns[0][0]);
    try std.testing.expectEqual(@as(u8, 7), b.columns[1][1] - b.columns[1][0]);
    try std.testing.expectEqual(@as(u8, 7), b.columns[2][1] - b.columns[2][0]);
    try std.testing.expectEqual(@as(u8, 7), b.columns[3][1] - b.columns[3][0]);
    try std.testing.expectEqual(@as(u8, 6), b.columns[4][1] - b.columns[4][0]);
    try std.testing.expectEqual(@as(u8, 6), b.columns[5][1] - b.columns[5][0]);
    try std.testing.expectEqual(@as(u8, 6), b.columns[6][1] - b.columns[6][0]);
    try std.testing.expectEqual(@as(u8, 6), b.columns[7][1] - b.columns[7][0]);

    try std.testing.expectEqualSlices(Card, expected[0..], b.cards[0..52]);
}
