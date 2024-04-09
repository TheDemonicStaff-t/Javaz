const std = @import("std");
const java = @import("../java.zig");
// imported values
const Instructions = java.bytecode.Instructions;
// imported structs
const Reader = std.fs.File.Reader;
const Writer = std.fs.File.Writer;
const Allocator = std.mem.Allocator;
const CpInfo = java.cpinfo.CpInfo;

pub fn parseAttr(reader: Reader, allocator: Allocator, cpool: []CpInfo) anyerror!AttributeInfo {
    var attr_tag = try reader.readIntBig(u16);
    var attr_length = try reader.readIntBig(u32);
    inline for (std.meta.fields(AttributeInfo)[0..]) |f| {
        if (std.mem.eql(u8, @field(f.type, "name"), cpool[attr_tag - 1].utf8.bytes)) {
            var val: f.type = if (@hasDecl(f.type, "decode")) try @field(f.type, "decode")(reader, allocator, cpool, attr_length, attr_tag) else try Serialize(f.type).decode(reader, attr_tag, attr_length);
            return @unionInit(AttributeInfo, f.name, val);
        }
    }
    std.debug.print("debug: unknown attribute type: {s}\n", .{cpool[attr_tag - 1].utf8.bytes});
    unreachable;
}
pub fn encodeAttrs(self: []AttributeInfo, out: Writer) anyerror!void {
    try out.writeIntBig(u16, @as(u16, @intCast(self.len)));
    for (self) |attr| {
        inline for (std.meta.fields(AttributeInfo)) |f| {
            if (std.meta.activeTag(attr) == @field(std.meta.Tag(AttributeInfo), f.name)) {
                if (@hasDecl(f.type, "encode")) try @field(attr, f.name).encode(out) else try Serialize(f.type).encode(@field(attr, f.name), out);
            }
        }
    }
}
pub const AttributeInfo = union(enum) {
    constant_value: ConstantValue,
    code: Code,
    exceptions: Exceptions,
    source_file: SourceFile,
    line_number_table: LineNumberTable,
    local_variable_table: LocalVariableTable,
    inner_classes: InnerClasses,
    synthetic: Synthetic,
    deprecated: Deprecatred,
    enclosing_method: EnclosingMethod,
    signature: Signature,
    source_debug_exstension: SourceDebugExstension,
    local_variable_type_table: LocalVariableTypeTable,
    runtime_visible_annotations: RuntimeVisibleAnnotations,
    runtime_invisible_annotations: RuntimeInvisibleAnnotations,
    runtime_visible_parameter_annotations: RuntimeVisibleParameterAnnotations,
    runtime_invisible_parameter_annotations: RuntimeInvisibleParameterAnnotations,
    annotation_default: AnnotationDefault,
    stack_map_table: StackMapTable,
    bootstrap_methods: BootstrapMethods,
    runtime_visible_type_annotations: RuntimeVisibleTypeAnnotations,
    runtime_invisible_tupe_annotations: RuntimeInvisibleTypeAnnotations,
    method_parameters: MethodParameters,
    module: Module,
    module_packages: ModulePackages,
    module_main_class: ModuleMainClass,
    nest_host: NestHost,
    record: Record,
    permitted_subclasses: PermittedSubclasses,

    pub fn freeAttr(self: *AttributeInfo, allocator: Allocator) void {
        inline for (std.meta.fields(AttributeInfo)) |f| {
            if (std.meta.activeTag(self.*) == @field(std.meta.Tag(AttributeInfo), f.name)) {
                if (@hasDecl(f.type, "deinit")) @field(self, f.name).deinit(allocator);
            }
        }
    }
};

pub fn Serialize(comptime T: type) type {
    return struct {
        pub fn decode(reader: Reader, attr_tag: u16, attr_len: u32) !T {
            var value: T = undefined;
            value.tag = attr_tag;
            value.len = attr_len;
            inline for (std.meta.fields(T)[2..]) |field| {
                @field(value, field.name) = switch (@typeInfo(field.type)) {
                    .Int => try reader.readIntBig(field.type),
                    else => @compileError("The Info Structure" ++ @typeName(T) ++ "cannot be serialized because The Field" ++ field.name ++ "is not an int type"),
                };
            }
            return value;
        }
        pub fn encode(self: T, out: Writer) !void {
            try out.writeIntBig(u16, self.tag);
            try out.writeIntBig(u32, self.len);
            inline for (std.meta.fields(T)[2..]) |field| {
                switch (@typeInfo(field.type)) {
                    .Int => try out.writeIntBig(field.type, @field(self, field.name)),
                    else => @compileError("The Info Structure" ++ @typeName(T) ++ "cannot be serialized because The Field" ++ field.name ++ "is not an int type"),
                }
            }
        }
    };
}
// decoded structs
pub const Code = struct {
    pub const name = "Code";
    tag: u16,
    len: u32,
    max_stack: u16 = 0,
    max_locals: u16 = 0,
    code: ?[]u8 = undefined,
    exception_table: ?[]CodeException = undefined,
    attributes: ?[]AttributeInfo = undefined,

    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !Code {
        var c = Code{ .len = len, .tag = tag };
        c.max_stack = try reader.readIntBig(u16);
        c.max_locals = try reader.readIntBig(u16);

        // parse code
        var leng = try reader.readIntBig(u32);
        if (leng == 0) {
            c.code = null;
        } else {
            c.code = try allocator.alloc(u8, leng);
            _ = try reader.readAll(c.code.?);
        }

        // parse exceptions
        leng = try reader.readIntBig(u16);
        if (leng == 0) {
            c.exception_table = null;
        } else {
            c.exception_table = try allocator.alloc(CodeException, leng);
            for (c.exception_table.?) |*e| {
                e.start_pc = try reader.readIntBig(u16);
                e.end_pc = try reader.readIntBig(u16);
                e.handler_pc = try reader.readIntBig(u16);
                e.catch_type = try reader.readIntBig(u16);
            }
        }

        // parse attributes
        leng = try reader.readIntBig(u16);
        if (leng == 0) {
            c.attributes = null;
        } else {
            c.attributes = try allocator.alloc(AttributeInfo, leng);
            for (c.attributes.?) |*a| a.* = try parseAttr(reader, allocator, cpool);
        }

        return c;
    }
    pub fn encode(self: Code, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, self.max_stack);
        try out.writeIntBig(u16, self.max_locals);
        if (self.code) |code| {
            try out.writeIntBig(u32, @as(u16, @intCast(code.len)));
            try out.writeAll(code);
        } else try out.writeIntBig(u32, 0);
        if (self.exception_table) |exception_table| {
            try out.writeIntBig(u16, @as(u16, @intCast(exception_table.len)));
            for (exception_table) |e| {
                try out.writeIntBig(u16, e.start_pc);
                try out.writeIntBig(u16, e.end_pc);
                try out.writeIntBig(u16, e.handler_pc);
                try out.writeIntBig(u16, e.catch_type);
            }
        } else try out.writeIntBig(u16, 0);
        if (self.attributes) |attributes| {
            try encodeAttrs(attributes, out);
        } else try out.writeIntBig(u16, 0);
    }
    pub fn deinit(self: *Code, allocator: Allocator) void {
        if (self.code) |c| allocator.free(c);
        self.code = undefined;
        if (self.exception_table) |e| allocator.free(e);
        self.exception_table = undefined;
        if (self.attributes) |a| for (a) |*attr| attr.freeAttr(allocator);
        allocator.free(self.attributes.?);
        self.attributes = undefined;
    }

    pub const CodeException = struct { start_pc: u16, end_pc: u16, handler_pc: u16, catch_type: u16 };
};
pub const StackMapTable = struct {
    pub const name = "StackMapTable";
    tag: u16,
    len: u32,
    table: []StackMapFrame,

    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !StackMapTable {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var smt = StackMapTable{ .tag = tag, .len = len, .table = try allocator.alloc(StackMapFrame, leng) };

        for (smt.table) |*sf| {
            sf.tag = try reader.readByte();
            switch(sf.tag) {
                0...63 => sf.frame = StackMapFrame.Frame{.same_frame = .{}},
                64...127 => sf.frame = @unionInit(StackMapFrame.Frame, "same_locals_1_stack_item_frame", try StackMapFrame.VerificationType.get(reader)),
                247 => sf.frame = @unionInit(StackMapFrame.Frame, "same_locals_1_stack_item_frame_extended", StackMapFrame.Frame.SingleStackExt{.offset_delta = try reader.readIntBig(u16), .stack = try StackMapFrame.VerificationType.get(reader)}),
                248...250 => sf.frame = @unionInit(StackMapFrame.Frame, "chop_frame", StackMapFrame.Frame.ChopFrame{.offset_delta = try reader.readIntBig(u16)}),
                251 => sf.frame = @unionInit(StackMapFrame.Frame, "same_frame_extended", StackMapFrame.Frame.ChopFrame{.offset_delta = try reader.readIntBig(u16)}),
                252...254 => {
                    var a = StackMapFrame.Frame.AppendFrame{};
                    a.offset_delta = try reader.readIntBig(u16);
                    a.locals = try allocator.alloc(StackMapFrame.VerificationType, sf.tag - 251);
                    for (a.locals) |*l| l.* = try StackMapFrame.VerificationType.get(reader);
                    sf.frame = @unionInit(StackMapFrame.Frame, "append_frame", a);
                },
                255 => {
                    var a = StackMapFrame.Frame.FullFrame{};
                    a.offset_delta = try reader.readIntBig(u16);
                    var flen = try reader.readIntBig(u16);
                    a.locals = try allocator.alloc(StackMapFrame.VerificationType, flen);
                    for (a.locals)  |*l| l.* = try StackMapFrame.VerificationType.get(reader);
                    flen = try reader.readIntBig(u16);
                    a.stack = try allocator.alloc(StackMapFrame.VerificationType, flen);
                    for (a.stack) |*s| s.* = try StackMapFrame.VerificationType.get(reader);
                    sf.frame = @unionInit(StackMapFrame.Frame, "full_frame", a);
                },
                else => {},
            }
        }

        return smt;
    }
    pub fn encode(self: StackMapTable, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);

        try out.writeIntBig(u16, @as(u16, @intCast(self.table.len)));
        for (self.table) |e| {
            try out.writeByte(e.tag);
            if (e.tag > 63 and e.tag < 128) {
                try e.frame.same_locals_1_stack_item_frame.encode(out);
            } else if (e.tag == 247) {
                try out.writeIntBig(u16, e.frame.same_locals_1_stack_item_frame_extended.offset_delta);
                try e.frame.same_locals_1_stack_item_frame_extended.stack.encode(out);
            } else if (e.tag > 247 and e.tag < 251) {
                try out.writeIntBig(u16, e.frame.chop_frame.offset_delta);
            } else if (e.tag == 251) {
                try out.writeIntBig(u16, e.frame.same_frame_extended.offset_delta);
            } else if (e.tag > 251 and e.tag < 255) {
                try out.writeIntBig(u16, e.frame.append_frame.offset_delta);
                for (e.frame.append_frame.locals) |local| try local.encode(out);
            } else if (e.tag == 255) {
                try out.writeIntBig(u16, e.frame.full_frame.offset_delta);
                try out.writeIntBig(u16, @as(u16, @intCast(e.frame.full_frame.locals.len)));
                for (e.frame.full_frame.locals) |local| try local.encode(out);
                try out.writeIntBig(u16, @as(u16, @intCast(e.frame.full_frame.stack.len)));
                for (e.frame.full_frame.stack) |s| try s.encode(out);
            }
        }
    }
    pub fn deinit(self: StackMapTable, allocator: Allocator) void {
        for (self.table) |frame| {
            switch (frame.frame) {
                .append_frame => |af| allocator.free(af.locals),
                .full_frame => |ff| {
                    allocator.free(ff.locals);
                    allocator.free(ff.stack);
                },
                else => {},
            }
        }
    }
    pub const StackMapFrame = struct {
        tag: u8,
        frame: Frame = undefined,

        pub const Frame = union(enum) {
            same_frame: struct{},
            same_locals_1_stack_item_frame: VerificationType,
            same_locals_1_stack_item_frame_extended: SingleStackExt,
            chop_frame: ChopFrame,
            same_frame_extended: ChopFrame,
            append_frame: AppendFrame,
            full_frame: FullFrame,

            pub const SingleStackExt = struct { offset_delta: u16 = 0, stack: VerificationType = undefined };
            pub const AppendFrame = struct { offset_delta: u16 = 0, locals: []VerificationType = undefined };
            pub const ChopFrame = struct { offset_delta: u16 = 0 };
            pub const FullFrame = struct { offset_delta: u16 = 0, locals: []VerificationType = undefined, stack: []VerificationType = undefined };
        };
        pub const VType = enum(u8) {
            top = 0,
            integer = 1,
            float = 2,
            double = 3,
            long = 4,
            nul = 5,
            uninit_this = 6,
            object = 7,
            uninit = 8,
        };
        pub const VerificationType = union(VType) {
            top: void,
            integer: void,
            float: void,
            double: void,
            long: void,
            nul: void,
            uninit_this: void,
            object: ObjectType,
            uninit: UninitType,

            pub const ObjectType = struct { cpool_idx: u16 = 0 };
            pub const UninitType = struct { offset: u16 };

            pub fn get(reader: Reader) !VerificationType {
                var t: VType = @enumFromInt(try reader.readByte());
                var vf: VerificationType = switch (t) {
                    .top => @unionInit(VerificationType, "top", undefined),
                    .integer => @unionInit(VerificationType, "integer", undefined),
                    .float => @unionInit(VerificationType, "float", undefined),
                    .double => @unionInit(VerificationType, "double", undefined),
                    .long => @unionInit(VerificationType, "long", undefined),
                    .nul => @unionInit(VerificationType, "nul", undefined),
                    .uninit_this => @unionInit(VerificationType, "uninit_this", undefined),
                    .object => @unionInit(VerificationType, "object", ObjectType{ .cpool_idx = try reader.readIntBig(u16) }),
                    .uninit => @unionInit(VerificationType, "uninit", UninitType{ .offset = try reader.readIntBig(u16) }),
                };
                return vf;
            }
            pub fn encode(self: VerificationType, out: Writer) !void {
                try out.writeByte(@intFromEnum(std.meta.activeTag(self)));
                switch (self) {
                    .object => |object| try out.writeIntBig(u16, object.cpool_idx),
                    .uninit => |uninit| try out.writeIntBig(u16, uninit.offset),
                    else => {},
                }
            }
        };
    };
};
pub const Exceptions = struct {
    pub const name = "Exceptions";
    tag: u16,
    len: u32,
    exceptions: []u16,

    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !Exceptions {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var e = Exceptions{ .tag = tag, .len = len, .exceptions = try allocator.alloc(u16, leng) };
        for (e.exceptions) |*ex| ex.* = try reader.readIntBig(u16);
        return e;
    }
    pub fn encode(self: Exceptions, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.exceptions.len)));
        for (self.exceptions) |e| try out.writeIntBig(u16, e);
    }
    pub fn deinit(self: Exceptions, allocator: Allocator) void {
        allocator.free(self.exceptions);
    }
};
pub const InnerClasses = struct {
    pub const name = "InnerClasses";
    tag: u16,
    len: u32,
    classes: []Class,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !InnerClasses {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var ic = InnerClasses{ .tag = tag, .len = len, .classes = try allocator.alloc(Class, leng) };
        for (ic.classes) |*c| {
            c.inner_class_info_index = try reader.readIntBig(u16);
            c.outer_class_info_index = try reader.readIntBig(u16);
            c.inner_name_index = try reader.readIntBig(u16);
            c.inner_class_access_flags = try reader.readIntBig(u16);
        }
        return ic;
    }
    pub fn encode(self: InnerClasses, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.classes.len)));
        for (self.classes) |class| {
            try out.writeIntBig(u16, class.inner_class_info_index);
            try out.writeIntBig(u16, class.outer_class_info_index);
            try out.writeIntBig(u16, class.inner_name_index);
            try out.writeIntBig(u16, class.inner_class_access_flags);
        }
    }
    pub fn deinit(self: InnerClasses, allocator: Allocator) void {
        allocator.free(self.classes);
    }
    pub const Class = struct { inner_class_info_index: u16, outer_class_info_index: u16, inner_name_index: u16, inner_class_access_flags: u16 };
};
pub const SourceDebugExstension = struct {
    pub const name = "SourceDebugExtension";
    tag: u16,
    len: u32,
    debug_exstension: []u8,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !SourceDebugExstension {
        _ = cpool;
        var de = SourceDebugExstension{ .tag = tag, .len = len, .debug_exstension = try allocator.alloc(u8, len) };
        _ = try reader.readAll(de.debug_exstension);
        return de;
    }
    pub fn encode(self: SourceDebugExstension, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeAll(self.debug_exstension);
    }
    pub fn deinit(self: SourceDebugExstension, allocator: Allocator) void {
        allocator.free(self.debug_exstension);
    }
};
pub const LineNumberTable = struct {
    pub const name = "LineNumberTable";
    tag: u16,
    len: u32,
    ln_table: []Line,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !LineNumberTable {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var lnt = LineNumberTable{ .tag = tag, .len = len, .ln_table = try allocator.alloc(Line, leng) };
        for (lnt.ln_table) |*l| {
            l.start_pc = try reader.readIntBig(u16);
            l.line_number = try reader.readIntBig(u16);
        }
        return lnt;
    }
    pub fn encode(self: LineNumberTable, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.ln_table.len)));
        for (self.ln_table) |l| {
            try out.writeIntBig(u16, l.start_pc);
            try out.writeIntBig(u16, l.line_number);
        }
    }
    pub fn deinit(self: LineNumberTable, allocator: Allocator) void {
        allocator.free(self.ln_table);
    }
    pub const Line = struct { start_pc: u16, line_number: u16 };
};
pub const LocalVariableTable = struct {
    pub const name = "LocalVariableTable";
    tag: u16,
    len: u32,
    local_vtable: []LocalVariable,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !LocalVariableTable {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var lvt = LocalVariableTable{ .tag = tag, .len = len, .local_vtable = try allocator.alloc(LocalVariable, leng) };
        for (lvt.local_vtable) |*l| {
            l.start_pc = try reader.readIntBig(u16);
            l.length = try reader.readIntBig(u16);
            l.name_idx = try reader.readIntBig(u16);
            l.descriptor_idx = try reader.readIntBig(u16);
            l.index = try reader.readIntBig(u16);
        }
        return lvt;
    }
    pub fn encode(self: LocalVariableTable, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.local_vtable.len)));
        for (self.local_vtable) |lv| {
            try out.writeIntBig(u16, lv.start_pc);
            try out.writeIntBig(u16, lv.length);
            try out.writeIntBig(u16, lv.name_idx);
            try out.writeIntBig(u16, lv.descriptor_idx);
            try out.writeIntBig(u16, lv.index);
        }
    }
    pub fn deinit(self: LocalVariableTable, allocator: Allocator) void {
        allocator.free(self.local_vtable);
    }
    pub const LocalVariable = struct { start_pc: u16, length: u16, name_idx: u16, descriptor_idx: u16, index: u16 };
};
pub const LocalVariableTypeTable = struct {
    pub const name = "LocalVariableTypeTable";
    tag: u16,
    len: u32,
    local_vtype_table: []LocalVariableType,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !LocalVariableTypeTable {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var lvt = LocalVariableTypeTable{ .tag = tag, .len = len, .local_vtype_table = try allocator.alloc(LocalVariableType, leng) };
        for (lvt.local_vtype_table) |*l| {
            l.start_pc = try reader.readIntBig(u16);
            l.length = try reader.readIntBig(u16);
            l.name_idx = try reader.readIntBig(u16);
            l.signature_idx = try reader.readIntBig(u16);
            l.index = try reader.readIntBig(u16);
        }
        return lvt;
    }
    pub fn encode(self: LocalVariableTypeTable, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.local_vtype_table.len)));
        for (self.local_vtype_table) |lv| {
            try out.writeIntBig(u16, lv.start_pc);
            try out.writeIntBig(u16, lv.length);
            try out.writeIntBig(u16, lv.name_idx);
            try out.writeIntBig(u16, lv.signature_idx);
            try out.writeIntBig(u16, lv.index);
        }
    }
    pub fn deinit(self: LocalVariableTypeTable, allocator: Allocator) void {
        allocator.free(self.local_vtype_table);
    }
    pub const LocalVariableType = struct { start_pc: u16, length: u16, name_idx: u16, signature_idx: u16, index: u16 };
};
pub const RuntimeInvisibleAnnotations = struct {
    pub const name = "RuntimeInvisibleAnnotations";
    tag: u16,
    len: u32,
    annotations: []Annotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeInvisibleAnnotations {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var rann = RuntimeInvisibleAnnotations{ .tag = tag, .len = len, .annotations = try allocator.alloc(Annotation, leng) };
        for (rann.annotations) |*a| a.* = try Annotation.findAnnotation(reader, allocator);
        return rann;
    }
    pub fn encode(self: RuntimeInvisibleAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.annotations.len)));
        for (self.annotations) |a| try a.encodeAnnotation(out);
    }
    pub fn deinit(self: RuntimeInvisibleAnnotations, allocator: Allocator) void {
        for (self.annotations) |a| a.deinitAnnotation(allocator);
        allocator.free(self.annotations);
    }
};
pub const RuntimeVisibleAnnotations = struct {
    pub const name = "RuntimeVisibleAnnotations";
    tag: u16,
    len: u32,
    annotations: []Annotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeVisibleAnnotations {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var rann = RuntimeVisibleAnnotations{ .tag = tag, .len = len, .annotations = try allocator.alloc(Annotation, leng) };
        for (rann.annotations) |*a| a.* = try Annotation.findAnnotation(reader, allocator);
        return rann;
    }
    pub fn encode(self: RuntimeVisibleAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.annotations.len)));
        for (self.annotations) |a| try a.encodeAnnotation(out);
    }
    pub fn deinit(self: RuntimeVisibleAnnotations, allocator: Allocator) void {
        for (self.annotations) |a| a.deinitAnnotation(allocator);
        allocator.free(self.annotations);
    }
};
pub const RuntimeVisibleParameterAnnotations = struct {
    pub const name = "RuntimeVisibleParameterAnnotations";
    tag: u16,
    len: u32,
    parameters: []ParameterAnnotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeVisibleParameterAnnotations {
        _ = cpool;
        var leng = @as(u16, try reader.readByte());
        var rpa = RuntimeVisibleParameterAnnotations{ .tag = tag, .len = len, .parameters = try allocator.alloc(ParameterAnnotation, leng) };
        for (rpa.parameters) |*p| {
            leng = try reader.readIntBig(u16);
            p.annotations = try allocator.alloc(Annotation, leng);
            for (p.annotations) |*a| a.* = try Annotation.findAnnotation(reader, allocator);
        }
        return rpa;
    }
    pub fn encode(self: RuntimeVisibleParameterAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeByte(@as(u8, @intCast(self.parameters.len)));
        for (self.parameters) |p| {
            try out.writeIntBig(u16, @as(u16, @intCast(p.annotations.len)));
            for (p.annotations) |a| try a.encodeAnnotation(out);
        }
    }
    pub fn deinit(self: RuntimeVisibleParameterAnnotations, allocator: Allocator) void {
        for (self.parameters) |*p| {
            for (p.annotations) |a| a.deinitAnnotation(allocator);
        }
        allocator.free(self.parameters);
    }
};
pub const RuntimeInvisibleParameterAnnotations = struct {
    pub const name = "RuntimeInvisibleParameterAnnotations";
    tag: u16,
    len: u32,
    parameters: []ParameterAnnotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeInvisibleParameterAnnotations {
        _ = cpool;
        var leng = @as(u16, try reader.readByte());
        var rpa = RuntimeInvisibleParameterAnnotations{ .tag = tag, .len = len, .parameters = try allocator.alloc(ParameterAnnotation, leng) };
        for (rpa.parameters) |*p| {
            leng = try reader.readIntBig(u16);
            p.annotations = try allocator.alloc(Annotation, leng);
            for (p.annotations) |*a| a.* = try Annotation.findAnnotation(reader, allocator);
        }
        return rpa;
    }
    pub fn encode(self: RuntimeInvisibleParameterAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.parameters.len)));
        for (self.parameters) |p| {
            try out.writeIntBig(u16, @as(u16, @intCast(p.annotations.len)));
            for (p.annotations) |a| try a.encodeAnnotation(out);
        }
    }
    pub fn deinit(self: RuntimeInvisibleParameterAnnotations, allocator: Allocator) void {
        for (self.parameters) |*p| {
            for (p.annotations) |a| a.deinitAnnotation(allocator);
        }
        allocator.free(self.parameters);
    }
};
pub const AnnotationDefault = struct {
    pub const name = "AnnotationDefault";
    tag: u16,
    len: u32,
    default_value: ElementValue,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !AnnotationDefault {
        _ = cpool;
        return AnnotationDefault{ .tag = tag, .len = len, .default_value = try ElementValue.getValue(reader, allocator) };
    }
    pub fn encode(self: AnnotationDefault, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try self.default_value.encodeValue(out);
    }
    pub fn deinit(self: AnnotationDefault, allocator: Allocator) void {
        self.default_value.deinitValue(allocator);
    }
};
pub const BootstrapMethods = struct {
    pub const name = "BootstrapMethods";
    tag: u16,
    len: u32,
    bootstrap_methods: []BootstrapMethod,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !BootstrapMethods {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var bsm = BootstrapMethods{ .tag = tag, .len = len, .bootstrap_methods = try allocator.alloc(BootstrapMethod, leng) };
        for (bsm.bootstrap_methods) |*bm| {
            bm.bootstrap_method_ref = try reader.readIntBig(u16);
            leng = try reader.readIntBig(u16);
            bm.bootstrap_arguments = try allocator.alloc(u16, leng);
            for (bm.bootstrap_arguments) |*a| a.* = try reader.readIntBig(u16);
        }
        return bsm;
    }
    pub fn encode(self: BootstrapMethods, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.bootstrap_methods.len)));
        for (self.bootstrap_methods) |bsm| {
            try out.writeIntBig(u16, bsm.bootstrap_method_ref);
            try out.writeIntBig(u16, @as(u16, @intCast(bsm.bootstrap_arguments.len)));
            for (bsm.bootstrap_arguments) |b| try out.writeIntBig(u16, b);
        }
    }
    pub fn deinit(self: BootstrapMethods, allocator: Allocator) void {
        for (self.bootstrap_methods) |bsm| allocator.free(bsm.bootstrap_arguments);
        allocator.free(self.bootstrap_methods);
    }
    pub const BootstrapMethod = struct { bootstrap_method_ref: u16, bootstrap_arguments: []u16 };
};
pub const RuntimeVisibleTypeAnnotations = struct {
    pub const name = "RuntimeVisibleTypeAnnotations";
    tag: u16,
    len: u32,
    type_annotations: []TypeAnnotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeVisibleTypeAnnotations {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var rta = RuntimeVisibleTypeAnnotations{ .tag = tag, .len = len, .type_annotations = try allocator.alloc(TypeAnnotation, leng) };
        for (rta.type_annotations) |*ta| ta.* = try TypeAnnotation.getTypeAnnotation(reader, allocator);
        return rta;
    }
    pub fn encode(self: RuntimeVisibleTypeAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.type_annotations.len)));
        for (self.type_annotations) |a| try a.encodeTypeAnnotation(out);
    }
    pub fn deinit(self: RuntimeVisibleTypeAnnotations, allocator: Allocator) void {
        for (self.type_annotations) |ta| ta.freeTypeAnnotation(allocator);
        allocator.free(self.type_annotations);
    }
};
pub const RuntimeInvisibleTypeAnnotations = struct {
    pub const name = "RuntimeInvisibleTypeAnnotations";
    tag: u16,
    len: u32,
    type_annotations: []TypeAnnotation,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !RuntimeInvisibleTypeAnnotations {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var rta = RuntimeInvisibleTypeAnnotations{ .tag = tag, .len = len, .type_annotations = try allocator.alloc(TypeAnnotation, leng) };
        for (rta.type_annotations) |*ta| ta.* = try TypeAnnotation.getTypeAnnotation(reader, allocator);
        return rta;
    }
    pub fn encode(self: RuntimeInvisibleTypeAnnotations, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.type_annotations.len)));
        for (self.type_annotations) |a| try a.encodeTypeAnnotation(out);
    }
    pub fn deinit(self: RuntimeInvisibleTypeAnnotations, allocator: Allocator) void {
        for (self.type_annotations) |ta| ta.freeTypeAnnotation(allocator);
        allocator.free(self.type_annotations);
    }
};
pub const MethodParameters = struct {
    pub const name = "MethodParameters";
    tag: u16,
    len: u32,
    parameters: []Parameter,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !MethodParameters {
        _ = cpool;
        var leng = try reader.readByte();
        var mp = MethodParameters{ .tag = tag, .len = len, .parameters = try allocator.alloc(Parameter, leng) };
        for (mp.parameters) |*p| {
            p.name_idx = try reader.readIntBig(u16);
            p.access_flags = @bitCast(try reader.readIntBig(u16));
        }
        return mp;
    }
    pub fn encode(self: MethodParameters, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.parameters.len)));
        for (self.parameters) |p| {
            try out.writeIntBig(u16, p.name_idx);
            try out.writeIntBig(u16, @as(u16, @bitCast(p.access_flags)));
        }
    }
    pub fn deinit(self: MethodParameters, allocator: Allocator) void {
        allocator.free(self.parameters);
    }
    pub const Parameter = struct {
        name_idx: u16,
        access_flags: AccessFlags,
        pub const AccessFlags = packed struct(u16) { _p0: u4 = 0, final: bool = false, _p1: u7 = 0, synthetic: bool = false, _p2: u2 = 0, mandated: bool = false };
    };
};
pub const Module = struct {
    pub const name = "Module";
    tag: u16,
    len: u32,
    module_name_idx: u16,
    module_flags: Flags,
    module_version_idx: u16,
    requires: []Require = undefined,
    exports: []Export = undefined,
    opens: []Open = undefined,
    uses: []u16 = undefined,
    provides: []Provide = undefined,

    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !Module {
        _ = cpool;
        var m = Module{
            .tag = tag,
            .len = len,
            .module_name_idx = try reader.readIntBig(u16),
            .module_flags = @bitCast(try reader.readIntBig(u16)),
            .module_version_idx = try reader.readIntBig(u16),
        };
        var leng = try reader.readIntBig(u16);
        m.requires = try allocator.alloc(Require, leng);
        for (m.requires) |*r| {
            r.idx = try reader.readIntBig(u16);
            r.flags = try reader.readIntBig(u16);
            r.version = try reader.readIntBig(u16);
        }
        leng = try reader.readIntBig(u16);
        m.exports = try allocator.alloc(Export, leng);
        for (m.exports) |*e| {
            e.idx = try reader.readIntBig(u16);
            e.flags = try reader.readIntBig(u16);
            leng = try reader.readIntBig(u16);
            e.exports = try allocator.alloc(u16, leng);
            for (e.exports) |*exp| exp.* = try reader.readIntBig(u16);
        }
        leng = try reader.readIntBig(u16);
        m.opens = try allocator.alloc(Open, leng);
        for (m.opens) |*o| {
            o.idx = try reader.readIntBig(u16);
            o.flags = try reader.readIntBig(u16);
            leng = try reader.readIntBig(u16);
            o.opens = try allocator.alloc(u16, leng);
            for (o.opens) |*op| op.* = try reader.readIntBig(u16);
        }
        leng = try reader.readIntBig(u16);
        m.uses = try allocator.alloc(u16, leng);
        for (m.uses) |*u| u.* = try reader.readIntBig(u16);
        leng = try reader.readIntBig(u16);
        m.provides = try allocator.alloc(Provide, leng);
        for (m.provides) |*p| {
            p.idx = try reader.readIntBig(u16);
            leng = try reader.readIntBig(u16);
            p.provides = try allocator.alloc(u16, leng);
            for (p.provides) |*pr| pr.* = try reader.readIntBig(u16);
        }
        return m;
    }
    pub fn encode(self: Module, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, self.module_name_idx);
        try out.writeIntBig(u16, @as(u16, @bitCast(self.module_flags)));
        try out.writeIntBig(u16, self.module_version_idx);
        try out.writeIntBig(u16, @as(u16, @intCast(self.requires.len)));
        for (self.requires) |r| {
            try out.writeIntBig(u16, r.idx);
            try out.writeIntBig(u16, r.flags);
            try out.writeIntBig(u16, r.version);
        }
        try out.writeIntBig(u16, @as(u16, @intCast(self.exports.len)));
        for (self.exports) |e| {
            try out.writeIntBig(u16, e.idx);
            try out.writeIntBig(u16, e.flags);
            try out.writeIntBig(u16, @as(u16, @intCast(e.exports.len)));
            for (e.exports) |ex| try out.writeIntBig(u16, ex);
        }
        try out.writeIntBig(u16, @as(u16, @intCast(self.opens.len)));
        for (self.opens) |o| {
            try out.writeIntBig(u16, o.idx);
            try out.writeIntBig(u16, o.flags);
            try out.writeIntBig(u16, @as(u16, @intCast(o.opens.len)));
            for (o.opens) |op| try out.writeIntBig(u16, op);
        }
        try out.writeIntBig(u16, @as(u16, @intCast(self.uses.len)));
        for (self.uses) |u| try out.writeIntBig(u16, u);
        try out.writeIntBig(u16, @as(u16, @intCast(self.provides.len)));
        for (self.provides) |p| {
            try out.writeIntBig(u16, p.idx);
            try out.writeIntBig(u16, @as(u16, @intCast(p.provides.len)));
            for (p.provides) |pr| try out.writeIntBig(u16, pr);
        }
    }
    pub fn deinit(self: Module, allocator: Allocator) void {
        allocator.free(self.requires);
        for (self.exports) |e| allocator.free(e.exports);
        allocator.free(self.exports);
        for (self.opens) |o| allocator.free(o.opens);
        allocator.free(self.opens);
        allocator.free(self.uses);
        for (self.provides) |p| allocator.free(p.provides);
        allocator.free(self.provides);
    }

    pub const Flags = packed struct(u16) { _p0: u5 = 0, open: bool = false, _p1: u6 = 0, synthetic: bool = false, _p2: u2 = 0, mandated: bool = false };
    pub const Require = struct { idx: u16, flags: u16, version: u16 };
    pub const Export = struct { idx: u16, flags: u16, exports: []u16 };
    pub const Open = struct { idx: u16, flags: u16, opens: []u16 };
    pub const Provide = struct { idx: u16, provides: []u16 };
};
pub const ModulePackages = struct {
    pub const name = "ModulePackages";
    tag: u16,
    len: u32,
    packages: []u16,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !ModulePackages {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var mp = ModulePackages{ .tag = tag, .len = len, .packages = try allocator.alloc(u16, leng) };
        for (mp.packages) |*p| p.* = try reader.readIntBig(u16);
        return mp;
    }
    pub fn encode(self: ModulePackages, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.packages.len)));
        for (self.packages) |p| try out.writeIntBig(u16, p);
    }
    pub fn deinit(self: ModulePackages, allocator: Allocator) void {
        allocator.free(self.packages);
    }
};
pub const NestMembers = struct {
    pub const name = "NestMembers";
    tag: u16,
    len: u32,
    classes: []u16,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !NestMembers {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var n = NestMembers{ .tag = tag, .len = len, .classes = try allocator.alloc(u16, leng) };
        for (n.classes) |*c| c.* = try reader.readIntBig(u16);
        return n;
    }
    pub fn encode(self: NestMembers, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.classes.len)));
        for (self.classes) |c| try out.writeIntBig(u16, c);
    }
    pub fn deinit(self: NestMembers, allocator: Allocator) void {
        allocator.free(self.classes);
    }
};
pub const Record = struct {
    pub const name = "Record";
    tag: u16,
    len: u32,
    components: []Component,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !Record {
        var leng = try reader.readIntBig(u16);
        var r = Record{ .tag = tag, .len = len, .components = try allocator.alloc(Component, leng) };
        for (r.components) |*c| {
            c.name_idx = try reader.readIntBig(u16);
            c.descriptor_idx = try reader.readIntBig(u16);
            leng = try reader.readIntBig(u16);
            c.attributes = try allocator.alloc(AttributeInfo, leng);
            for (c.attributes) |*a| a.* = try parseAttr(reader, allocator, cpool);
        }
        return r;
    }
    pub fn encode(self: Record, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.components.len)));
        for (self.components) |c| {
            try out.writeIntBig(u16, c.name_idx);
            try out.writeIntBig(u16, c.descriptor_idx);
            try out.writeIntBig(u16, @as(u16, @intCast(c.attributes.len)));
            try encodeAttrs(c.attributes, out);
        }
    }
    pub fn deinit(self: Record, allocator: Allocator) void {
        for (self.components) |c| {
            for (c.attributes) |*a| a.freeAttr(allocator);
            allocator.free(c.attributes);
        }
        allocator.free(self.components);
    }
    pub const Component = struct {
        name_idx: u16,
        descriptor_idx: u16,
        attributes: []AttributeInfo,
    };
};
pub const PermittedSubclasses = struct {
    pub const name = "PermittedSubclasses";
    tag: u16,
    len: u32,
    classes: []u16,
    pub fn decode(reader: Reader, allocator: Allocator, cpool: []CpInfo, len: u32, tag: u16) !PermittedSubclasses {
        _ = cpool;
        var leng = try reader.readIntBig(u16);
        var p = PermittedSubclasses{ .tag = tag, .len = len, .classes = try allocator.alloc(u16, leng) };
        for (p.classes) |*c| c.* = try reader.readIntBig(u16);
        return p;
    }
    pub fn encode(self: PermittedSubclasses, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        try out.writeIntBig(u32, self.len);
        try out.writeIntBig(u16, @as(u16, @intCast(self.classes.len)));
        for (self.classes) |c| try out.writeIntBig(u16, c);
    }
    pub fn deinit(self: PermittedSubclasses, allocator: Allocator) void {
        allocator.free(self.classes);
    }
};

// serialized structs
pub const ConstantValue = struct {
    pub const name = "ConstantValue";
    tag: u16,
    len: u32,
    const_value_idx: u16,
};
pub const EnclosingMethod = struct {
    pub const name = "EnclosingMethod";
    tag: u16,
    len: u32,
    class_idx: u16,
    method_idx: u16,
};
pub const Synthetic = struct {
    pub const name = "Synthetic";
    tag: u16,
    len: u32,
};
pub const Signature = struct {
    pub const name = "Signature";
    tag: u16,
    len: u32,
    signature_idx: u16,
};
pub const SourceFile = struct {
    pub const name = "SourceFile";
    tag: u16,
    len: u32,
    sourcefile_idx: u16,
};
pub const Deprecatred = struct {
    pub const name = "Deprecatred";
    tag: u16,
    len: u32,
};
pub const ModuleMainClass = struct {
    pub const name = "ModuleMainClass";
    tag: u16,
    len: u32,
    main_class_idx: u16,
};
pub const NestHost = struct {
    pub const name = "NestHost";
    tag: u16,
    len: u32,
    host_class_idx: u16,
};

// repeat used structures
pub const Annotation = struct {
    type_idx: u16,
    element_value_pairs: []ElementValuePair = undefined,
    pub fn findAnnotation(reader: Reader, allocator: Allocator) anyerror!Annotation {
        var a = Annotation{ .type_idx = try reader.readIntBig(u16) };
        var len = try reader.readIntBig(u16);
        a.element_value_pairs = try allocator.alloc(ElementValuePair, len);
        for (a.element_value_pairs) |*evp| {
            evp.element_name_idx = try reader.readIntBig(u16);
            evp.value = try ElementValue.getValue(reader, allocator);
        }
        return a;
    }
    pub fn encodeAnnotation(self: Annotation, out: Writer) anyerror!void {
        try out.writeIntBig(u16, self.type_idx);
        try out.writeIntBig(u16, @as(u16, @intCast(self.element_value_pairs.len)));
        for (self.element_value_pairs) |evp| {
            try out.writeIntBig(u16, evp.element_name_idx);
            try evp.value.encodeValue(out);
        }
    }
    pub fn deinitAnnotation(self: Annotation, allocator: Allocator) void {
        for (self.element_value_pairs) |*evp| {
            evp.value.deinitValue(allocator);
        }
    }
};
pub const ParameterAnnotation = struct { annotations: []Annotation };
pub const TypeAnnotation = struct {
    target_type: u8,
    target_info: TargetInfo = undefined,
    target_path: TargetPath = undefined,
    type_idx: u16 = 0,
    element_value_pairs: []ElementValuePair = undefined,
    pub fn getTypeAnnotation(reader: Reader, allocator: Allocator) !TypeAnnotation {
        var ta = TypeAnnotation{ .target_type = try reader.readByte() };
        ta.target_info = try TargetInfo.parseTarget(reader, allocator, ta.target_type);
        ta.target_path = try TargetPath.getPath(reader, allocator);
        ta.type_idx = try reader.readIntBig(u16);
        var len = try reader.readIntBig(u16);
        ta.element_value_pairs = try allocator.alloc(ElementValuePair, len);
        for (ta.element_value_pairs) |*evp| {
            evp.element_name_idx = try reader.readIntBig(u16);
            evp.value = try ElementValue.getValue(reader, allocator);
        }
        return ta;
    }
    pub fn encodeTypeAnnotation(self: TypeAnnotation, out: Writer) !void {
        try out.writeByte(self.target_type);
        switch (self.target_info) {
            .type_parameter => |t| try out.writeByte(t.type_param_idx),
            .super_type => |t| try out.writeIntBig(u16, t.supertype_idx),
            .type_parameter_bound => |t| {
                try out.writeByte(t.type_parameter_idx);
                try out.writeByte(t.bound_idx);
            },
            .formal_parameter => |t| try out.writeByte(t.formal_parameter_idx),
            .throws => |t| try out.writeIntBig(u16, t.throws_type_idx),
            .local_var => |t| {
                try out.writeIntBig(u16, @as(u16, @intCast(t.table.len)));
                for (t.table) |e| {
                    try out.writeIntBig(u16, e.start_pc);
                    try out.writeIntBig(u16, e.length);
                    try out.writeIntBig(u16, e.idx);
                }
            },
            .catcht => |t| try out.writeIntBig(u16, t.exception_table_idx),
            .offset => |t| try out.writeIntBig(u16, t.offset),
            .type_argument => |t| {
                try out.writeIntBig(u16, t.offset);
                try out.writeByte(t.type_argument_idx);
            },
            else => {},
        }
        try out.writeByte(@as(u8, @intCast(self.target_path.path.len)));
        for (self.target_path.path) |p| {
            try out.writeByte(p.type_path_kind);
            try out.writeByte(p.type_argument_idx);
        }
        try out.writeIntBig(u16, self.type_idx);
        try out.writeIntBig(u16, @as(u16, @intCast(self.element_value_pairs.len)));
        for (self.element_value_pairs) |evp| {
            try out.writeIntBig(u16, evp.element_name_idx);
            try evp.value.encodeValue(out);
        }
    }
    pub fn freeTypeAnnotation(self: TypeAnnotation, allocator: Allocator) void {
        self.target_info.deinitTarget(allocator);
        allocator.free(self.target_path.path);
        for (self.element_value_pairs) |*evp| evp.value.deinitValue(allocator);
        allocator.free(self.element_value_pairs);
    }
};
pub const ElementValuePair = struct { element_name_idx: u16, value: ElementValue };
pub const ElementValue = struct {
    tag: u8,
    value: Value = undefined,

    pub const Value = union(enum) {
        const_value_idx: u16,
        element_name_idx: u16,
        class_info_idx: u16,
        enum_const_value: EnumConstValue,
        array_value: ArrayValue,
        annotation_value: Annotation,
    };

    pub fn getValue(reader: Reader, allocator: Allocator) !ElementValue {
        var v = ElementValue{ .tag = try reader.readByte() };
        if (v.tag == 'B' or v.tag == 'C' or v.tag == 'D' or v.tag == 'F' or v.tag == 'I' or v.tag == 'J' or v.tag == 'S' or v.tag == 'Z' or v.tag == 's') {
            v.value.const_value_idx = try reader.readIntBig(u16);
        } else if (v.tag == 'e') {
            v.value.enum_const_value.type_name_idx = try reader.readIntBig(u16);
            v.value.enum_const_value.const_name_idx = try reader.readIntBig(u16);
        } else if (v.tag == 'c') {
            v.value.class_info_idx = try reader.readIntBig(u16);
        } else if (v.tag == '@') {
            v.value.annotation_value = try Annotation.findAnnotation(reader, allocator);
        } else if (v.tag == '[') {
            v.value.array_value.count = try reader.readIntBig(u16);
            v.value.array_value.values = try allocator.alloc(ElementValue, v.value.array_value.count);
            for (v.value.array_value.values) |*val| {
                val.* = try getValue(reader, allocator);
            }
        }
        return v;
    }
    pub fn encodeValue(self: ElementValue, out: Writer) !void {
        try out.writeIntBig(u16, self.tag);
        switch (self.value) {
            .const_value_idx, .element_name_idx, .class_info_idx => |idx| try out.writeIntBig(u16, idx),
            .enum_const_value => |ev| {
                try out.writeIntBig(u16, ev.type_name_idx);
                try out.writeIntBig(u16, ev.const_name_idx);
            },
            .array_value => |av| {
                try out.writeIntBig(u16, @as(u16, @intCast(av.count)));
                for (av.values) |v| try v.encodeValue(out);
            },
            .annotation_value => |v| try v.encodeAnnotation(out),
        }
    }
    pub fn deinitValue(self: ElementValue, allocator: Allocator) void {
        if (self.tag == '@') {
            self.value.annotation_value.deinitAnnotation(allocator);
        } else if (self.tag == '[') {
            for (self.value.array_value.values) |v| v.deinitValue(allocator);
            allocator.free(self.value.array_value.values);
        }
    }

    pub const EnumConstValue = struct { type_name_idx: u16, const_name_idx: u16 };
    pub const ArrayValue = struct { count: u16, values: []ElementValue };
};
pub const TargetInfo = union(enum) {
    type_parameter: TypeParameterTarget,
    super_type: SuperTypeTarget,
    type_parameter_bound: TypeParameterBoundTarget,
    empty: EmptyTarget,
    formal_parameter: FormalParameterTarget,
    throws: ThrowsTarget,
    local_var: LocalVarTarget,
    catcht: CatchTarget,
    offset: OffsetTarget,
    type_argument: TypeArgumentTarget,
    pub fn parseTarget(reader: Reader, allocator: Allocator, tag: u8) !TargetInfo {
        if (tag == 0 or tag == 1) {
            return @unionInit(TargetInfo, "type_parameter", TypeParameterTarget{ .type_param_idx = try reader.readByte() });
        } else if (tag == 16) {
            return @unionInit(TargetInfo, "super_type", SuperTypeTarget{ .supertype_idx = try reader.readIntBig(u16) });
        } else if (tag == 17 or tag == 18) {
            return @unionInit(TargetInfo, "type_parameter_bound", TypeParameterBoundTarget{ .type_parameter_idx = try reader.readByte(), .bound_idx = try reader.readByte() });
        } else if (tag == 19 or tag == 20 or tag == 21) {
            return @unionInit(TargetInfo, "empty", EmptyTarget{});
        } else if (tag == 22) {
            return @unionInit(TargetInfo, "formal_parameter", FormalParameterTarget{ .formal_parameter_idx = try reader.readByte() });
        } else if (tag == 23) {
            return @unionInit(TargetInfo, "throws", ThrowsTarget{ .throws_type_idx = try reader.readIntBig(u16) });
        } else if (tag == 64 or tag == 65) {
            var len = try reader.readIntBig(u16);
            var lvt = LocalVarTarget{ .table = try allocator.alloc(LocalVarTarget.Var, len) };
            for (lvt.table) |*v| {
                v.start_pc = try reader.readIntBig(u16);
                v.length = try reader.readIntBig(u16);
                v.idx = try reader.readIntBig(u16);
            }
            return @unionInit(TargetInfo, "local_var", lvt);
        } else if (tag == 66) {
            return @unionInit(TargetInfo, "catcht", CatchTarget{ .exception_table_idx = try reader.readIntBig(u16) });
        } else if (tag > 66 and tag < 71) {
            return @unionInit(TargetInfo, "offset", OffsetTarget{ .offset = try reader.readIntBig(u16) });
        } else if (tag > 70 and tag < 76) {
            return @unionInit(TargetInfo, "type_argument", TypeArgumentTarget{ .offset = try reader.readIntBig(u16), .type_argument_idx = try reader.readByte() });
        }
        unreachable;
    }
    pub fn deinitTarget(self: TargetInfo, allocator: Allocator) void {
        if (std.meta.activeTag(self) == .local_var) allocator.free(self.local_var.table);
    }
    pub const TypeParameterTarget = struct { type_param_idx: u8 };
    pub const SuperTypeTarget = struct { supertype_idx: u16 };
    pub const TypeParameterBoundTarget = struct { type_parameter_idx: u8, bound_idx: u8 };
    pub const EmptyTarget = struct {};
    pub const FormalParameterTarget = struct { formal_parameter_idx: u8 };
    pub const ThrowsTarget = struct { throws_type_idx: u16 };
    pub const LocalVarTarget = struct {
        table: []Var,
        pub const Var = struct { start_pc: u16, length: u16, idx: u16 };
    };
    pub const CatchTarget = struct { exception_table_idx: u16 };
    pub const OffsetTarget = struct { offset: u16 };
    pub const TypeArgumentTarget = struct { offset: u16, type_argument_idx: u8 };
};
pub const TargetPath = struct {
    path: []Path,
    pub fn getPath(reader: Reader, allocator: Allocator) !TargetPath {
        var len = try reader.readByte();
        var tp = TargetPath{ .path = try allocator.alloc(Path, len) };
        for (tp.path) |*p| {
            p.type_path_kind = try reader.readByte();
            p.type_argument_idx = try reader.readByte();
        }
        return tp;
    }
    pub const Path = struct { type_path_kind: u8, type_argument_idx: u8 };
};
