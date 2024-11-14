//! This module handles the generation of Zig code for Protocol Buffer map fields.
//! Protocol Buffers represent maps as repeated key-value pairs in the wire format.
//! In Zig, maps are implemented using either StringHashMap or AutoHashMap depending
//! on the key type.

//               .'\   /`.
//             .'.-.`-'.-.`.
//        ..._:   .-. .-.   :_...
//      .'    '-.(o ) (o ).-'    `.
//     :  _    _ _`~(_)~`_ _    _  :
//    :  /:   ' .-=_   _=-. `   ;\  :
//    :   :|-.._  '     `  _..-|:   :
//     :   `:| |`:-:-.-:-:'| |:'   :
//      `.   `.| | | | | | |.'   .'
//        `.   `-:_| | |_:-'   .'
//          `-._   ````    _.-'
//              ``-------''
//
// Created by ab, 12.11.2024

const std = @import("std");
const naming = @import("naming.zig");
const Option =  @import("../../../parser/main.zig").Option;
const FieldType =  @import("../../../parser/main.zig").FieldType;
const MessageMapField =  @import("../../../parser/main.zig").fields.MessageMapField;

// Import scalar type utilities
const scalarSize = @import("scalar.zig").scalarSize;
const scalarZigType = @import("scalar.zig").scalarZigType;
const scalarWriter = @import("scalar.zig").scalarWriter;
const scalarReader = @import("scalar.zig").scalarReader;
const scalarDefaultValue = @import("scalar.zig").scalarDefaultValue;

/// Represents a Protocol Buffer map field in Zig.
/// Maps are encoded as repeated messages where each message contains a key and value field.
pub const ZigMapField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Map field properties
    key_type: []const u8, // Type of the map key (must be scalar type or string)
    value_type: FieldType, // Type of the map value (can be any protobuf type)
    field_index: i32, // Field number in protocol

    // Generated names for field access
    writer_field_name: []const u8, // Name in writer struct
    reader_field_name: []const u8, // Internal name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name

    // Resolved type information
    resolved_enum_type: ?[]const u8 = null, // For enum value types
    resolved_writer_message_type: ?[]const u8 = null, // For message value types (writer)
    resolved_reader_message_type: ?[]const u8 = null, // For message value types (reader)

    /// Initialize a new ZigMapField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field: *const MessageMapField,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigMapField {
        // Generate field names
        const name = try naming.structFieldName(allocator, field.f_name, names);

        // Generate wire format constant names
        const wirePostfixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field.f_name, "Wire" });
        defer allocator.free(wirePostfixed);
        const wireConstName = try naming.constName(allocator, wirePostfixed, names);
        const wireName = try std.mem.concat(allocator, u8, &[_][]const u8{
            wire_prefix,
            ".",
            wireConstName,
        });

        // Generate reader method name
        const reader_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "get_", field.f_name });
        defer allocator.free(reader_prefixed);
        const readerMethodName = try naming.structMethodName(allocator, reader_prefixed, names);

        return ZigMapField{
            .allocator = allocator,
            .key_type = field.key_type,
            .value_type = field.value_type,
            .field_index = field.index,
            .writer_field_name = name,
            .reader_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name }),
            .reader_method_name = readerMethodName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigMapField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_field_name);
        self.allocator.free(self.reader_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);

        if (self.resolved_enum_type) |e| {
            self.allocator.free(e);
        }
        if (self.resolved_reader_message_type) |m| {
            self.allocator.free(m);
        }
        if (self.resolved_writer_message_type) |m| {
            self.allocator.free(m);
        }
    }

    // Key-related helper functions

    /// Get the Zig type for the map key
    fn keyType(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return "[]const u8";
        } else {
            return scalarZigType(self.key_type);
        }
    }

    /// Generate code for calculating key size
    fn keySize(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8,
                \\const key = entry.key_ptr.*;
                \\        const key_size = gremlin.sizes.sizeUsize(key.len) + key.len;
            );
        } else {
            return std.mem.concat(self.allocator, u8, &[_][]const u8{
                "const key = entry.key_ptr.*;\n",
                "        const key_size = ",
                scalarSize(self.key_type),
                "(key);",
            });
        }
    }

    /// Generate code for writing key to wire format
    fn keyWrite(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8, "target.appendBytes(1, key);");
        } else {
            return std.mem.concat(self.allocator, u8, &[_][]const u8{
                "target.",
                scalarWriter(self.key_type),
                "(1, key);",
            });
        }
    }

    /// Generate code for reading key from wire format
    fn keyRead(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8,
                \\const sized_key = try entry_buf.readBytes(offset);
                \\                      key = sized_key.value;
                \\                      offset += sized_key.size;
            );
        } else {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_key = try entry_buf.{s}(offset);
                \\                      key = sized_key.value;
                \\                      offset += sized_key.size;
            , .{scalarReader(self.key_type)});
        }
    }

    // Value-related helper functions

    /// Get the Zig type for map value (writer side)
    fn valueType(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "[]const u8");
        } else if (self.value_type.is_scalar) {
            return try self.allocator.dupe(u8, scalarZigType(self.value_type.src));
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, self.resolved_enum_type.?);
        } else {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                self.resolved_writer_message_type.?,
            });
        }
    }

    /// Get the Zig type for map value (reader side)
    fn valueReaderType(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "[]const u8");
        } else if (self.value_type.is_scalar) {
            return try self.allocator.dupe(u8, scalarZigType(self.value_type.src));
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, self.resolved_enum_type.?);
        } else {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                self.resolved_reader_message_type.?,
            });
        }
    }

    /// Generate code for reading value from wire format
    fn valueRead(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return self.allocator.dupe(u8,
                \\const sized_value = try entry_buf.readBytes(offset);
                \\                      value = sized_value.value;
                \\                      offset += sized_value.size;
            );
        } else if (self.value_type.is_scalar) {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_value = try entry_buf.{s}(offset);
                \\                      value = sized_value.value;
                \\                      offset += sized_value.size;
            , .{scalarReader(self.value_type.src)});
        } else if (self.value_type.isEnum()) {
            return self.allocator.dupe(u8,
                \\const sized_value = try entry_buf.readInt32(offset);
                \\                      value = @enumFromInt(sized_value.value);
                \\                      offset += sized_value.size;
            );
        } else {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_value = try entry_buf.readBytes(offset);
                \\                      value = try {s}.init(allocator, sized_value.value);
                \\                      offset += sized_value.size;
            , .{self.resolved_reader_message_type.?});
        }
    }

    /// Generate code for calculating value size
    fn valueSize(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr.*;
                \\        const value_size = gremlin.sizes.sizeUsize(value.len) + value.len;
            );
        } else if (self.value_type.is_scalar) {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                "const value = entry.value_ptr.*;\n        const value_size = ",
                scalarSize(self.value_type.src),
                "(value);",
            });
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr.*;
                \\        const value_size = gremlin.sizes.sizeI32(@intFromEnum(value));
            );
        } else {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr;
                \\        const v_size = value.calcProtobufSize();
                \\        const value_size: usize = gremlin.sizes.sizeUsize(v_size) + v_size;
            );
        }
    }

    /// Generate code for writing value to wire format
    fn valueWrite(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "target.appendBytes(2, value);");
        } else if (self.value_type.is_scalar) {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                "target.",
                scalarWriter(self.value_type.src),
                "(2, value);",
            });
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, "target.appendInt32(2, @intFromEnum(value));");
        } else {
            return try self.allocator.dupe(u8,
                \\target.appendBytesTag(2, v_size);
                \\        value.encodeTo(target);
            );
        }
    }

    /// Generate code for value variable declaration
    fn valueReaderVar(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "var value: []const u8 = undefined;");
        } else if (self.value_type.is_scalar) {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = {s};", .{ scalarZigType(self.value_type.src), scalarDefaultValue(self.value_type.src) });
        } else if (self.value_type.isEnum()) {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = @enumFromInt(0);", .{self.resolved_enum_type.?});
        } else {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = undefined;", .{self.resolved_reader_message_type.?});
        }
    }

    // Type resolution methods

    /// Set the resolved enum type name after type resolution phase
    pub fn resolveEnumValue(self: *ZigMapField, resolved_enum_type: []const u8) !void {
        self.resolved_enum_type = try self.allocator.dupe(u8, resolved_enum_type);
    }

    /// Set the resolved message type names after type resolution phase
    pub fn resoveMessageValue(self: *ZigMapField, resolved_writer_message_type: []const u8, resolved_reader_message_type: []const u8) !void {
        self.resolved_writer_message_type = try self.allocator.dupe(u8, resolved_writer_message_type);
        self.resolved_reader_message_type = try self.allocator.dupe(u8, resolved_reader_message_type);
    }

    // Code generation methods for field definitions and operations

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.field_index });
    }

    /// Generate writer struct field declaration.
    /// Creates either a StringHashMap or AutoHashMap based on key type.
    pub fn createWriterStructField(self: *const ZigMapField) ![]const u8 {
        const is_str_key = std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes");
        const value_type = try self.valueType();
        defer self.allocator.free(value_type);

        if (is_str_key) {
            return std.fmt.allocPrint(self.allocator, "{s}: ?*std.StringHashMap({s}) = null,", .{ self.writer_field_name, value_type });
        } else {
            const key_type = try self.keyType();
            return std.fmt.allocPrint(self.allocator, "{s}: ?*std.AutoHashMap({s}, {s}) = null,", .{ self.writer_field_name, key_type, value_type });
        }
    }

    /// Generate size calculation code for serialization.
    /// Maps are encoded as repeated messages, where each message contains a key-value pair.
    pub fn createSizeCheck(self: *const ZigMapField) ![]const u8 {
        const key_size = try self.keySize();
        const value_size = try self.valueSize();
        defer self.allocator.free(key_size);
        defer self.allocator.free(value_size);

        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    var it = v.iterator();
            \\    const entry_wire = gremlin.sizes.sizeWireNumber({s});
            \\    while (it.next()) |entry| {{
            \\        {s}
            \\        {s}
            \\        const entry_size = key_size + value_size + gremlin.sizes.sizeWireNumber(1) + gremlin.sizes.sizeWireNumber(2);
            \\        res += entry_wire + gremlin.sizes.sizeUsize(entry_size) + entry_size;
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name, key_size, value_size });
    }

    /// Generate serialization code for the map field.
    /// Each key-value pair is written as a separate message with fields 1 (key) and 2 (value).
    pub fn createWriter(self: *const ZigMapField) ![]const u8 {
        const key_writer = try self.keyWrite();
        const value_writer = try self.valueWrite();
        const key_size = try self.keySize();
        const value_size = try self.valueSize();
        defer self.allocator.free(key_writer);
        defer self.allocator.free(value_writer);
        defer self.allocator.free(key_size);
        defer self.allocator.free(value_size);

        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    var it = v.iterator();
            \\    while (it.next()) |entry| {{
            \\        {s}
            \\        {s}
            \\        const entry_size = key_size + value_size + gremlin.sizes.sizeWireNumber(1) + gremlin.sizes.sizeWireNumber(2);
            \\        target.appendBytesTag({s}, entry_size);
            \\        {s}
            \\        {s}
            \\    }}
            \\}}
        , .{ self.writer_field_name, key_size, value_size, self.wire_const_full_name, key_writer, value_writer });
    }

    /// Generate reader struct field declaration.
    /// The reader temporarily stores serialized key-value pairs as byte arrays.
    pub fn createReaderStructField(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?std.ArrayList([]const u8) = null,", .{self.reader_field_name});
    }

    /// Generate deserialization case statement.
    /// Collects serialized key-value pair messages for later processing.
    pub fn createReaderCase(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\    const result = try buf.readBytes(offset);
            \\    offset += result.size;
            \\    if (res.{s} == null) {{
            \\        res.{s} = std.ArrayList([]const u8).init(allocator);
            \\    }}
            \\    try res.{s}.?.append(result.value);
            \\}},
        , .{ self.wire_const_full_name, self.reader_field_name, self.reader_field_name, self.reader_field_name });
    }

    /// Generate getter method that constructs a map from collected key-value pairs.
    /// This method deserializes each pair and builds either a StringHashMap or AutoHashMap.
    pub fn createReaderMethod(self: *const ZigMapField) ![]const u8 {
        const is_str_key = std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes");
        const key_type = try self.keyType();
        const value_type = try self.valueReaderType();
        const key_read = try self.keyRead();
        const value_reader_var = try self.valueReaderVar();
        const value_read = try self.valueRead();
        defer self.allocator.free(value_type);
        defer self.allocator.free(key_read);
        defer self.allocator.free(value_reader_var);
        defer self.allocator.free(value_read);

        var return_type: []const u8 = undefined;
        defer self.allocator.free(return_type);

        if (is_str_key) {
            return_type = try std.fmt.allocPrint(self.allocator, "std.StringHashMap({s})", .{value_type});
        } else {
            return_type = try std.fmt.allocPrint(self.allocator, "std.AutoHashMap({s}, {s})", .{ key_type, value_type });
        }

        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}, allocator: std.mem.Allocator) gremlin.Error!?{s} {{
            \\    if (self.{s}) |bufs| {{
            \\        var result = {s}.init(allocator);
            \\        for (bufs.items) |buf| {{
            \\            const entry_buf = gremlin.Reader.init(buf);
            \\            var offset: usize = 0;
            \\
            \\            var key: {s} = undefined;
            \\            var has_key = false;
            \\            {s}
            \\            var has_value = false;
            \\
            \\            while (entry_buf.hasNext(offset, 0)) {{
            \\                const tag = try entry_buf.readTagAt(offset);
            \\                offset += tag.size;
            \\                switch (tag.number) {{
            \\                  1 => {{
            \\                      // read map key
            \\                      {s}
            \\                      has_key = true;
            \\                  }},
            \\                  2 => {{
            \\                      // read map value
            \\                      {s}
            \\                      has_value = true;
            \\                  }},
            \\                  else => {{
            \\                      offset = try entry_buf.skipData(offset, tag.wire);
            \\                  }}
            \\                }}
            \\            }}
            \\            if (has_key and has_value) {{
            \\                try result.put(key, value);
            \\            }}
            \\        }}
            \\        return result;
            \\    }}
            \\    return null;
            \\}}
        , .{
            self.reader_method_name,
            self.reader_struct_name,
            return_type,
            self.reader_field_name,
            return_type,
            key_type,
            value_reader_var,
            key_read,
            value_read,
        });
    }

    /// Indicates whether the reader needs an allocator (always true for maps)
    pub fn readerNeedsAllocator(_: *const ZigMapField) bool {
        return true;
    }

    /// Generate cleanup code for reader's temporary storage
    pub fn createReaderDeinit(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    arr.deinit();
            \\}}
        , .{self.reader_field_name});
    }
};
