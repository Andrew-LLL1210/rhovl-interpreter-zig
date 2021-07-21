
const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub fn read(fname: []const u8, buffer: *[4096]u8) !usize {
    const flags = fs.File.OpenFlags{
        .read = true, .write = false,
        .lock = .None,

    };
    const file = try fs.cwd().openFile(fname, flags);
    defer file.close();
    
    // var buffer: [1024 * 4]u8 = .{0} ** (1024 * 4);
    const len = try file.read(buffer.*[0..]); 

    return len;
}

pub fn swapu8(ptra:*u8, ptrb:*u8) void {
    var tmp: u8 = ptra.*;
    ptra.* = ptrb.*;
    ptrb.* = tmp;
}
pub fn bit(x:bool) u8 { return if (x) 1 else 0; }

pub const TokenError = error{NotAToken, NumberTooBig, NonValue, UnbalancedParen};
pub const Token = union(enum) {
    number: u8, register: u8, operation: Operation, output: OutType,
    if_block: IfBlock, for_block: ForBlock,
};
pub const Value = union(enum) { number: u8, register: u8 };
pub const Op = enum {
    add, sub, mul, div, mod, exp, // arithmetic and in_place ops
    band, bor, bxor, // bitwise ops
    gt, lt, gte, lte, eq, neq, // comparison
    nop, // bc assignment is just in_place no-op
};
pub const Operation = struct { op_type: Op, target: Value, in_place: bool = false };
pub const OutType = enum { ascii, number, newline, space, list };
pub const IfBlock = struct { condition: []const Token, body: []const Token, repeat: bool };
pub const ForBlock = struct {
    list: []const Token,
    body: []const Token,
    into: ?[]const Token,
};
const Err = TokenError || mem.Allocator.Error;
const Package = struct {token: Token, len: usize};
const TokensPackage = struct {tokens: []const Token, len: usize};

pub fn tokenize(src: []const u8) Err!TokensPackage {
    var collector = std.ArrayList(Token).init(std.heap.page_allocator);
    // idk if this call is necessary after toOwnedSlice() but there's no complaint
    defer collector.deinit();
    var source = src;
    var len: usize = 0;

    while (try nexttoken(source)) |pkg| {
        try collector.append(pkg.token);
        source = source[pkg.len..];
        len += pkg.len;
        // std.debug.print("strnow: {s}\n", .{source});
        // std.debug.print("{s}\n", .{source});
    }
    return TokensPackage{.len = len, .tokens = collector.toOwnedSlice()};
}

fn nexttoken(src: []const u8) Err!?Package {
    var offset: usize = 0;
    var source: []const u8 = src;
    while (source.len > 0) : ({offset += 1; source = src[offset..];}) {
        switch (source[0]) {
            '$' => {
                const mark = if (source.len == 1) 0 else source[1];
                return switch(mark) {
                    '\'' => Package{.len = 2 + offset, .token = Token{.output = .number}},
                    '`'  => Package{.len = 2 + offset, .token = Token{.output = .newline}},
                    '_'  => Package{.len = 2 + offset, .token = Token{.output = .space}},
                    ','  => Package{.len = 2 + offset, .token = Token{.output = .list}},
                    else => Package{.len = 1 + offset, .token = Token{.output = .ascii}},
                };
            },
            'a'...'z', 'A'...'Z' => |c| {
                const off: u8 = if (c >= 'a') 'a' else 'A';
                const reg: u8 = c - off;
                return @as(?Package, 
                    Package{.len = 1 + offset, .token = Token{.register = reg}}
                );
            },
            '0'...'9' => {
                var num: u8 = 0;
                const i: usize = for (source) |c, j| {
                    switch(c) {
                        '0'...'9' => |c1| {
                            num = num * 10 + c1 - '0';
                        }, else => break j
                    }
                } else source.len;
                return Package{.len = i + offset, .token = Token{.number = num}};
            },
            '<', '>', '=', '!', '+', '-', '*', '/', '%', '^', '&', '|', '~' => |c1| {
                if (source.len < 2) return TokenError.NonValue;
                const is_long: bool = source[1] == '=';
                const len: usize = if(is_long) 2 else 1;
                const pkg: Package = (try nexttoken(source[len..])) orelse return TokenError.NonValue;
                const in_place: bool = (c1 == '=' and !is_long) or is_long and switch(c1) {
                    '<', '>', '=', '!', '+' => false, else => true};
                return @as(?Package, Package{
                    .len = len + pkg.len + offset,
                    .token = Token{.operation = Operation{
                        .in_place = in_place,
                        .target = try toValue(pkg.token, !in_place),
                        .op_type = switch(c1) {
                            '+' => .add, '-' => .sub,
                            '*' => .mul, '/' => .div,
                            '%' => .mod, '^' => .exp,
                            '|' => .bor, '~' => .bxor,
                            '&' => .band,
                            '<' => if (is_long) .lte else Op.lt,
                            '>' => if (is_long) .gte else Op.gt,
                            '=' => if (is_long) .eq  else Op.nop,
                            '!' => if (is_long) .neq else return TokenError.NotAToken,
                            else => unreachable
                }}}});
            },
            '(' => {
                const head: TokensPackage = try tokenize(source[1..]);
                source = source[head.len + 1..];
                if (source.len == 0) return TokenError.UnbalancedParen;
                switch (source[0]) {
                    ':', ';' => |sep| {
                        const body: TokensPackage = try tokenize(source[1..]);
                        source = source[body.len + 1..];
                        if (source.len == 0) return TokenError.UnbalancedParen;
                        if (source[0] != ')') return TokenError.UnbalancedParen;
                        return @as(?Package, Package{
                            .len = 3 + head.len + body.len + offset,
                            .token = Token{.if_block = IfBlock{
                                .condition = head.tokens, 
                                .body = body.tokens, 
                                .repeat = sep == ';'
                        }}});
                    },
                    else => return TokenError.UnbalancedParen
                }
            },
            '[' => {
                const head: TokensPackage = try tokenize(source[1..]);
                source = source[head.len + 1..];
                if (source.len == 0) return TokenError.UnbalancedParen;
                switch (source[0]) {
                    ':', ';' => |sep| {
                        const body: TokensPackage = try tokenize(source[1..]);
                        source = source[body.len + 1..];
                        if (source.len == 0) return TokenError.UnbalancedParen;
                        if (sep == ':' and source[0] == ':') {
                            const tail: TokensPackage = try tokenize(source[1..]);
                            source = source[tail.len + 1..];
                            if (source.len == 0) return TokenError.UnbalancedParen;
                            if (source[0] != ']') return TokenError.UnbalancedParen;
                            return @as(?Package, Package{
                                .len = 4 + head.len + body.len + tail.len + offset,
                                .token = Token{.for_block = ForBlock{
                                    .list = head.tokens,
                                    .body = body.tokens,
                                    .into = tail.tokens,
                            }}});
                        }
                        if (source[0] != ']') {
                            std.debug.print("at: '{s}'", .{source});
                            return TokenError.UnbalancedParen;}
                        return @as(?Package, Package{
                                .len = 3 + head.len + body.len + offset,
                                .token = Token{.for_block = ForBlock{
                                    .list = head.tokens,
                                    .body = body.tokens,
                                    .into = if (sep == ';') head.tokens else null,
                            }}});
                    },
                    else => return TokenError.UnbalancedParen,
                }
            },
            ':', ';', ')', ']' => return null,
            else => {},
        }
    }
    return null;
}

fn toValue(token: Token, allowconst: bool) TokenError!Value {
    return switch(token) {
        .register => |x| Value{.register = x},
        .number => |x| if (allowconst) Value{.number = x}
            else TokenError.NonValue,
        else => TokenError.NonValue,
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "tokenize" {
    // std.debug.print("\n", .{});
    var in: []const u8 = "\n 32- 12 a +d ";

    const tokens = (try tokenize(in)).tokens;
    // std.debug.print("{any}", .{tokens});

    try expect(tokens.len == 4);
    try expect(tokens[0].number == 32);
    try expect(tokens[1].operation.op_type == .sub);
    try expect(tokens[2].register == 0);
    try expect(tokens[3].operation.target.register == 3);
}
test "if token" {
    // std.debug.print("\n", .{});
    var in: []const u8 = "(97:$)$";

    const pkg = try tokenize(in);
    try expect(pkg.len == 7);
    const tokens = pkg.tokens;
    // std.debug.print("{any}", .{tokens});

    try expect(tokens.len == 2);
    try expect(tokens[0].if_block.condition[0].number == 97);

}
test "read" {
    var buffer: [1024 * 4]u8 = .{0} ** (1024 * 4);

    const len: usize = try read("source.txt", buffer[0..]);
    const source: []const u8 = buffer[0..len];
    const actual: []const u8 ="97$98$99$100$\n10(;$,-1)10$\n[97 98 99 100 101 102 8:: abcdefg]\n[abcdefg:+2$]\n[abcdefg:$]\n";
    try expectEqualStrings(source, actual);
    const pkg: TokensPackage = try tokenize(source);
    _ = pkg;
}