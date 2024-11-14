//! Provides buffered file output functionality for generating Zig source code files.
//! This module handles proper formatting of generated code including indentation,
//! comments, and multi-line strings while maintaining efficient I/O operations.

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
// Created by ab, 04.11.2024

const std = @import("std");
const paths = @import("paths.zig");
const naming = @import("fields/naming.zig");

/// Configuration constants for output formatting
const Config = struct {
    /// Size of the output buffer in bytes
    const BUFFER_SIZE = 4096;
    /// Number of spaces per indentation level
    const INDENT_SIZE = 4;
    /// Comment prefix string
    const COMMENT_PREFIX = "// ";
};

/// FileOutput provides a buffered writer for generating formatted Zig source files.
/// Handles proper indentation, comments, and multi-line string output while
/// maintaining efficient I/O through buffering.
pub const FileOutput = struct {
    /// Memory allocator used for dynamic allocations
    allocator: std.mem.Allocator,
    /// Current indentation depth (each level is Config.INDENT_SIZE spaces)
    depth: u32,
    /// Buffered writer for improved I/O performance
    buf_writer: std.io.BufferedWriter(Config.BUFFER_SIZE, std.fs.File.Writer),
    /// Underlying file handle
    file: std.fs.File,

    /// Initialize a new FileOutput with the given allocator and path.
    /// Creates the necessary directory structure and opens the file for writing.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for buffer allocations
    ///   - path: Output file path
    ///
    /// Returns: Initialized FileOutput or an error
    /// Error: InvalidPath if the path is invalid
    ///        File system errors during directory creation or file opening
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !FileOutput {
        // Ensure directory exists
        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
        try std.fs.cwd().makePath(dir_path);

        // Create or truncate output file
        var file = try std.fs.cwd().createFile(path, .{
            .truncate = true,
            .read = false,
        });

        return FileOutput{
            .allocator = allocator,
            .depth = 0,
            .file = file,
            .buf_writer = std.io.bufferedWriter(file.writer()),
        };
    }

    /// Writes the current indentation prefix based on depth.
    /// Each indentation level adds Config.INDENT_SIZE spaces.
    ///
    /// Returns: Error if write operation fails
    pub fn writePrefix(self: *FileOutput) !void {
        const writer = self.buf_writer.writer();
        const spaces = self.depth * Config.INDENT_SIZE;
        try writer.writeByteNTimes(' ', spaces);
    }

    /// Writes a single-line comment with proper indentation.
    /// Automatically adds the comment prefix and a newline.
    ///
    /// Parameters:
    ///   - comment: Comment text to write
    ///
    /// Returns: Error if write operation fails
    pub fn writeComment(self: *FileOutput, comment: []const u8) !void {
        const writer = self.buf_writer.writer();
        try self.writePrefix();
        try writer.writeAll(Config.COMMENT_PREFIX);
        try writer.writeAll(comment);
        try writer.writeByte('\n');
    }

    /// Flushes any buffered content and closes the file.
    /// Should be called when finished writing to ensure all data is written.
    ///
    /// Returns: Error if flush operation fails
    pub fn close(self: *FileOutput) !void {
        try self.buf_writer.flush();
        self.file.close();
    }

    /// Writes a single linebreak without any indentation.
    ///
    /// Returns: Error if write operation fails
    pub fn linebreak(self: *FileOutput) !void {
        try self.buf_writer.writer().writeByte('\n');
    }

    /// Writes a multi-line string with proper indentation for each line.
    /// Maintains consistent indentation across line breaks.
    ///
    /// Parameters:
    ///   - value: String content to write
    ///
    /// Returns: Error if write or allocation operations fail
    pub fn writeString(self: *FileOutput, value: []const u8) !void {
        // Generate indentation prefix
        var prefix = try self.createIndentPrefix();
        defer prefix.deinit();

        // Write lines with proper indentation
        try self.writeIndentedLines(value, prefix.items);
    }

    /// Continues writing a string without adding indentation or linebreaks.
    /// Useful for building complex strings across multiple write operations.
    ///
    /// Parameters:
    ///   - value: String content to write
    ///
    /// Returns: Error if write operation fails
    pub fn continueString(self: *FileOutput, value: []const u8) !void {
        try self.buf_writer.writer().writeAll(value);
    }

    // Private helper functions

    /// Creates an indentation prefix based on current depth
    fn createIndentPrefix(self: *FileOutput) !std.ArrayList(u8) {
        var prefix_list = std.ArrayList(u8).init(self.allocator);
        errdefer prefix_list.deinit();

        const spaces = self.depth * Config.INDENT_SIZE;
        try prefix_list.appendNTimes(' ', spaces);

        return prefix_list;
    }

    /// Writes lines with consistent indentation
    fn writeIndentedLines(self: *FileOutput, content: []const u8, prefix: []const u8) !void {
        const writer = self.buf_writer.writer();
        var line_iterator = std.mem.splitSequence(u8, content, "\n");

        while (line_iterator.next()) |line| {
            try writer.writeAll(prefix);
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }
    }
};
