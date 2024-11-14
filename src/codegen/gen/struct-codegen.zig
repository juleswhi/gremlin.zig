//! Provides functionality for generating Zig code from Protocol Buffer struct definitions.
//! This module handles the generation of wire format enums, writer structs, and reader structs,
//! including all necessary fields, methods, and nested types.

const std = @import("std");
const FileOutput = @import("output.zig").FileOutput;
const ZigStruct = @import("struct.zig").ZigStruct;
const ZigEnum = @import("enum.zig").ZigEnum;

/// CodeGenerator handles the generation of Zig source code for Protocol Buffer messages.
/// It manages the creation of wire format enums, writer structs, and reader structs,
/// along with all their associated methods and fields.
pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    target: *const ZigStruct, // Target struct to generate code for
    out_file: *FileOutput, // Output file for generated code

    /// Initialize a new code generator for a target struct.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string operations
    ///   - target: Target struct to generate code for
    ///   - out_file: Output file handler
    pub fn init(allocator: std.mem.Allocator, target: *const ZigStruct, out_file: *FileOutput) CodeGenerator {
        return .{
            .allocator = allocator,
            .target = target,
            .out_file = out_file,
        };
    }

    /// Generate all code components for the struct.
    /// This includes wire format enum, writer struct, and reader struct.
    pub fn generate(self: *const CodeGenerator) !void {
        try self.generateWireEnum();
        try self.generateWriter();
        try self.generateReader();
    }

    /// Generate the wire format enum for field identifiers.
    /// Only generated if the struct has fields.
    fn generateWireEnum(self: *const CodeGenerator) !void {
        if (self.target.fields.items.len == 0) return;

        try self.out_file.writePrefix();
        try self.out_file.continueString("const ");
        try self.out_file.continueString(self.target.wire_enum_name);
        try self.out_file.continueString(" = struct {\n");

        self.out_file.depth += 1;
        for (self.target.fields.items) |field| {
            const wire_const = try field.createWireConst();
            defer self.allocator.free(wire_const);
            try self.out_file.writeString(wire_const);
        }
        self.out_file.depth -= 1;

        try self.out_file.writeString("};\n");
    }

    /// Generate the writer struct that handles serialization.
    /// Includes nested types, fields, and serialization methods.
    fn generateWriter(self: *const CodeGenerator) !void {
        try self.out_file.writePrefix();
        try self.out_file.continueString("pub const ");
        try self.out_file.continueString(self.target.writer_name);
        try self.out_file.continueString(" = struct {\n");

        self.out_file.depth += 1;

        try self.generateNestedTypes();
        try self.generateFields();
        try self.generateSizeFunction();
        try self.generateSerializeFunction();

        self.out_file.depth -= 1;
        try self.out_file.writeString("};\n");
    }

    /// Generate nested type definitions (enums and structs).
    fn generateNestedTypes(self: *const CodeGenerator) !void {
        if (self.target.enums.items.len > 0) {
            try self.out_file.writeComment("nested enums");
            for (self.target.enums.items) |*enum_item| {
                const enum_code = try enum_item.createEnumDef(self.allocator);
                defer self.allocator.free(enum_code);
                try self.out_file.writeString(enum_code);
            }
        }

        if (self.target.structs.items.len > 0) {
            try self.out_file.writeComment("nested structs");
            for (self.target.structs.items) |*nested| {
                try nested.code(self.out_file);
            }
        }
    }

    /// Generate field definitions for the writer struct.
    fn generateFields(self: *const CodeGenerator) !void {
        if (self.target.fields.items.len > 0) {
            try self.out_file.writeComment("fields");
            for (self.target.fields.items) |field| {
                const writer_struct = try field.createWriterStructField();
                defer self.allocator.free(writer_struct);
                try self.out_file.writeString(writer_struct);
            }
        }
    }

    /// Generate the reader struct for deserialization.
    /// Includes fields, initialization, cleanup, and accessor methods.
    fn generateReader(self: *const CodeGenerator) !void {
        try self.out_file.writePrefix();
        try self.out_file.continueString("pub const ");
        try self.out_file.continueString(self.target.reader_name);
        try self.out_file.continueString(" = struct {\n");

        self.out_file.depth += 1;

        // Check if we need allocator for any fields
        var needs_allocator = false;
        for (self.target.fields.items) |field| {
            if (field.readerNeedsAllocator()) {
                needs_allocator = true;
                break;
            }
        }

        try self.generateReaderFields(needs_allocator);
        try self.generateReaderInit(needs_allocator);
        try self.generateReaderDeinit(needs_allocator);
        try self.generateReaderGetters();

        self.out_file.depth -= 1;
        try self.out_file.writeString("};\n");
    }

    /// Generate initialization code for the reader.
    fn generateReaderInit(self: *const CodeGenerator, needs_allocator: bool) !void {
        if (self.target.fields.items.len == 0) {
            try self.generateEmptyReaderInit();
            return;
        }

        try self.generateFullReaderInit(needs_allocator);
    }

    /// Generate initialization for empty reader (no fields).
    fn generateEmptyReaderInit(self: *const CodeGenerator) !void {
        const formatted = try std.fmt.allocPrint(self.allocator,
            \\pub fn init(_: std.mem.Allocator, _: []const u8) gremlin.Error!{s} {{
            \\    return {s}{{}};
            \\}}
        , .{ self.target.reader_name, self.target.reader_name });
        defer self.allocator.free(formatted);
        try self.out_file.writeString(formatted);
    }

    /// Generate initialization for reader with fields.
    fn generateFullReaderInit(self: *const CodeGenerator, needs_allocator: bool) !void {
        if (needs_allocator) {
            const init_sig = try std.fmt.allocPrint(
                self.allocator,
                "pub fn init(allocator: std.mem.Allocator, src: []const u8) gremlin.Error!{s} {{",
                .{self.target.reader_name},
            );
            defer self.allocator.free(init_sig);
            try self.out_file.writeString(init_sig);
        } else {
            const init_sig = try std.fmt.allocPrint(
                self.allocator,
                "pub fn init(_: std.mem.Allocator, src: []const u8) gremlin.Error!{s} {{",
                .{self.target.reader_name},
            );
            defer self.allocator.free(init_sig);
            try self.out_file.writeString(init_sig);
        }
        try self.out_file.writeString("    var buf = gremlin.Reader.init(src);");

        if (needs_allocator) {
            const init_res = try std.fmt.allocPrint(
                self.allocator,
                "    var res = {s}{{.allocator = allocator, .buf = buf}};",
                .{self.target.reader_name},
            );
            defer self.allocator.free(init_res);
            try self.out_file.writeString(init_res);
        } else {
            const init_res = try std.fmt.allocPrint(
                self.allocator,
                "    var res = {s}{{}};",
                .{self.target.reader_name},
            );
            defer self.allocator.free(init_res);
            try self.out_file.writeString(init_res);
        }

        try self.out_file.writeString(
            \\    if (buf.buf.len == 0) {
            \\        return res;
            \\    }
            \\    var offset: usize = 0;
            \\    while (buf.hasNext(offset, 0)) {
            \\        const tag = try buf.readTagAt(offset);
            \\        offset += tag.size;
            \\        switch (tag.number) {
        );

        self.out_file.depth += 3;
        for (self.target.fields.items) |field| {
            const reader_init = try field.createReaderCase();
            defer self.allocator.free(reader_init);
            try self.out_file.writeString(reader_init);
        }
        self.out_file.depth -= 3;

        try self.out_file.writeString(
            \\            else => {
            \\                offset = try buf.skipData(offset, tag.wire);
            \\            }
            \\        }
            \\    }
            \\    return res;
            \\}
        );
    }

    /// Generate cleanup code for the reader.
    fn generateReaderDeinit(self: *const CodeGenerator, needs_allocator: bool) !void {
        if (!needs_allocator) {
            const fmt = try std.fmt.allocPrint(self.allocator, "pub fn deinit(_: *const {s}) void {{ }}\n", .{self.target.reader_name});
            defer self.allocator.free(fmt);
            try self.out_file.writeString(fmt);
            return;
        }

        const fmt = try std.fmt.allocPrint(self.allocator, "pub fn deinit(self: *const {s}) void {{", .{self.target.reader_name});
        defer self.allocator.free(fmt);
        try self.out_file.writeString(fmt);
        self.out_file.depth += 1;

        // Generate cleanup for each field that needs it
        for (self.target.fields.items) |field| {
            const reader_deinit = try field.createReaderDeinit();
            defer self.allocator.free(reader_deinit);
            if (reader_deinit.len > 0) {
                try self.out_file.writeString(reader_deinit);
            }
        }

        self.out_file.depth -= 1;
        try self.out_file.writeString("}");
    }

    /// Generate field definitions for the reader struct.
    fn generateReaderFields(self: *const CodeGenerator, needs_allocator: bool) !void {
        // Add allocator and buffer fields if needed
        if (needs_allocator) {
            try self.out_file.writeString("allocator: std.mem.Allocator,");
            try self.out_file.writeString("buf: gremlin.Reader,");
        }

        // Generate field definitions
        for (self.target.fields.items) |field| {
            const reader_struct = try field.createReaderStructField();
            defer self.allocator.free(reader_struct);
            try self.out_file.writeString(reader_struct);
        }
        try self.out_file.linebreak();
    }

    /// Generate getter methods for reader fields.
    fn generateReaderGetters(self: *const CodeGenerator) !void {
        for (self.target.fields.items) |field| {
            const getter = try field.createReaderMethod();
            defer self.allocator.free(getter);
            try self.out_file.writeString(getter);
        }
    }

    /// Generate the size calculation function for serialization.
    /// This function computes the total size needed to serialize the struct.
    fn generateSizeFunction(self: *const CodeGenerator) !void {
        try self.out_file.linebreak();

        // Handle empty structs
        if (self.target.fields.items.len == 0) {
            const fmt = try std.fmt.allocPrint(self.allocator,
                \\pub fn calcProtobufSize(_: *const {s}) usize {{ return 0; }}
                \\
            , .{self.target.writer_name});
            defer self.allocator.free(fmt);

            try self.out_file.writeString(fmt);
            return;
        }

        // Generate size calculation for structs with fields
        const fmt = try std.fmt.allocPrint(self.allocator,
            \\pub fn calcProtobufSize(self: *const {s}) usize {{
            \\    var res: usize = 0;
        , .{self.target.writer_name});
        defer self.allocator.free(fmt);

        try self.out_file.writeString(fmt);

        // Add size calculations for each field
        self.out_file.depth += 1;
        for (self.target.fields.items) |field| {
            const size_check = try field.createSizeCheck();
            defer self.allocator.free(size_check);
            try self.out_file.writeString(size_check);
        }
        try self.out_file.writeString("return res;");
        self.out_file.depth -= 1;

        try self.out_file.writeString("}");
    }

    /// Generate the serialization functions.
    /// This includes both the main encode function and the encodeTo helper.
    fn generateSerializeFunction(self: *const CodeGenerator) !void {
        try self.out_file.linebreak();

        // Generate main encode function that allocates buffer
        const encoder = try std.fmt.allocPrint(
            self.allocator,
            \\pub fn encode(self: *const {s}, allocator: std.mem.Allocator) gremlin.Error![]const u8 {{
            \\    const size = self.calcProtobufSize();
            \\    if (size == 0) {{
            \\        return &[_]u8{{}};
            \\    }}
            \\    const buf = try allocator.alloc(u8, self.calcProtobufSize());
            \\    var writer = gremlin.Writer.init(buf);
            \\    self.encodeTo(&writer);
            \\    return buf;
            \\}}
        ,
            .{self.target.writer_name},
        );
        defer self.allocator.free(encoder);

        try self.out_file.writeString(encoder);
        try self.out_file.linebreak();

        try self.out_file.linebreak();

        // Handle empty structs
        if (self.target.fields.items.len == 0) {
            const empty_encode = try std.fmt.allocPrint(
                self.allocator,
                \\pub fn encodeTo(_: *const {s}, _: *gremlin.Writer) void {{}}
                \\
                ,.{self.target.writer_name});
            defer self.allocator.free(empty_encode);

            try self.out_file.writeString(empty_encode);
            return;
        }

        // Generate encodeTo function for writing to provided buffer
        const encode_to = try std.fmt.allocPrint(
            self.allocator,
            \\pub fn encodeTo(self: *const {s}, target: *gremlin.Writer) void {{
                ,.{self.target.writer_name});
        defer self.allocator.free(encode_to);
        try self.out_file.writeString(encode_to);

        // Generate encoding for each field
        self.out_file.depth += 1;
        for (self.target.fields.items) |field| {
            const writer_code = try field.createWriter();
            defer self.allocator.free(writer_code);
            try self.out_file.writeString(writer_code);
        }
        self.out_file.depth -= 1;
        try self.out_file.writeString("}");
    }
};
