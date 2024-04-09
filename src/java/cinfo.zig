const std = @import("std");

// imported structs
const Reader = std.fs.File.Reader;
const Writer = std.fs.File.Writer;
const Allocator = std.mem.Allocator;

pub fn initCpool(reader: Reader, allocator: Allocator) ![]CpInfo {
    var length = try reader.readIntBig(u16) - 1;
    var cpool = try allocator.alloc(CpInfo, length);
    var long_entry: bool = false;
    for (cpool) |*c| {
        if (long_entry) {
            c.* = @unionInit(CpInfo, "empty", .{});
            long_entry = false;
        } else {
            var tag = try reader.readByte();
            if (tag == 5 or tag == 6) long_entry = true;
            inline for (@typeInfo(Tag).Enum.fields, 0..) |f, i| {
                if (f.value == tag) {
                    const T = std.meta.fields(CpInfo)[i].type;
                    var value = if (@hasDecl(T, "decode")) try @field(T, "decode")(reader, allocator) else try Serialize(T).decode(reader);
                    c.* = @unionInit(CpInfo, f.name, value);
                }
            }
        }
    }

    return cpool;
}

pub fn encodeCpool(self: []CpInfo, out: Writer) !void {
    try out.writeIntBig(u16, @as(u16, @intCast(self.len + 1)));
    for (self) |c| {
        inline for (@typeInfo(Tag).Enum.fields, 0..) |field, i| {
            if (field.value == @intFromEnum(std.meta.activeTag(c))) {
                if (field.value != 2) try out.writeIntBig(u8, field.value);
                const T = std.meta.fields(CpInfo)[i].type;
                if (@hasDecl(T, "encode")) try @field(c, std.meta.fields(CpInfo)[i].name).encode(out) else try Serialize(T).encode(@field(c, field.name), out);
            }
        }
    }
}

pub fn deinitCpool(self: *[]CpInfo, allocator: Allocator) void {
    for (self.*) |*c| {
        if (std.meta.activeTag(c.*) == .utf8) c.utf8.deinit(allocator);
    }
    allocator.free(self.*);
    self.* = undefined;
}

pub fn Serialize(comptime T: type) type {
    return struct {
        pub fn decode(reader: Reader) !T {
            var value: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(value, field.name) = switch (@typeInfo(field.type)) {
                    .Int => try reader.readIntBig(field.type),
                    else => @compileError("The Info Structure" ++ @typeName(T) ++ "cannot be serialized because The Field" ++ field.name ++ "is not an int type"),
                };
            }
            return value;
        }
        pub fn encode(self: T, out: Writer) !void {
            inline for (std.meta.fields(T)) |field| {
                switch (@typeInfo(field.type)) {
                    .Int => try out.writeIntBig(field.type, @field(self, field.name)),
                    else => @compileError("The Info Structure" ++ @typeName(T) ++ "cannot be serialized because The Field" ++ field.name ++ "is nat an int type"),
                }
            }
        }
    };
}

pub const Tag = enum(u8) {
    utf8 = 1,
    empty = 2,
    integer = 3,
    float = 4,
    long = 5,
    double = 6,
    class = 7,
    string = 8,
    fieldref = 9,
    methodref = 10,
    interface_methodref = 11,
    name_and_type = 12,
    method_handle = 15,
    method_type = 16,
    dynamic = 17, // TODO
    invoke_dynamic = 18,
    module = 19,
    package = 20,
};

pub const CpInfo = union(Tag) {
    utf8: Utf8Info,
    empty: struct {},
    integer: IntegerInfo,
    float: FloatInfo,
    long: LongInfo,
    double: DoubleInfo,
    class: ClassInfo,
    string: StringInfo,
    fieldref: RefInfo,
    methodref: RefInfo,
    interface_methodref: RefInfo,
    name_and_type: NameAndTypeInfo,
    method_handle: MethodHandleInfo,
    method_type: MethodTypeInfo,
    dynamic: DynamicInfo,
    invoke_dynamic: DynamicInfo,
    module: ModuleInfo,
    package: PackageInfo,
};

// serializable
pub const IntegerInfo = struct { bytes: u32 };
pub const FloatInfo = struct { bytes: u32 };
pub const LongInfo = struct { bytes: u64 };
pub const DoubleInfo = struct { bytes: u64 };
pub const ClassInfo = struct { name_idx: u16 };
pub const StringInfo = struct { string_idx: u16 };
pub const RefInfo = struct { class_idx: u16, name_and_type_idx: u16 };
pub const NameAndTypeInfo = struct { name_idx: u16, descriptor_idx: u16 };
pub const MethodHandleInfo = struct { reference_kind: u8, reference_index: u16 };
pub const MethodTypeInfo = struct { descriptor_idx: u16 };
pub const DynamicInfo = struct { bootstrap_method_attr_idx: u16, name_and_type_idx: u16 };
pub const ModuleInfo = struct { name_idx: u16 };
pub const PackageInfo = struct { name_idx: u16 };

// decoded
pub const Utf8Info = struct {
    bytes: []u8,
    pub fn decode(reader: Reader, allocator: Allocator) !Utf8Info {
        var len = try reader.readIntBig(u16);
        var bytes = try allocator.alloc(u8, len);
        _ = try reader.readAll(bytes);
        return .{
            .bytes = bytes,
        };
    }

    pub fn encode(self: Utf8Info, out: Writer) !void {
        try out.writeIntBig(u16, @as(u16, @intCast(self.bytes.len)));
        try out.writeAll(self.bytes);
    }

    pub fn deinit(self: *Utf8Info, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};
