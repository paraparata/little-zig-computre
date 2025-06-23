const std = @import("std");

const MEMORY_MAX = 1 << 16;
const REG_MAX = 10;

pub const Register = enum(u16) {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    PC,
    COND,
    COUNT,
};

pub const Flags = enum(u16) {
    POS = 1 << 0,
    ZRO = 1 << 1,
    NEG = 1 << 2,
};

pub const Opcodes = enum(u16) {
    BR, // branch
    ADD, // add
    LD, // load
    ST, // store
    JSR, // jump register
    AND, // bitwise and
    LDR, // load register
    STR, // store register
    RTI, // unused
    NOT, // bitwise not
    LDI, // load indirect
    STI, // store indirect
    JMP, // jump
    RES, // reserved (unused)
    LEA, // load effective address
    TRAP, // execute trap
};

const Lzc = struct {
    memory: [MEMORY_MAX]u16,
    reg: [REG_MAX]u16,

    pub fn writeMem(self: *Lzc, address: u16, val: u16) !void {
        if (address > self.memory.len) {
            return error.OutOfBound;
        }
        self.memory[address] = val;
    }

    pub fn readMem(self: Lzc, address: u16) !u16 {
        if (address > self.memory.len) {
            return error.OutOfBound;
        }
        // TODO: MR_KBSR
        return self.memory[address];
    }

    pub fn writeReg(self: *Lzc, kind: Register, val: u16) void {
        self.reg[@intFromEnum(kind)] = val;
    }

    pub fn readReg(self: *Lzc, kind: Register) u16 {
        return self.reg[@intFromEnum(kind)];
    }

    pub fn updateFlags(self: *Lzc, r: u16) !void {
        if (r > self.reg.len) {
            return error.OutOfBound;
        }

        switch (self.reg[r]) {
            0 => self.writeReg(.COND, Flags.ZRO),
            blk: {
                const shifted = self.reg[r] >> 15;
                break :blk shifted;
            } => self.writeReg(.COND, Flags.NEG),
            else => self.writeReg(.COND, Flags.POS),
        }
    }
};

pub fn init() Lzc {
    return Lzc{
        .memory = [_]u16{0} ** MEMORY_MAX,
        .reg = [_]u16{0} ** REG_MAX,
    };
}

fn signExtend(x: u16, bit_count: u16) u16 {
    if (((x >> @intCast(bit_count - 1)) & 1) != 0) {
        const ff: u16 = 0xFFFF;
        return x | (ff << @intCast(bit_count));
    }
    return x;
}

test "signExtend fn" {
    const signed = signExtend(2, 5);
    std.debug.print("{b}\n", .{signed});
    try std.testing.expect(signed == 5);
}
