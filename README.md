# gremlin

A zero-dependency Protocol Buffers implementation in pure Zig (no protoc required)

## Installation & Setup

Single command setup:
```bash
zig fetch --save https://github.com/octopus-foundation/gremlin.zig/archive/refs/tags/v0.0.0.tar.gz
```

This command will:
1. Download gremlin
2. Add it to your `build.zig.zon`
3. Generate the correct dependency hash

In your `build.zig`:
```zig
const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the parser dependency
    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    }).module("gremlin");

    // Generate Zig code from .proto files
    // This will process all .proto files in the proto/ directory
    // and output generated Zig code to src/gen/
    const protobuf = ProtoGenStep.create(
        b,
        .{
            .proto_sources = b.path("proto"),    // Directory containing .proto files
            .target = b.path("src/gen"),         // Output directory for generated Zig code
        },
    );

    // Create binary
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the parser module
    exe.root_module.addImport("gremlin", gremlin_dep);
    exe.step.dependOn(&protobuf.step);

    b.installArtifact(exe);
}
```

## Features

- Zero dependencies
- Pure Zig implementation (no protoc required)
- Compatible with Protocol Buffers version 2 and 3
- Simple integration with Zig build system
- Single! allocation for serialization (including complex recursive messages)
- Lazy parsing - parses only required complex fields
- Tested with Zig 0.14.0-dev

## Generated code

See the complete working example in the [`example`](./example) folder.

Given a protobuf definition:
```protobuf
syntax = "proto3";

message User {
  string name = 1;
  uint64 id   = 2;
  repeated string tags = 10;
}
```

Gremlin will generate equivalent Zig code:
```zig
const std = @import("std");
const gremlin = @import("gremlin");

// Wire numbers for fields
const UserWire = struct {
    const NAME_WIRE: gremlin.ProtoWireNumber = 1;
    const ID_WIRE: gremlin.ProtoWireNumber = 2;
    const TAGS_WIRE: gremlin.ProtoWireNumber = 10;
};

// Message struct
pub const User = struct {
    name: ?[]const u8 = null,
    id: u64 = 0,
    tags: ?[]const ?[]const u8 = null,
    
    // Calculate size for allocation
    pub fn calcProtobufSize(self: *const User) usize { ... }
    
    // Encode to new buffer
    pub fn encode(self: *const User, allocator: std.mem.Allocator) gremlin.Error![]const u8 { ... }
    
    // Encode to existing buffer
    pub fn encodeTo(self: *const User, target: *gremlin.Writer) void { ... }
};

// Reader for lazy parsing
pub const UserReader = struct {
    allocator: std.mem.Allocator,
    buf: gremlin.Reader,
    _name: ?[]const u8 = null, 
    _id: u64 = 0,
    _tags: ?std.ArrayList([]const u8) = null,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) gremlin.Error!UserReader { ... }
    pub fn deinit(self: *const UserReader) void { ... }
    
    // Accessor methods
    pub inline fn getName(self: *const UserReader) []const u8 { ... }
    pub inline fn getId(self: *const UserReader) u64 { ... }
    pub fn getTags(self: *const UserReader) []const []const u8 { ... }
};
```