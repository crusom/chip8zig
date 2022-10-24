const std = @import("std");
const expect = std.testing.expect;

const StackError = error{
    FullStack,
    EmptyStack,
};

pub fn Stack(comptime T: type, comptime arg_size: usize) type {
    return struct {
        const Self = @This();
        size: usize = 0,
        array: [arg_size]T = undefined,

        pub fn init() Self {
            return Self{};
        }

        pub fn is_empty(self: *Self) bool {
            if (self.size == 0) return true;
            return false;
        }
        pub fn push(self: *Self, value: T) StackError!void {
            if (self.size == self.array.len) return error.FullStack;
            self.size += 1;
            self.array[self.size - 1] = value;
        }

        pub fn pop(self: *Self) StackError!T {
            if (self.is_empty()) return error.EmptyStack;
            const ret = self.array[self.size - 1];
            self.size -= 1;
            return ret;
        }
    };
}
test "stack test1" {
    var stack: Stack(u16, 100) = Stack(u16, 100).init();
    try stack.push(1);
    try stack.push(2);
    try stack.push(3);
    try expect(try stack.pop() == 3);
    try expect(try stack.pop() == 2);
    try expect(try stack.pop() == 1);
    try expect(stack.pop() == StackError.EmptyStack);
}

test "stack test2" {
    var stack: Stack(u16, 100) = Stack(u16, 100).init();
    try stack.push(1);
    try expect(try stack.pop() == 1);
    try stack.push(2);
    try expect(try stack.pop() == 2);
    try stack.push(3);
    try expect(try stack.pop() == 3);
    try expect(stack.is_empty() == true);
}
