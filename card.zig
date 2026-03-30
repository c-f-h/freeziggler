const std = @import("std");

pub const Card = u8;
pub const CARD_NONE: Card = 0;

pub const RED_BIT: u8 = 1 << 7;

pub fn color(c: Card) u8 {
    return c & RED_BIT;
}

// spades (♠), clubs (♣), hearts (♥), diamonds (♦)

pub const Suit = enum(u8) {
    Spades = 0,
    Clubs = (1 << 6),
    Hearts = RED_BIT | (0),
    Diamonds = RED_BIT | (1 << 6),
};

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

pub fn printCard(card: Card) void {
    if (card == CARD_NONE) {
        std.debug.print("  ", .{});
        return;
    }
    const rank = card & 0b0000_1111;
    const suit: Suit = @enumFromInt(card & 0b1100_0000);
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

var str_buffer: [8]u8 = undefined;

pub fn cardName(card: Card) []const u8 {
    if (card == CARD_NONE) {
        return "  ";
    }
    const rank = card & 0b0000_1111;
    const suit: Suit = @enumFromInt(card & 0b1100_0000);
    if (std.fmt.bufPrint(&str_buffer, "{s}{c}", .{ suitString(suit), rankName(rank) })) |name| {
        return name;
    } else |_| {
        return "  ";
    }
}

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
    var count: usize = 0;
    for (deck) |card| {
        try std.testing.expect(card != CARD_NONE);
        count += 1;
    }
    try std.testing.expect(count == 52);
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
