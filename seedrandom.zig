const std = @import("std");

// A reimplementation of David Bau's seedrandom.js as used on free-freecell-solitaire.com

const WIDTH: u32 = 256;
const CHUNKS: u32 = 6;
const START_DENOM: f64 = 281474976710656.0; // 2^48
const SIGNIFICANCE: f64 = 4503599627370496.0; // 2^52
const OVERFLOW: f64 = 9007199254740992.0; // 2^53
const MASK: usize = WIDTH - 1;

const Arc4 = struct {
    i: u8 = 0,
    j: u8 = 0,
    s: [256]u8 = undefined,

    fn init(key_input: []const u8) Arc4 {
        var key_fallback = [_]u8{0};
        const key = if (key_input.len == 0) key_fallback[0..] else key_input;

        var arc4: Arc4 = .{};
        for (&arc4.s, 0..) |*item, idx| {
            item.* = @intCast(idx);
        }

        var j: usize = 0;
        for (0..256) |idx| {
            const si = arc4.s[idx];
            j = (j + si + key[idx % key.len]) & MASK;
            arc4.s[idx] = arc4.s[j];
            arc4.s[j] = si;
        }

        _ = arc4.g(WIDTH);
        return arc4;
    }

    fn g(self: *Arc4, count: u32) u64 {
        var value: u64 = 0;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            self.i +%= 1;
            const si = self.s[self.i];
            self.j +%= si;
            const sj = self.s[self.j];
            self.s[self.i] = sj;
            self.s[self.j] = si;
            const idx: u8 = self.s[self.i] +% self.s[self.j];
            value = (value *% WIDTH) +% self.s[idx];
        }
        return value;
    }
};

fn mixKey(seed: []const u8, key: *[256]u8, key_len: *usize) void {
    var smear: u32 = 0;
    for (seed, 0..) |char_code, idx| {
        const key_idx = idx & MASK;
        const key_val: u32 = if (key_idx < key_len.*) key[key_idx] else 0;
        smear ^= 19 * key_val;
        key[key_idx] = @intCast((smear + char_code) & MASK);
        if (key_idx + 1 > key_len.*) {
            key_len.* = key_idx + 1;
        }
    }
}

pub const SeedRandom = struct {
    arc4: Arc4,

    // Mirrors new Math.seedrandom(gameNumber) for numeric game numbers.
    pub fn initFromGameNumber(game_number: u64) SeedRandom {
        var seed_buf: [32]u8 = undefined;
        const seed_text = std.fmt.bufPrint(seed_buf[0..], "{d}", .{game_number}) catch unreachable;

        var seed_with_nul: [33]u8 = undefined;
        @memcpy(seed_with_nul[0..seed_text.len], seed_text);
        seed_with_nul[seed_text.len] = 0;
        const seed = seed_with_nul[0 .. seed_text.len + 1];

        var key_buf: [256]u8 = [_]u8{0} ** 256;
        var key_len: usize = 0;
        mixKey(seed, &key_buf, &key_len);

        return .{ .arc4 = Arc4.init(key_buf[0..key_len]) };
    }

    pub fn next(self: *SeedRandom) f64 {
        var n = @as(f64, @floatFromInt(self.arc4.g(CHUNKS)));
        var d = START_DENOM;
        var x: u64 = 0;

        while (n < SIGNIFICANCE) {
            n = (n + @as(f64, @floatFromInt(x))) * WIDTH;
            d *= WIDTH;
            x = self.arc4.g(1);
        }
        while (n >= OVERFLOW) {
            n /= 2.0;
            d /= 2.0;
            x >>= 1;
        }
        return (n + @as(f64, @floatFromInt(x))) / d;
    }
};
