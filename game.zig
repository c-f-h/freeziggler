const std = @import("std");
const board_mod = @import("board.zig");
const card_mod = @import("card.zig");

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
    var board = Board.init(&deck);
    board.reallocateColumns();
    return board;
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
