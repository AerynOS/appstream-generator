/*
 * Copyright (C) 2025 AerynOS Developers <copyright@aerynos.com>
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

#include "aerynpkgindex.h"
#include "aerynpkg.h"
#include "aerynutils.h"
#include "../../logging.h"
#include "../../config.h"
#include "../../datastore.h"
#include <string>

#include <stone.h>

#include <iostream>
#include <fstream>
#include <chrono>

namespace ASGenerator
{

// Helper to convert StoneString from Stone bindings to std::string
static std::string stone_string_to_cpp(const StoneString *s)
{
    if (s == nullptr || s->buf == nullptr || s->size == 0)
    {
        return "";
    }
    return std::string(reinterpret_cast<const char*>(s->buf), s->size);
}

// Shim for stone_read_fn - matches the StoneReadVTable signature
static uintptr_t read_shim(void *user_data, char *buf, uintptr_t nbyte)
{
    std::ifstream *file = static_cast<std::ifstream *>(user_data);
    if (!file || !file->is_open() || file->eof())
    {
        return 0;
    }

    file->read(buf, nbyte);
    uintptr_t bytes_read = static_cast<uintptr_t>(file->gcount());
    return bytes_read;
}

// Shim for stone_seek_fn - matches the StoneReadVTable signature
static int64_t seek_shim(void *user_data, int64_t offset, StoneSeekFrom whence)
{
    std::ifstream *file = static_cast<std::ifstream *>(user_data);
    if (!file || !file->is_open())
    {
        return -1;
    }

    std::ios_base::seekdir dir;
    switch (whence)
    {
    case STONE_SEEK_FROM_START:
        dir = std::ios_base::beg;
        break;
    case STONE_SEEK_FROM_CURRENT:
        dir = std::ios_base::cur;
        break;
    case STONE_SEEK_FROM_END:
        dir = std::ios_base::end;
        break;
    default:
        logError("Invalid seek whence parameter: %d", static_cast<int>(whence));
        return -1;
    }

    file->seekg(offset, dir);
    if (file->fail())
    {
        return -1;
    }

    return static_cast<int64_t>(file->tellg());
}

AerynPackageIndex::AerynPackageIndex(const std::string &dir)
    : m_rootDir(dir)
{
    if (!Utils::isRemote(dir) && !fs::exists(m_rootDir))
    {
        throw std::runtime_error("Directory '" + dir + "' does not exist.");
    }

    // Initialize tmpDir based on Config::get()->getTmpDir() and baseName of rootDir
    const auto &conf = Config::get();
    m_tmpDir = conf.getTmpDir() / fs::path(dir).filename();
}

void AerynPackageIndex::release()
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    m_pkgCache.clear();
    m_indexChanged.clear();
}

std::string AerynPackageIndex::getIndexFile(const std::string &suite, const std::string &section, const std::string &arch)
{
    // For aeryn repositories, we expect stone.index in the arch directory
    // The section parameter is ignored for stone/aeryn backend
    return (m_rootDir / fs::path(suite) / fs::path(arch) / "stone.index").string();
}

std::shared_ptr<AerynPackage> AerynPackageIndex::newPackage(
    const std::string &name,
    const std::string &ver,
    const std::string &arch)
{
    return std::make_shared<AerynPackage>(name, ver, arch);
}

// Private helper to process a STONE_PAYLOAD_KIND_META payload
std::shared_ptr<Package> AerynPackageIndex::processMetaPayload(StonePayload *payload, StonePayloadHeader *header, const std::string &arch, const std::string &suite)
{
    auto pkg = newPackage("", "", arch);
    std::string pkgFilename = "";
    bool skip_current_package = false;
    std::string version;
    std::string release;

    // Iterate through records in the meta payload
    for (uintptr_t i = 0; i < header->num_records; ++i)
    {
        StonePayloadMetaRecord record;
        int result = stone_payload_next_meta_record(payload, &record);
        if (result < 0)
        {
            logWarning("Failed to read meta record {}", i);
            break;
        }

        //logDebug("record tag: {}, Expected tag kind: {}",
        //         static_cast<unsigned int>(record.tag),
        //         static_cast<unsigned int>(STONE_PAYLOAD_META_TAG_NAME));

        switch (record.tag)
        {
        case STONE_PAYLOAD_META_TAG_NAME:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                auto name = stone_string_to_cpp(&record.primitive_payload.string);
                // Optimization: It is a waste of time to process these packages
                if (name.ends_with("-devel") || name.ends_with("-dbginfo")) {
                    skip_current_package = true;
                    break;
                }
                pkg->setName(name);
            }
            break;
        case STONE_PAYLOAD_META_TAG_VERSION:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                version = stone_string_to_cpp(&record.primitive_payload.string);
                pkg->setVersion(version);
            }
            break;
        case STONE_PAYLOAD_META_TAG_RELEASE:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_UINT64)
            {
                release = std::to_string(record.primitive_payload.uint64);
                if (!pkg->ver().empty()) {
                    pkg->setVersion(version + "-" + release);
                } else {
                    logWarning("got release before version was set, invalid version");
                }
            }
        case STONE_PAYLOAD_META_TAG_ARCHITECTURE:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                pkg->setArch(stone_string_to_cpp(&record.primitive_payload.string));
            }
            break;
        case STONE_PAYLOAD_META_TAG_SUMMARY:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                pkg->setSummary(stone_string_to_cpp(&record.primitive_payload.string), "en");
            }
            break;
        case STONE_PAYLOAD_META_TAG_DESCRIPTION:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                pkg->setDescription(stone_string_to_cpp(&record.primitive_payload.string), "en");
            }
            break;
        case STONE_PAYLOAD_META_TAG_PACKAGE_URI:
            if (record.primitive_type == STONE_PAYLOAD_META_PRIMITIVE_TYPE_STRING)
            {
                // The package URI is relative to rootDir/suite/arch
                pkgFilename = (m_rootDir / fs::path(suite) / fs::path(arch) / fs::path(stone_string_to_cpp(&record.primitive_payload.string))).string();
                pkg->setFilename(pkgFilename);
            }
            break;
        default:
            break;
        }

        if (skip_current_package) {
            break;
        }
    }

    if (skip_current_package) {
        return nullptr;
    }

    // Validate that we have minimum required fields
    if (pkg->name().empty() || pkg->ver().empty())
    {
        logWarning("Incomplete package metadata found (Name or Version missing). Skipping.");
        if (pkg->name().empty()) logError("  - Name is missing");
        if (pkg->ver().empty()) logError("  - Version is missing");
        return nullptr;
    }

    return pkg;
}

std::vector<std::shared_ptr<Package>> AerynPackageIndex::loadPackages(
    const std::string &suite,
    const std::string &section,
    const std::string &arch)
{
    std::string indexFname = getIndexFile(suite, section, arch);
    fs::path localIndexFname;

    //std::lock_guard<std::mutex> lock(m_cacheMutex);
    localIndexFname = downloadIfNecessary(indexFname, m_tmpDir.string());

    if (!fs::exists(localIndexFname))
    {
        logWarning("Aeryn package index file '%s' does not exist.", localIndexFname.string().c_str());
        return {};
    }

    logDebug("Opening aeryn index: {}", localIndexFname.string().c_str());

    std::ifstream file(localIndexFname, std::ios::binary);
    if (!file.is_open())
    {
        logError("Failed to open aeryn index file: %s", localIndexFname.string().c_str());
        return {};
    }

    StoneReader *reader = nullptr;
    StoneHeaderVersion version;

    StoneReadVTable vtable;
    vtable.read = &read_shim;
    vtable.seek = &seek_shim;

    int stone_result = stone_read(&file, vtable, &reader, &version);
    if (stone_result != 0)
    {
        logError("Failed to read aeryn index file: %s (error: %d)", localIndexFname.string().c_str(), stone_result);
        file.close();
        return {};
    }

    if (version != STONE_HEADER_VERSION_V1)
    {
        logError("Unsupported stone format version: %u", static_cast<unsigned>(version));
        stone_reader_destroy(reader);
        file.close();
        return {};
    }

    // Ensure reader is cleaned up on exit
    std::shared_ptr<StoneReader> reader_guard(reader, [](StoneReader *r) {
        if (r)
            stone_reader_destroy(r);
    });

    // File will be closed when it goes out of scope

    StoneHeaderV1 header;
    if (stone_reader_header_v1(reader, &header) != 0)
    {
        logError("Failed to read aeryn header from: %s", localIndexFname.string().c_str());
        return {};
    }

    std::unordered_map<std::string, std::shared_ptr<Package>> pkgs;

    // Process each payload (each represents a package)
    for (int currentPayload = 0; currentPayload < header.num_payloads; ++currentPayload)
    {
        StonePayload *payload = nullptr;
        if (stone_reader_next_payload(reader, &payload) < 0)
        {
            logWarning("Failed to read next payload from aeryn index.");
            break;
        }

        std::shared_ptr<StonePayload> payload_guard(payload, [](StonePayload *p) {
            if (p)
                stone_payload_destroy(p);
        });

        StonePayloadHeader payloadHeader;
        int payload_header_result = stone_payload_header(payload, &payloadHeader);
        if (payload_header_result != 0)
        {
            logWarning("Failed to read payload header (error: {}), skipping", payload_header_result);
            continue;
        }

        //logDebug("Payload kind: {}, Expected meta kind: {}, Num records: {}",
        //         static_cast<unsigned int>(payloadHeader.kind),
        //         static_cast<unsigned int>(STONE_PAYLOAD_KIND_META),
        //         static_cast<unsigned int>(payloadHeader.num_records));

        // Only process meta payloads for package information
        if (payloadHeader.kind == STONE_PAYLOAD_KIND_META)
        {
            auto pkg = processMetaPayload(payload, &payloadHeader, arch, suite);
            if (pkg != nullptr)
            {
                // Filter out duplicate packages, keeping the most recent version
                auto it = pkgs.find(pkg->name());
                if (it != pkgs.end())
                {
                    // Simple version comparison - you might need a more robust version comparison
                    // if semantic versioning is used (e.g., using a dedicated library).
                    if (it->second->ver() >= pkg->ver())
                    {
                        continue;
                    }
                }
                pkgs[pkg->name()] = pkg;
            }
        }
    }

    std::vector<std::shared_ptr<Package>> result_pkgs;
    result_pkgs.reserve(pkgs.size());
    for (const auto &pair : pkgs)
    {
        result_pkgs.push_back(pair.second);
    }
    return result_pkgs;
}

std::vector<std::shared_ptr<Package>> AerynPackageIndex::packagesFor(
    const std::string &suite,
    const std::string &section,
    const std::string &arch,
    bool withLongDescs)
{
    // The section parameter is ignored for stone/aeryn backend
    std::string id = suite + "/" + arch; // Use only suite and arch for the ID

    std::lock_guard<std::mutex> lock(m_cacheMutex);
    if (m_pkgCache.find(id) == m_pkgCache.end())
    {
        m_pkgCache[id] = loadPackages(suite, section, arch);
    }

    return m_pkgCache[id];
}

std::shared_ptr<Package> AerynPackageIndex::packageForFile(
    const std::string &fname,
    const std::string &suite,
    const std::string &section)
{
    logDebug("Loading single aeryn package: {}", fname);

    std::ifstream file(fname, std::ios::binary);
    if (!file.is_open())
    {
        logError("Failed to open aeryn package file: {}", fname);
        throw std::runtime_error("Unable to open aeryn package file");
    }

    StoneReader *reader = nullptr;
    StoneHeaderVersion version;

    StoneReadVTable vtable;
    vtable.read = &read_shim;
    vtable.seek = &seek_shim;

    int stone_result = stone_read(&file, vtable, &reader, &version);
    if (stone_result != 0)
    {
        logError("Failed to read aeryn package file: {}", fname);
        file.close();
        throw std::runtime_error("Unable to read aeryn package file");
    }

    if (version != STONE_HEADER_VERSION_V1)
    {
        logError("Unsupported stone format version: {}", static_cast<unsigned>(version));
        stone_reader_destroy(reader);
        file.close();
        throw std::runtime_error("Unsupported stone format version");
    }

    // Ensure reader is cleaned up on exit
    std::shared_ptr<StoneReader> reader_guard(reader, [](StoneReader *r) {
        if (r)
            stone_reader_destroy(r);
    });

    // File will be closed when it goes out of scope

    StoneHeaderV1 header;
    if (stone_reader_header_v1(reader, &header) != 0)
    {
        logError("Failed to read aeryn header from: {}", fname);
        throw std::runtime_error("Unable to read aeryn header");
    }

    std::shared_ptr<Package> pkg = nullptr;

    // Process payloads to find metadata
    for (int currentPayload = 0; currentPayload < header.num_payloads; ++currentPayload)
    {
        StonePayload *payload = nullptr;
        if (stone_reader_next_payload(reader, &payload) < 0)
        {
            logWarning("Failed to read next payload from aeryn package.");
            break;
        }

        std::shared_ptr<StonePayload> payload_guard(payload, [](StonePayload *p) {
            if (p)
                stone_payload_destroy(p);
        });

        StonePayloadHeader payloadHeader;
        if (stone_payload_header(payload, &payloadHeader) != 0)
        {
            logWarning("Failed to read payload header, skipping");
            continue;
        }

        // Add debug logging for payload kind comparison
        logDebug("Payload kind: {}, Expected meta kind: {}",
                 static_cast<unsigned int>(payloadHeader.kind),
                 static_cast<unsigned int>(STONE_PAYLOAD_KIND_META));

        if (payloadHeader.kind == STONE_PAYLOAD_KIND_META)
        {
            // For a single file, we pass empty suite/arch as they are not relevant to the metadata parsing
            pkg = processMetaPayload(payload, &payloadHeader, "", "");
            logDebug("pkg name {}", pkg->name());
            if (pkg != nullptr)
            {
                // Ensure the package has the correct filename (the one passed to this function)
                auto aeryn_pkg = std::dynamic_pointer_cast<AerynPackage>(pkg);
                if (aeryn_pkg)
                {
                    // Set the filename to the actual file path we're reading from
                    aeryn_pkg->setFilename(fname);
                }
                break; // Found the metadata, no need to process further payloads
            }
        }
    }

    if (pkg == nullptr)
    {
        throw std::runtime_error("Unable to read metadata from aeryn package " + fname);
    }

    return pkg;
}

bool AerynPackageIndex::hasChanges(
    std::shared_ptr<DataStore> dstore,
    const std::string &suite,
    const std::string &section,
    const std::string &arch)
{
    auto indexFname = getIndexFile(suite, section, arch);
    // if the file doesn't exist, we will emit a warning later anyway, so we just ignore this here
    if (!fs::exists(indexFname))
        return true;

    // check our cache on whether the index had changed
    auto cacheIt = m_indexChanged.find(indexFname);
    if (cacheIt != m_indexChanged.end())
        return cacheIt->second;

    const auto mtime = fs::last_write_time(indexFname);
    const auto currentTime = std::chrono::duration_cast<std::chrono::seconds>(mtime.time_since_epoch()).count();

    auto repoInfo = dstore->getRepoInfo(suite, section, arch);

    // Update mtime in repo info when we exit this function
    auto updateRepoInfo = [&]() {
        repoInfo.data["mtime"] = static_cast<std::int64_t>(currentTime);
        dstore->setRepoInfo(suite, section, arch, repoInfo);
    };

    auto mtimeIt = repoInfo.data.find("mtime");
    if (mtimeIt == repoInfo.data.end()) {
        m_indexChanged[indexFname] = true;
        updateRepoInfo();
        return true;
    }

    const auto pastTime = std::get<std::int64_t>(mtimeIt->second);
    if (pastTime != currentTime) {
        m_indexChanged[indexFname] = true;
        updateRepoInfo();
        return true;
    }

    m_indexChanged[indexFname] = false;
    updateRepoInfo();
    return false;
}

} // namespace ASGenerator
