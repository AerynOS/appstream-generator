/*
 * Copyright (C) 2024 Serpent OS Developers
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

module asgen.backends.stone.stonebindings;

import std.string;
import core.stdc.stdint;

// Stone library bindings based on official stone.h
extern (C)
{
    enum StoneHeaderV1FileType : ubyte
    {
        STONE_HEADER_V1_FILE_TYPE_BINARY = 1,
        STONE_HEADER_V1_FILE_TYPE_DELTA = 2,
        STONE_HEADER_V1_FILE_TYPE_REPOSITORY = 3,
        STONE_HEADER_V1_FILE_TYPE_BUILD_MANIFEST = 4,
    }

    enum StoneHeaderVersion : uint
    {
        STONE_HEADER_VERSION_V1 = 1,
    }

    enum StonePayloadCompression : ubyte
    {
        STONE_PAYLOAD_COMPRESSION_NONE = 1,
        STONE_PAYLOAD_COMPRESSION_ZSTD = 2,
    }

    enum StonePayloadKind : ubyte
    {
        STONE_PAYLOAD_KIND_META = 1,
        STONE_PAYLOAD_KIND_CONTENT = 2,
        STONE_PAYLOAD_KIND_LAYOUT = 3,
        STONE_PAYLOAD_KIND_INDEX = 4,
        STONE_PAYLOAD_KIND_ATTRIBUTES = 5,
        STONE_PAYLOAD_KIND_DUMB = 6,
    }

    enum StonePayloadLayoutFileType : ubyte
    {
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_REGULAR = 1,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_SYMLINK = 2,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_DIRECTORY = 3,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_CHARACTER_DEVICE = 4,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_BLOCK_DEVICE = 5,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_FIFO = 6,
        STONE_PAYLOAD_LAYOUT_FILE_TYPE_SOCKET = 7,
    }

    enum StonePayloadMetaDependency : ubyte
    {
        STONE_PAYLOAD_META_DEPENDENCY_PACKAGE_NAME = 0,
        STONE_PAYLOAD_META_DEPENDENCY_SHARED_LIBRARY = 1,
        STONE_PAYLOAD_META_DEPENDENCY_PKG_CONFIG = 2,
        STONE_PAYLOAD_META_DEPENDENCY_INTERPRETER = 3,
        STONE_PAYLOAD_META_DEPENDENCY_C_MAKE = 4,
        STONE_PAYLOAD_META_DEPENDENCY_PYTHON = 5,
        STONE_PAYLOAD_META_DEPENDENCY_BINARY = 6,
        STONE_PAYLOAD_META_DEPENDENCY_SYSTEM_BINARY = 7,
        STONE_PAYLOAD_META_DEPENDENCY_PKG_CONFIG32 = 8,
    }

    enum StonePayloadMetaPrimitiveType : uint
    {
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_INT8 = 0,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_UINT8 = 1,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_INT16 = 2,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_UINT16 = 3,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_INT32 = 4,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_UINT32 = 5,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_INT64 = 6,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_UINT64 = 7,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING = 8,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_DEPENDENCY = 9,
        STONE_PAYLOAD_META_PRIMITIVE_TYPE_PROVIDER = 10,
    }

    enum StonePayloadMetaTag : ushort
    {
        STONE_PAYLOAD_META_TAG_NAME = 1,
        STONE_PAYLOAD_META_TAG_ARCHITECTURE = 2,
        STONE_PAYLOAD_META_TAG_VERSION = 3,
        STONE_PAYLOAD_META_TAG_SUMMARY = 4,
        STONE_PAYLOAD_META_TAG_DESCRIPTION = 5,
        STONE_PAYLOAD_META_TAG_HOMEPAGE = 6,
        STONE_PAYLOAD_META_TAG_SOURCE_ID = 7,
        STONE_PAYLOAD_META_TAG_DEPENDS = 8,
        STONE_PAYLOAD_META_TAG_PROVIDES = 9,
        STONE_PAYLOAD_META_TAG_CONFLICTS = 10,
        STONE_PAYLOAD_META_TAG_RELEASE = 11,
        STONE_PAYLOAD_META_TAG_LICENSE = 12,
        STONE_PAYLOAD_META_TAG_BUILD_RELEASE = 13,
        STONE_PAYLOAD_META_TAG_PACKAGE_URI = 14,
        STONE_PAYLOAD_META_TAG_PACKAGE_HASH = 15,
        STONE_PAYLOAD_META_TAG_PACKAGE_SIZE = 16,
        STONE_PAYLOAD_META_TAG_BUILD_DEPENDS = 17,
        STONE_PAYLOAD_META_TAG_SOURCE_URI = 18,
        STONE_PAYLOAD_META_TAG_SOURCE_PATH = 19,
        STONE_PAYLOAD_META_TAG_SOURCE_REF = 20,
    }

    enum StoneSeekFrom : ubyte
    {
        STONE_SEEK_FROM_START = 0,
        STONE_SEEK_FROM_CURRENT = 1,
        STONE_SEEK_FROM_END = 2,
    }

    struct StoneHeaderV1
    {
        ushort num_payloads;
        StoneHeaderV1FileType file_type;
    }

    struct StonePayloadHeader
    {
        ulong stored_size;
        ulong plain_size;
        ubyte[8] checksum;
        uintptr_t num_records;
        ushort version_;
        StonePayloadKind kind;
        StonePayloadCompression compression;
    }

    struct StoneString
    {
        const(ubyte)* buf;
        size_t size;
    }

    struct StonePayloadLayoutFileRegular
    {
        ubyte[16] hash;
        StoneString name;
    }

    struct StonePayloadLayoutFileSymlink
    {
        StoneString source;
        StoneString target;
    }

    union StonePayloadLayoutFilePayload
    {
        StonePayloadLayoutFileRegular regular;
        StonePayloadLayoutFileSymlink symlink;
        StoneString directory;
        StoneString character_device;
        StoneString block_device;
        StoneString fifo;
        StoneString socket;
    }

    struct StonePayloadLayoutRecord
    {
        uint uid;
        uint gid;
        uint mode;
        uint tag;
        StonePayloadLayoutFileType file_type;
        StonePayloadLayoutFilePayload file_payload;
    }

    struct StonePayloadMetaDependencyValue
    {
        StonePayloadMetaDependency kind;
        StoneString name;
    }

    struct StonePayloadMetaProviderValue
    {
        StonePayloadMetaDependency kind;
        StoneString name;
    }

    union StonePayloadMetaPrimitivePayload
    {
        byte int8;
        ubyte uint8;
        short int16;
        ushort uint16;
        int int32;
        uint uint32;
        long int64;
        ulong uint64;
        StoneString string;
        StonePayloadMetaDependencyValue dependency;
        StonePayloadMetaProviderValue provider;
    }

    struct StonePayloadMetaRecord
    {
        StonePayloadMetaTag tag;
        StonePayloadMetaPrimitiveType primitive_type;
        StonePayloadMetaPrimitivePayload primitive_payload;
    }

    struct StonePayloadIndexRecord
    {
        ulong start;
        ulong end;
        ubyte[16] digest;
    }

    struct StonePayloadAttributeRecord
    {
        uintptr_t key_size;
        const(ubyte)* key_buf;
        uintptr_t value_size;
        const(ubyte)* value_buf;
    }

    struct StoneReadVTable
    {
        extern (C) uintptr_t function(void* data, char* buf, uintptr_t size) read;
        extern (C) int64_t function(void* data, int64_t offset, StoneSeekFrom from) seek;
    }

    // Opaque structs
    struct StoneReader;
    struct StonePayload;
    struct StonePayloadContentReader;

    // Function declarations
    int stone_read(void* data, StoneReadVTable vtable, StoneReader** reader_ptr, StoneHeaderVersion* version_);
    int stone_read_file(int file, StoneReader** reader_ptr, StoneHeaderVersion* version_);
    int stone_read_buf(const(ubyte)* buf, size_t len, StoneReader** reader_ptr, StoneHeaderVersion* version_);
    int stone_reader_header_v1(const(StoneReader)* reader, StoneHeaderV1* header);
    int stone_reader_next_payload(StoneReader* reader, StonePayload** payload_ptr);
    int stone_reader_unpack_content_payload(StoneReader* reader, const(StonePayload)* payload, int file);
    int stone_reader_read_content_payload(StoneReader* reader, const(StonePayload)* payload, StonePayloadContentReader** content_reader);
    void stone_reader_destroy(StoneReader* reader);
    size_t stone_payload_content_reader_read(StonePayloadContentReader* content_reader, ubyte* buf, size_t size);
    int stone_payload_content_reader_buf_hint(const(StonePayloadContentReader)* content_reader, size_t* hint);
    int stone_payload_content_reader_is_checksum_valid(const(StonePayloadContentReader)* content_reader);
    void stone_payload_content_reader_destroy(StonePayloadContentReader* content_reader);
    int stone_payload_header(const(StonePayload)* payload, StonePayloadHeader* header);
    int stone_payload_next_layout_record(StonePayload* payload, StonePayloadLayoutRecord* record);
    int stone_payload_next_meta_record(StonePayload* payload, StonePayloadMetaRecord* record);
    int stone_payload_next_index_record(StonePayload* payload, StonePayloadIndexRecord* record);
    int stone_payload_next_attribute_record(StonePayload* payload, StonePayloadAttributeRecord* record);
    void stone_payload_destroy(StonePayload* payload);
    void stone_format_header_v1_file_type(StoneHeaderV1FileType file_type, ubyte* buf);
    void stone_format_payload_compression(StonePayloadCompression compression, ubyte* buf);
    void stone_format_payload_kind(StonePayloadKind kind, ubyte* buf);
    void stone_format_payload_layout_file_type(StonePayloadLayoutFileType file_type, ubyte* buf);
    void stone_format_payload_meta_tag(StonePayloadMetaTag tag, ubyte* buf);
    void stone_format_payload_meta_dependency(StonePayloadMetaDependency dependency, ubyte* buf);
}

//string stoneStringToD(StoneString str)
//{
//    if (str.buf is null || str.size == 0)
//        return "";
//
//    return fromStringz(cast(const char*) str.buf).idup;
//}

// Helper functions for converting StoneString to D string
string stoneStringToD(StoneString str)
{
    if (str.buf is null || str.size == 0)
        //logError("Fucked up C string %s", str);
        return "";

    auto slice = (cast(const(char)*) str.buf)[0 .. str.size];
    return slice.idup;
}

// C callback functions for Stone reader
extern (C) uintptr_t readShim(void* fptr, char* buf, uintptr_t n)
{
    import std.stdio : File;
    File* file = cast(File*) fptr;
    try {
        auto data = file.rawRead(buf[0 .. n]);
        return data.length;
    } catch (Exception e) {
        return 0;
    }
}

extern (C) int64_t seekShim(void* fptr, int64_t offset, StoneSeekFrom from)
{
    import std.stdio : File, SEEK_SET, SEEK_CUR, SEEK_END;
    File* file = cast(File*) fptr;

    int whence;
    switch (from)
    {
    case StoneSeekFrom.STONE_SEEK_FROM_START:
        whence = SEEK_SET;
        break;
    case StoneSeekFrom.STONE_SEEK_FROM_CURRENT:
        whence = SEEK_CUR;
        break;
    case StoneSeekFrom.STONE_SEEK_FROM_END:
        whence = SEEK_END;
        break;
    default:
        whence = SEEK_SET;
        break;
    }

    try {
        file.seek(offset, whence);
        return file.tell();
    } catch (Exception e) {
        return -1;
    }
}
