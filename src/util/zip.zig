const std = @import("std");
// imported structs
const Allocator = std.mem.Allocator;
const File = std.fs.File;

pub const ZipFile = struct {
    local_entries: []LocalEntry = undefined,
    central_dir: []CentrayDirectoryEntry = undefined,
    zip64_eocd: ?Zip64Eocd = undefined,
    eocd: Eocd = undefined,
    allocator: Allocator,
    pub fn init(allocator: Allocator, bytes: []u8) !ZipFile {
        var zf = ZipFile{ .allocator = allocator };
    }
    pub const LocalEntry = struct {
        pub const SIGN = 0x04034b50;
        version: u16,
        gp_flags: Flags,
        comp_method: Compressor,
        mod_time: DosTime,
        mod_date: DosDate,
        crc32: u32,
        comp_size: u32,
        uncomp_size: u32,
        fname_len: u16,
        ex_field_len: u16,
        fname: []u8,
        ex_field: ExField,
        pub fn init(reader: Reader, allocator: Allocator) !LocalEntry {}

        // _p0 and _p2 contain various proprietary pkware encryption data
        pub const Fields = enum(u16) {};
        pub const ExField = union(Fields) {};
    };
    pub const CentrayDirectoryEntry = struct {
        pub const SIGN = 0x02014b50;
        make_version: u16,
        req_version: u16,
        gp_flags: Flags,
        comp_method: Compressor,
        mod_time: DosTime,
        mod_date: DosDate,
        crc32: u32,
        comp_size: u32,
        ucomp_size: u32,
        fname_len: u16,
        ex_field_len: u16,
        f_comm_len: u16,
        disk_start: u16,
        int_file_attrs: u16,
        ext_file_attrs: u32,
        relative_offset: u32,
        fname: []u8,
        ex_field: ExField,
        file_comment: []u8,
        pub const Fields = enum(u16) {};
        pub const ExField = union(Fields) {};
    };
    pub const Zip64Eocd = struct {
        pub const SIGN = 0x06064b50;
        size: u64,
        make_version: u16,
        req_version: u16,
        disk_num: u32,
        socd_disk_count: u32,
        cd_disk_entry_count: u64,
        cd_entry_count: u64,
        size_of_cd: u64,
        cd_start_offset: u64,
        data_sector: []u8,
    };
    pub const Eocd = struct {
        pub const SIGN = 0x06054b50;
        disk_count: u16,
        socd_disk_count: u16,
        cd_entry_count: u16,
        cd: u16,
        central_dir_size: u32,
        start_disk_num: u32,
        file_comment_len: u16,
        file_comment: []u8,
    };
    pub const Flags = packed struct(u16) { encrypted: bool = false, cop_1: bool = false, cop_2: bool = false, offset_size_crc: bool = false, cop_3: bool = false, patched_data: bool = false, _p0: bool = false, _p1: u4 = 0, lang_encoding: bool = false, _p2: u4 };
    pub const Compressor = enum(u16) { NONE = 0, SHRUNK = 1, REDUCED_F1 = 2, REDUCED_F2 = 3, REDUCED_F3 = 4, REDUCED_F4 = 5, IMPLODE = 6, DEFLATE = 8, DEFALTE64 = 9, PK_IMPLODE = 10, BZIP2 = 12, LZMA = 14, CMPSC = 16, TERSE = 18, LZ77 = 19, ZSTD = 93, MP3 = 94, XZ = 95, JPEG = 96, WAV_PACK = 97, PPMD = 98, AE_X = 99 };
    pub const DosTime = packed struct(u16) { hour: u5 = 0, min: u6 = 0, sec: u5 = 0 };
    pub const DosDate = packed struct(u16) { year: u7 = 0, month: u4 = 0, day: u5 = 0 };
};
