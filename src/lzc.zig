const Self = @This();

const MEMORY_MAX = 1 << 16;
const REG_MAX = 10;
const PC_START = 0x3000;

memory: [MEMORY_MAX]u16,
reg: [REG_MAX]u16,
reader: std.io.AnyReader,
writer: std.io.AnyWriter,

const Register = enum(u16) {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    /// program counter
    PC,
    COND,
    COUNT,
};

/// Conditional Flags
const Flags = enum(u16) {
    POS = 1 << 0,
    ZRO = 1 << 1,
    NEG = 1 << 2,
};

const Opcodes = enum(u16) {
    /// branch
    BR,
    /// add
    ADD,
    /// load
    LD,
    /// store
    ST,
    /// jump register
    JSR,
    /// bitwise and
    AND,
    /// load register
    LDR,
    /// store register
    STR,
    /// unused
    RTI,
    /// bitwise not
    NOT,
    /// load indirect
    LDI,
    /// store indirect
    STI,
    /// jump
    JMP,
    /// reserved (unused)
    RES,
    /// load effective address
    LEA,
    /// execute trap
    TRAP,
};

const TrapRoutine = enum(u16) {
    GETC = 0x20,
    OUT,
    PUTS,
    IN,
    PUTSP,
    HALT,
};

/// Memory mapped registers
const MemReg = enum(u16) {
    /// keyboard status
    KBSR = 0xFE00,
    /// keyboard data
    KBDR = 0xFE02,
};

pub fn init(reader: std.io.AnyReader, writer: std.io.AnyWriter) Self {
    return Self{
        .memory = [_]u16{0} ** MEMORY_MAX,
        .reg = [_]u16{0} ** REG_MAX,
        .reader = reader,
        .writer = writer,
    };
}

extern fn disable_input_buffering() c_int;
extern fn restore_input_buffering() void;
extern fn check_key() c_int;

fn readMem(self: *Self, address: u16) !u16 {
    if (address >= self.memory.len) {
        return error.OutOfBound;
    }

    if (address == @intFromEnum(MemReg.KBSR)) {
        if (check_key() != 0) {
            try self.writeMem(@intFromEnum(MemReg.KBSR), 1 << 15);
            try self.writeMem(@intFromEnum(MemReg.KBDR), blk: {
                // The original C code uses getchar().
                // From the getchar man page, if successful the routine
                // (getchar) will return an unsigned char converted
                // to an int. So reader().readInt is more suitable.
                // The use of .litte (as in little endian) solely because
                // it's more common then .big
                break :blk self.reader.readInt(u16, .little) catch {
                    return error.StdinError;
                };
            });
        } else {
            try self.writeMem(@intFromEnum(MemReg.KBSR), 0);
        }
    }
    return self.memory[address];
}

fn writeMem(self: *Self, address: u16, val: u16) !void {
    if (address >= self.memory.len) {
        return error.OutOfBound;
    }
    self.memory[address] = val;
}

fn writeReg(self: *Self, comptime T: type, kind: Register, val: T) void {
    switch (@typeInfo(T)) {
        .@"enum" => {
            self.reg[@intFromEnum(kind)] = @intFromEnum(val);
        },
        .int => {
            self.reg[@intFromEnum(kind)] = val;
        },
        else => unreachable,
    }
}

fn readReg(self: Self, kind: Register) u16 {
    return self.reg[@intFromEnum(kind)];
}

fn updateFlags(self: *Self, r: Register) void {
    if (self.readReg(r) == 0) {
        self.writeReg(Flags, .COND, .ZRO);
        return;
    }

    const shifted = self.reg[@intFromEnum(r)] >> 15;
    if (self.readReg(r) == shifted) {
        self.writeReg(Flags, .COND, .NEG);
    } else {
        self.writeReg(Flags, .COND, .POS);
    }

    // switch (self.readReg(r)) {
    //     0 => self.writeReg(Flags, .COND, .ZRO),
    //     blk: {
    //         const shifted = self.reg[@intFromEnum(r)] >> 15;
    //         break :blk shifted;
    //     } => self.writeReg(Flags, .COND, .NEG),
    //     else => self.writeReg(Flags, .COND, .POS),
    // }
}

fn readImageFile(self: *Self, file: std.fs.File) !void {
    const read2Bytes = try file.reader().readBytesNoEof(2);
    const origin = std.mem.readInt(u16, &read2Bytes, .little);

    var start = origin;
    while (true) : (start += 1) {
        const item = file.reader().readBytesNoEof(2) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        try self.writeMem(start, std.mem.readInt(u16, &item, .little));
    }
}

test "read file and swap16" {
    const file = try std.fs.cwd().openFile("hello.txt", .{});
    // h = 104 | 0x68
    // e = 101 | 0x65
    const read2Bytes = try file.reader().readBytesNoEof(2);
    try testing.expectEqual('h', read2Bytes[0]);
    try testing.expectEqualStrings("he", &read2Bytes);

    // 0x68 0x65 -> 0x6568
    const origin = std.mem.readInt(u16, &read2Bytes, .little);
    try testing.expectEqual(0x6568, origin);

    var buffer: [3]u16 = undefined;
    var start: usize = 0;
    while (true) : (start += 1) {
        const item = file.reader().readBytesNoEof(2) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        buffer[start] = std.mem.readInt(u16, &item, .little);
    }
    // [l ,l] -> [0x6c, 0x6c]([2]u8) -> 0x6c6c(u16.little-endian)
    try testing.expectEqual(0x6c6c, buffer[0]);
    // [0 ,`lf`(line feed)] -> [0x6f, 0xa]([2]u8) -> 0xa6f(u16.little-endian)
    try testing.expectEqual(0xa6f, buffer[1]);
}

pub fn run(self: *Self, image: std.fs.File) !void {
    const Op = Opcodes;
    var bw = io.bufferedWriter(self.writer);
    try bw.writer().print("\x1B[2J\x1B[H", .{});

    try self.readImageFile(image);

    // signal(SIGINT, handle_interrupt);
    // disable_input_buffering();

    self.writeReg(Flags, .COND, .ZRO);
    self.writeReg(u16, .PC, PC_START);

    var running = true;
    while (running) {
        const address = self.readReg(.PC) + 1;
        const instr = try self.readMem(address);
        const op: Op = @enumFromInt(instr >> 12);

        switch (op) {
            .ADD => {
                // DR: shift 9 to right according to encoding spec
                // then bitwise AND with 0x7 (8 in length)
                // because DR marked as 3 bits (8 in length)
                const r0 = enint((instr >> 9) & 0x7);
                // SR1
                const r1 = enint((instr >> 6) & 0x7);
                // Immediate mode flag: marked as 1 bit
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag != 0) {
                    const imm5 = signExtend(instr & 0x1F, 5);
                    self.writeReg(u16, r0, @addWithOverflow(self.readReg(r1), imm5)[0]);
                } else {
                    const r2 = enint(instr & 0x7);
                    self.writeReg(u16, r0, @addWithOverflow(self.readReg(r1), self.readReg(r2))[0]);
                }
                self.updateFlags(r0);
            },
            .AND => {
                const r0 = enint((instr >> 9) & 0x07);
                const r1 = enint((instr >> 6) & 0x07);
                const imm_flag: u16 = (instr >> 5) & 0x01;

                if (imm_flag != 0) {
                    const imm5 = signExtend(instr & 0x1F, 5);
                    self.writeReg(u16, r0, self.readReg(r1) & imm5);
                } else {
                    const r2 = enint(instr & 0x7);
                    self.writeReg(u16, r0, self.readReg(r1) & self.readReg(r2));
                }
                self.updateFlags(r0);
            },
            .NOT => {
                const r0 = enint((instr >> 9) & 0x07);
                const r1 = enint((instr >> 6) & 0x07);
                self.writeReg(u16, r0, ~self.readReg(r1));
                self.updateFlags(r0);
            },
            .BR => {
                const pc_offset = signExtend(instr & 0x1FF, 9);
                const cond_flag = (instr >> 9) & 0x07;
                if ((cond_flag & self.readReg(.COND)) != 0) {
                    self.writeReg(u16, .PC, self.readReg(.PC) + pc_offset);
                }
            },
            .JMP => {
                // Also handles RET. RET is listed as a separate instruction
                // in the specification, since it is a different
                // keyword in assembly. However, it is actually
                // a special case of JMP. RET happens whenever R1 is 7.
                const r1 = enint((instr >> 6) & 0x07);
                self.writeReg(u16, .PC, self.readReg(r1));
            },
            .JSR => {
                self.writeReg(u16, .R7, self.readReg(.PC));
                if (((instr >> 11) & 1) != 0) {
                    const long_pc_offset = signExtend(instr & 0x7FF, 11);
                    self.writeReg(u16, .PC, self.readReg(.PC) + long_pc_offset);
                } else {
                    const r1 = enint((instr >> 6) & 0x7);
                    self.writeReg(u16, .PC, self.readReg(r1)); // JSRR
                }
            },
            .LD => {
                const r0 = enint((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);
                const val = try self.readMem(@addWithOverflow(self.readReg(.PC), pc_offset)[0]);
                self.writeReg(u16, r0, val);
                self.updateFlags(r0);
            },
            .LDI => {
                const r0 = enint((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);
                const val = try self.readMem(try self.readMem(@addWithOverflow(self.readReg(.PC), pc_offset)[0]));
                self.writeReg(u16, r0, val);
                self.updateFlags(r0);
            },
            .LDR => {
                const r0 = enint((instr >> 9) & 0x7);
                const r1 = enint((instr >> 6) & 0x7);
                const offset = signExtend(instr & 0x3F, 6);
                const val = try self.readMem(self.readReg(r1) + offset);
                self.writeReg(u16, r0, val);
                self.updateFlags(r0);
            },
            .LEA => {
                const r0 = enint((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);
                self.writeReg(u16, r0, @addWithOverflow(self.readReg(.PC), pc_offset)[0]);
                self.updateFlags(r0);
            },
            .ST => {
                const r0 = enint((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);
                try self.writeMem(self.readReg(.PC) + pc_offset, self.readReg(r0));
            },
            .STI => {
                const r0 = enint((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);
                try self.writeMem(try self.readMem(self.readReg(.PC) + pc_offset), self.readReg(r0));
            },
            .STR => {
                const r0 = enint((instr >> 9) & 0x7);
                const r1 = enint((instr >> 6) & 0x7);
                const offset = signExtend(instr & 0x3F, 6);
                try self.writeMem(self.readReg(r1) + offset, self.readReg(r0));
            },
            .TRAP => {
                self.writeReg(u16, .R7, self.readReg(.PC));
                const routine: TrapRoutine = @enumFromInt(instr & 0xFF);

                switch (routine) {
                    .GETC => {
                        const c = try self.reader.readInt(u16, .little);
                        self.writeReg(u16, .R0, c);
                        self.updateFlags(.R0);
                    },
                    .OUT => {
                        const c: u8 = @truncate(self.readReg(.R0));
                        try bw.writer().writeInt(u8, c, .little);
                        try bw.flush();
                    },
                    .PUTS => {
                        var start = self.readReg(.R0);
                        const c = try self.readMem(start);
                        while (c != 0) : (start += 1) {
                            try bw.writer().writeByte(@as(u8, @truncate(c)));
                        }
                        try bw.flush();
                    },
                    .IN => {
                        try bw.writer().print("Enter a character: ", .{});

                        var br = io.bufferedReader(self.reader);
                        const c = try br.reader().readByte();
                        try bw.writer().writeByte(c);
                        try bw.flush();

                        self.writeReg(u16, .R0, @as(u16, c));
                        self.updateFlags(.R0);
                    },
                    .PUTSP => {
                        // TODO: Understand more about this
                        var start = self.readReg(.R0);
                        const c = try self.readMem(start);
                        while (c != 0) : (start += 1) {
                            try bw.writer().writeInt(u8, @truncate(c), .big);
                        }
                        try bw.flush();
                    },
                    .HALT => {
                        try bw.writer().writeAll("HALT");
                        try bw.flush();
                        running = false;
                    },
                }
            },
            .RTI, .RES => {},
        }

        try bw.flush();
    }

    // restore_input_buffering();
}

test "initiation" {
    const stdin = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin);
    const reader = br.reader();

    const stdout = std.io.getStdOut().writer();

    var lzc = init(reader.any(), stdout.any());

    lzc.writeReg(Flags, .COND, .ZRO);
    try std.testing.expectEqual(@intFromEnum(Flags.ZRO), lzc.readReg(.COND));

    lzc.writeReg(u16, .COND, 0x3000);
    try std.testing.expectEqual(0x3000, lzc.readReg(.COND));

    try testing.expectEqual(0x22, @intFromEnum(TrapRoutine.PUTS));
}

fn signExtend(x: u16, comptime bit_count: usize) u16 {
    if (((x >> (bit_count - 1)) & 1) != 0) {
        const ff: u16 = 0xFFFF;
        return x | (ff << bit_count);
    }
    return x;
}

fn enint(val: anytype) Register {
    return @enumFromInt(val);
}

test "enint" {
    try testing.expectEqual(Register.R1, enint(1));
}

test "signExtend fn" {
    const signed = signExtend(2, 5);
    try std.testing.expect(signed == 2);
}

const std = @import("std");
const io = std.io;
const testing = std.testing;
