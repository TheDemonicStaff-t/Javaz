const ClassFile = @This();

const std = @import("std");
const cpinfo = @import("cinfo.zig");
const attrs = @import("attrs.zig");
const util = @import("../util.zig");

// imported values
const cwd = std.fs.cwd();
// imported structs
const CpInfo = cpinfo.CpInfo;
const AttributeInfo = attrs.AttributeInfo;
const Allocator = std.mem.Allocator;
const Reader = std.fs.File.Reader;
const Writer = std.fs.File.Writer;
const File = std.fs.File;

// data
minor_version: u16 = 0,
major_version: u16 = 0,
access_flags: AccessFlags = .{},
this_class: u16 = 0,
super_class: u16 = 0,
const_pool: []CpInfo = undefined,
interfaces: ?[]u16 = undefined,
fields: ?[]FieldInfo = undefined,
methods: ?[]MethodInfo = undefined,
attributes: ?[]AttributeInfo = undefined,
// tools
allocator: Allocator,
file: File,
reader: Reader,

pub fn init(fname: []const u8, allocator: Allocator) !ClassFile {
    var file = try cwd.openFile(fname, .{});
    var reader = file.reader();
    var cf = ClassFile{
        .allocator = allocator,
        .file = file,
        .reader = reader,
    };

    if (try reader.readIntBig(u32) != 0xcafebabe) return error.InvalidClassFile;

    cf.minor_version = try reader.readIntBig(u16);
    cf.major_version = try reader.readIntBig(u16);
    if (cf.major_version > 66 or cf.major_version < 45) return error.InvalidVersion;
    cf.const_pool = try cpinfo.initCpool(reader, allocator);
    cf.access_flags = @bitCast(try reader.readIntBig(u16));
    cf.this_class = try reader.readIntBig(u16);
    cf.super_class = try reader.readIntBig(u16);

    // parse interfaces
    var count = try reader.readIntBig(u16);
    if (count == 0) {
        cf.interfaces = null;
    } else {
        cf.interfaces = try cf.allocator.alloc(u16, count);
        for (cf.interfaces.?) |*i| i.* = try reader.readIntBig(u16);
    }

    // parse fields
    count = try reader.readIntBig(u16);
    if (count == 0) {
        cf.fields = null;
    } else {
        cf.fields = try cf.allocator.alloc(FieldInfo, count);
        for (cf.fields.?) |*f| {
            f.access_flags = @bitCast(try reader.readIntBig(u16));
            f.name_idx = try reader.readIntBig(u16);
            f.descriptor_idx = try reader.readIntBig(u16);
            count = try reader.readIntBig(u16);
            if (count == 0) {
                f.attributes = null;
            } else {
                f.attributes = try cf.allocator.alloc(AttributeInfo, count);
                for (f.attributes.?) |*attr| attr.* = try attrs.parseAttr(reader, cf.allocator, cf.const_pool);
            }
        }
    }

    //// parse methods
    count = try reader.readIntBig(u16);
    if (count == 0) {
        cf.methods = null;
    } else {
        cf.methods = try cf.allocator.alloc(MethodInfo, count);
        for (cf.methods.?) |*m| {
            m.access_flags = @bitCast(try reader.readIntBig(u16));
            m.name_idx = try reader.readIntBig(u16);
            m.descriptor_idx = try reader.readIntBig(u16);
            count = try reader.readIntBig(u16);
            if (count == 0) {
                m.attributes = null;
            } else {
                m.attributes = try cf.allocator.alloc(AttributeInfo, count);
                for (m.attributes.?) |*attr| attr.* = try attrs.parseAttr(reader, cf.allocator, cf.const_pool);
            }
        }
    }

    //// parse attributes
    count = try reader.readIntBig(u16);
    if (count == 0) {
        cf.attributes = null;
    } else {
        cf.attributes = try cf.allocator.alloc(AttributeInfo, count);
        for (cf.attributes.?) |*attr| attr.* = try attrs.parseAttr(reader, cf.allocator, cf.const_pool);
    }
    return cf;
}
pub fn encode(self: ClassFile, out: Writer) !void {
    try out.writeIntBig(u32, 0xcafebabe);
    try out.writeIntBig(u16, self.minor_version);
    try out.writeIntBig(u16, self.major_version);
    try cpinfo.encodeCpool(self.const_pool, out);
    try out.writeIntBig(u16, @as(u16, @bitCast(self.access_flags)));
    try out.writeIntBig(u16, self.this_class);
    try out.writeIntBig(u16, self.super_class);
    if (self.interfaces) |interfaces| {
        try out.writeIntBig(u16, @as(u16, @intCast(interfaces.len)));
        for (interfaces) |i| try out.writeIntBig(u16, i);
    } else try out.writeIntBig(u16, 0);
    if (self.fields) |fields| {
        try out.writeIntBig(u16, @as(u16, @intCast(fields.len)));
        for (fields) |field| {
            try out.writeIntBig(u16, @as(u16, @bitCast(field.access_flags)));
            try out.writeIntBig(u16, field.name_idx);
            try out.writeIntBig(u16, field.descriptor_idx);
            if (field.attributes) |atrs| {
                try attrs.encodeAttrs(atrs, out);
            } else try out.writeIntBig(u16, 0);
        }
    } else try out.writeIntBig(u16, 0);
    if (self.methods) |methods| {
        try out.writeIntBig(u16, @as(u16, @intCast(methods.len)));
        for (methods) |method| {
            try out.writeIntBig(u16, @as(u16, @bitCast(method.access_flags)));
            try out.writeIntBig(u16, method.name_idx);
            try out.writeIntBig(u16, method.descriptor_idx);
            if (method.attributes) |atrs| {
                try attrs.encodeAttrs(atrs, out);
            } else try out.writeIntBig(u16, 0);
        }
    } else try out.writeIntBig(u16, 0);
    if (self.attributes) |atrs| {
        try attrs.encodeAttrs(atrs, out);
    } else try out.writeIntBig(u16, 0);
}
pub fn deinit(self: *ClassFile) void {
    if (self.attributes) |atrs| {
        for (atrs) |*a| a.freeAttr(self.allocator);
        self.allocator.free(atrs);
    }
    if (self.methods) |methods| {
        for (methods) |m| {
            if (m.attributes) |atrs| {
                for (atrs) |*a| a.freeAttr(self.allocator);
                self.allocator.free(atrs);
            }
        }
        self.allocator.free(methods);
    }
    if (self.fields) |fields| {
        for (fields) |f| {
            if (f.attributes) |atrs| {
                for (atrs) |*a| a.freeAttr(self.allocator);
                self.allocator.free(atrs);
            }
        }
        self.allocator.free(fields);
    }
    if (self.interfaces) |interfaces| self.allocator.free(interfaces);
    cpinfo.deinitCpool(&self.const_pool, self.allocator);
}
pub const FieldInfo = struct {
    access_flags: FieldAccessFlags,
    name_idx: u16,
    descriptor_idx: u16,
    attributes: ?[]AttributeInfo,
    pub const FieldAccessFlags = packed struct(u16) { public: bool = false, private: bool = false, protected: bool = false, static: bool = false, final: bool = false, _p0: u1 = 0, volatil: bool = false, transient: bool = false, _p1: u4 = 0, synthetic: bool = false, _p2: u1 = 0, enumeration: bool = false, _p3: u1 = 0 };
};
pub const MethodInfo = struct {
    access_flags: MethodAccessFlags,
    name_idx: u16,
    descriptor_idx: u16,
    attributes: ?[]AttributeInfo,

    pub const MethodAccessFlags = packed struct(u16) { public: bool = false, private: bool = false, protected: bool = false, static: bool = false, final: bool = false, synchronized: bool = false, bridge: bool = false, varargs: bool = false, native: bool = false, _p0: u1 = 0, abstract: bool = false, strict: bool = false, synthetic: bool = false, _p1: u3 = 0 };
};
pub const AccessFlags = packed struct(u16) { public: bool = false, _p0: u3 = 0, final: bool = false, super: bool = false, _p1: u3 = 0, interface: bool = false, abstract: bool = false, _p2: u1 = 0, synthetic: bool = false, annotation: bool = false, enumeration: bool = false, module: bool = false };
