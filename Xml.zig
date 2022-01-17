//! XML tokenizer. Takes the entire input buffer as the input; provides a
//! streaming, non-allocating API to pull tokens one at a time.

bytes: []const u8,
index: usize = 0,
line: usize = 0,
column: usize = 0,
state: State = .start,
/// This field is populated when `next` returns a `Token` with `Token.Tag.invalid`.
error_note: ErrorNote = undefined,

pub const Token = struct {
    tag: Tag,
    bytes: []const u8,

    pub const Tag = enum {
        /// Error tokenizing the XML. Details can be found at the line, column,
        /// and error_note field.
        invalid,
        /// Example: "xml".
        /// Possible next tags:
        /// * `attr_key`
        /// * `attr_value`
        /// * `tag_open`
        doctype,
        /// Example: "<head>"
        /// Possible next tags:
        /// * `attr_key`
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_open,
        /// Example: "</head>"
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_close,
        /// Emitted for empty nodes such as "<head/>".
        /// `bytes` will contain the "/".
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_close_empty,
        /// Only the name of the key, does not include the '=' or the value.
        /// Possible next tags:
        /// * `attr_value`
        attr_key,
        /// Exactly the bytes of the string, including the quotes. Does no decoding.
        /// Possible next tags:
        /// * `attr_key`
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        attr_value,
        /// The data between tags. Exactly the bytes, does no decoding.
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        content,
        /// End of file was reached.
        eof,
    };
};

pub const ErrorNote = enum {
    @"invalid byte",
};

pub fn next(xml: *Xml) Token {
    var tok_start: usize = undefined;
    while (xml.index < xml.bytes.len) {
        const byte = xml.bytes[xml.index];
        switch (xml.state) {
            .start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => xml.state = .doctype_q,
                else => return xml.fail(.@"invalid byte"),
            },
            .doctype_q => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => xml.state = .doctype_name_start,
                else => return xml.fail(.@"invalid byte"),
            },
            .doctype_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>', '<' => return xml.fail(.@"invalid byte"),
                else => {
                    tok_start = xml.index;
                    xml.state = .doctype_name;
                },
            },
            .doctype_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return xml.emit(.doctype, .{
                    .tag = .doctype,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '?' => return xml.emit(.doctype_end, .{
                    .tag = .doctype,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '>', '<' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .doctype => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => xml.state = .doctype_end,
                '<', '>' => return xml.fail(.@"invalid byte"),
                else => {
                    tok_start = xml.index;
                    xml.state = .doctype_attr_key;
                },
            },
            .doctype_attr_key => switch (byte) {
                '=' => return xml.emit(.doctype_attr_value_q, .{
                    .tag = .attr_key,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '?', '<', '>' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .doctype_attr_value_q => switch (byte) {
                '"' => {
                    xml.state = .doctype_attr_value;
                    tok_start = xml.index;
                },
                else => return xml.fail(.@"invalid byte"),
            },
            .doctype_attr_value => switch (byte) {
                '"' => return xml.emit(.doctype, .{
                    .tag = .attr_value,
                    .bytes = xml.bytes[tok_start .. xml.index + 1],
                }),
                '\n' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .doctype_end => switch (byte) {
                '>' => xml.state = .body,
                else => return xml.fail(.@"invalid byte"),
            },
            .body => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => xml.state = .tag_name_start,
                else => {
                    xml.state = .content;
                    tok_start = xml.index;
                },
            },
            .content => switch (byte) {
                '<' => return xml.emit(.tag_name_start, .{
                    .tag = .content,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                else => {},
            },
            .tag_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>', '<' => return xml.fail(.@"invalid byte"),
                '/' => xml.state = .tag_close_start,
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_name;
                },
            },
            .tag_close_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>', '<' => return xml.fail(.@"invalid byte"),
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_close_name;
                },
            },
            .tag_close_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return xml.emit(.tag_close_b, .{
                    .tag = .tag_open,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '>' => return xml.emit(.body, .{
                    .tag = .tag_close,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '<' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .tag_close_b => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>' => xml.state = .body,
                else => return xml.fail(.@"invalid byte"),
            },
            .tag_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return xml.emit(.tag, .{
                    .tag = .tag_open,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '>' => return xml.emit(.body, .{
                    .tag = .tag_open,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '<' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .tag => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => return xml.fail(.@"invalid byte"),
                '>' => xml.state = .body,
                '/' => {
                    tok_start = xml.index;
                    xml.state = .tag_end_empty;
                },
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_attr_key;
                },
            },
            .tag_end_empty => switch (byte) {
                '>' => return xml.emit(.body, .{
                    .tag = .tag_close_empty,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                else => return xml.fail(.@"invalid byte"),
            },
            .tag_attr_key => switch (byte) {
                '=' => return xml.emit(.tag_attr_value_q, .{
                    .tag = .attr_key,
                    .bytes = xml.bytes[tok_start..xml.index],
                }),
                '<', '>' => return xml.fail(.@"invalid byte"),
                else => {},
            },
            .tag_attr_value_q => switch (byte) {
                '"' => {
                    xml.state = .tag_attr_value;
                    tok_start = xml.index;
                },
                else => return xml.fail(.@"invalid byte"),
            },
            .tag_attr_value => switch (byte) {
                '"' => return xml.emit(.tag, .{
                    .tag = .attr_value,
                    .bytes = xml.bytes[tok_start .. xml.index + 1],
                }),
                '\n' => return xml.fail(.@"invalid byte"),
                else => {},
            },
        }
        xml.advanceCursor();
    }
    return .{
        .tag = .eof,
        .bytes = xml.bytes[xml.bytes.len..],
    };
}

const Xml = @This();
const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const State = enum {
    start,
    doctype_q,
    doctype_name,
    doctype_name_start,
    doctype,
    doctype_attr_key,
    doctype_attr_value_q,
    doctype_attr_value,
    doctype_end,
    body,
    content,
    tag_name_start,
    tag_name,
    tag,
    tag_attr_key,
    tag_attr_value_q,
    tag_attr_value,
    tag_close_start,
    tag_close_name,
    tag_close_b,
    tag_end_empty,
};

fn fail(xml: *Xml, note: ErrorNote) Token {
    xml.error_note = note;
    return .{ .tag = .invalid, .bytes = xml.bytes[xml.index..][0..0] };
}

fn emit(xml: *Xml, next_state: State, token: Token) Token {
    xml.state = next_state;
    xml.advanceCursor();
    return token;
}

fn advanceCursor(xml: *Xml) void {
    const byte = xml.bytes[xml.index];
    xml.index += 1;

    if (byte == '\n') {
        xml.line += 1;
        xml.column = 0;
    } else {
        xml.column += 1;
    }
}

test "hello world xml" {
    const bytes =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<map></map>
    ;
    var xml: Xml = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .attr_key, "version");
    try testExpect(&xml, .attr_value, "\"1.0\"");
    try testExpect(&xml, .attr_key, "encoding");
    try testExpect(&xml, .attr_value, "\"UTF-8\"");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
    try testExpect(&xml, .eof, "");
}

test "some props" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\  <property name="gravity" type="float" value="12.34"/>
        \\  <property name="never gonna give you up" type="bool" value="true"/>
        \\  <property name="never gonna let you down" type="bool" value="true"/>
        \\ </properties>
        \\</map>
    ;
    var xml: Xml = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_open, "properties");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"gravity\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"float\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"12.34\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna give you up\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna let you down\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_close, "properties");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
}

fn testExpect(xml: *Xml, tag: Token.Tag, bytes: []const u8) !void {
    const tok = xml.next();
    try testing.expectEqual(tag, tok.tag);
    try testing.expectEqualStrings(bytes, tok.bytes);
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try std.process.argsAlloc(arena);
    const input_file = args[1];
    const max_bytes = std.math.maxInt(u32);
    var xml: Xml = .{ .bytes = try std.fs.cwd().readFileAlloc(arena, input_file, max_bytes) };
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const writer = bw.writer();
    while (true) {
        const token = xml.next();
        try writer.print("{s}: {s}\n", .{ @tagName(token.tag), token.bytes });
        if (token.tag == .eof) break;
    }
    try bw.flush();
}
