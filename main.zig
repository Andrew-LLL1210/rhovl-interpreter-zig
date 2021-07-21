usingnamespace @import("lib.zig");

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const pow = std.math.pow;
const mem = std.mem;

const RuntimeError = error{CannotStore};
const WriteError = std.os.WriteError || RuntimeError;
// the type of stdout _eugh_
const Stdout = std.io.Writer(std.fs.File,std.os.WriteError,std.fs.File.write);

pub fn main() !void {

    

    const stdout = std.io.getStdOut().writer();
    var buffer: [1024 * 4]u8 = .{0} ** (1024 * 4);

    const len: usize = try read("source.txt", buffer[0..]);
    const source: []const u8 = buffer[0..len];
    // const source: []const u8 = "(1:97$32$99$)";
    print("source code:\n{s}\n", .{source});
    // for (source) |char| {
    //     print("{x} ", .{char});
    // }

    const tokens: []const Token = (try tokenize(source)).tokens;
    // print("tokens:\n{any}\n", .{tokens});

    var progm: Program = Program{.stdout = stdout};
    try progm.run(tokens);
}

const Program = struct{
    data: u8 = 0,
    registers: [26]u8 = .{0} ** 26,
    stdout: Stdout,

    fn run(self: *Program, tokens: []const Token) WriteError!void {
        for(tokens) |token| {
            try self.doSingle(token);
        }
    }
    fn doSingle(self: *Program, token: Token) WriteError!void {
        switch (token) {
            .number => |x| { self.data = x; },
            .register => |i| { self.data = self.registers[i]; },
            .operation => |operation| {
                var a: u8 = self.data;
                var b: u8 = self.get(operation.target);
                if (operation.in_place) {
                    const tmp: u8 = a;
                    a = b; b = tmp;
                }
                const res: u8 = switch(operation.op_type) {
                    .add => a +% b, .sub => a -% b,
                    .mul => a *% b, .div => a / b,
                    .mod => a % b,
                    .exp => pow(u8, a, b),
                    .band => a & b, .bor => a | b,
                    .bxor => a ^ b,
                    .gt  => bit(a >  b), .lt  => bit(a <  b),
                    .gte => bit(a >= b), .lte => bit(a <= b),
                    .eq  => bit(a == b), .neq => bit(a != b),
                    .nop => b,
                };
                if (operation.in_place) {
                    self.registers[operation.target.register] = res;
                } else {
                    self.data = res;
                }
            },
            .output => |optn| {
                try switch (optn) {
                    .ascii => self.stdout.print("{c}", .{self.data}),
                    .number => self.stdout.print("{}", .{self.data}),
                    .newline => self.stdout.print("{}\n", .{self.data}),
                    .space => self.stdout.print("{} ", .{self.data}),
                    .list => self.stdout.print("{}, ", .{self.data}),
                };
            },
            .if_block => |if_block| {
                try self.run(if_block.condition);
                while (self.data != 0) : (try self.run(if_block.condition)) {
                    try self.run(if_block.body);
                    if (!if_block.repeat) break;
                }
            },
            .for_block => |for_block| {
                for (for_block.list) |item, i| {
                    try self.doSingle(item);
                    try self.run(for_block.body);
                    if (for_block.into) |tail| {
                        switch(tail[i]) {
                            .register => |r| self.registers[r] = self.data,
                            else => return RuntimeError.CannotStore,
                        }
                    }
                }
            }
            // TODO: test tokenizer on for-structures, implement for-logic
        }
    }
    fn get(self: *Program, target: Value) u8 {
        return switch (target) {
            .number => |x| x,
            .register => |i| self.registers[i],
        };
    }
};


// test "typeof writer" {
    
//     const stdout = std.io.getStdOut().writer();
//     print("type of the writer is: {any}", .{@TypeOf(stdout)});
// }