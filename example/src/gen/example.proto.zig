const std = @import("std");
const gremlin = @import("gremlin");

// structs
const UserWire = struct {
    const NAME_WIRE: gremlin.ProtoWireNumber = 1;
    const ID_WIRE: gremlin.ProtoWireNumber = 2;
    const TAGS_WIRE: gremlin.ProtoWireNumber = 10;
};

pub const User = struct {
    // fields
    name: ?[]const u8 = null,
    id: u64 = 0,
    tags: ?[]const ?[]const u8 = null,

    pub fn calcProtobufSize(self: *const User) usize {
        var res: usize = 0;
        if (self.name) |v| { res += gremlin.sizes.sizeWireNumber(UserWire.NAME_WIRE) + gremlin.sizes.sizeUsize(v.len) + v.len; }
        if (self.id != 0) { res += gremlin.sizes.sizeWireNumber(UserWire.ID_WIRE) + gremlin.sizes.sizeU64(self.id); }
        if (self.tags) |arr| {
            for (arr) |maybe_v| {
                res += gremlin.sizes.sizeWireNumber(UserWire.TAGS_WIRE);
                if (maybe_v) |v| {
                    res += gremlin.sizes.sizeUsize(v.len) + v.len;
                } else {
                    res += gremlin.sizes.sizeUsize(0);
                }
            }
        }
        return res;
    }

    pub fn encode(self: *const User, allocator: std.mem.Allocator) gremlin.Error![]const u8 {
        const size = self.calcProtobufSize();
        if (size == 0) {
            return &[_]u8{};
        }
        const buf = try allocator.alloc(u8, self.calcProtobufSize());
        var writer = gremlin.Writer.init(buf);
        self.encodeTo(&writer);
        return buf;
    }


    pub fn encodeTo(self: *const User, target: *gremlin.Writer) void {
        if (self.name) |v| { target.appendBytes(UserWire.NAME_WIRE, v); }
        if (self.id != 0) { target.appendUint64(UserWire.ID_WIRE, self.id); }
        if (self.tags) |arr| {
            for (arr) |maybe_v| {
                if (maybe_v) |v| {
                    target.appendBytes(UserWire.TAGS_WIRE, v);
                } else {
                    target.appendBytesTag(UserWire.TAGS_WIRE, 0);
                }
            }
        }
    }
};

pub const UserReader = struct {
    allocator: std.mem.Allocator,
    buf: gremlin.Reader,
    _name: ?[]const u8 = null,
    _id: u64 = 0,
    _tags: ?std.ArrayList([]const u8) = null,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) gremlin.Error!UserReader {
        var buf = gremlin.Reader.init(src);
        var res = UserReader{.allocator = allocator, .buf = buf};
        if (buf.buf.len == 0) {
            return res;
        }
        var offset: usize = 0;
        while (buf.hasNext(offset, 0)) {
            const tag = try buf.readTagAt(offset);
            offset += tag.size;
            switch (tag.number) {
                UserWire.NAME_WIRE => {
                  const result = try buf.readBytes(offset);
                  offset += result.size;
                  res._name = result.value;
                },
                UserWire.ID_WIRE => {
                  const result = try buf.readUInt64(offset);
                  offset += result.size;
                  res._id = result.value;
                },
                UserWire.TAGS_WIRE => {
                    const result = try buf.readBytes(offset);
                    offset += result.size;
                    if (res._tags == null) {
                        res._tags = std.ArrayList([]const u8).init(allocator);
                    }
                    try res._tags.?.append(result.value);
                },
                else => {
                    offset = try buf.skipData(offset, tag.wire);
                }
            }
        }
        return res;
    }
    pub fn deinit(self: *const UserReader) void {
        if (self._tags) |arr| {
            arr.deinit();
        }
    }
    pub inline fn getName(self: *const UserReader) []const u8 { return self._name orelse &[_]u8{}; }
    pub inline fn getId(self: *const UserReader) u64 { return self._id; }
    pub fn getTags(self: *const UserReader) []const []const u8 {
        if (self._tags) |arr| {
            return arr.items;
        }
        return &[_][]u8{};
    }
};

