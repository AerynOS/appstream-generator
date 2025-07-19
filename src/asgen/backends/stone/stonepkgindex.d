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

module asgen.backends.stone.stonepkgindex;

import std.stdio;
import std.path;
import std.string;
import std.algorithm : remove;
import std.array : appender, array;
import std.conv : to;
import std.typecons : scoped;
import std.format : format;
import std.algorithm : startsWith;
static import std.file;

import asgen.logging;
import asgen.backends.interfaces;
import asgen.backends.stone.stonepkg;
import asgen.backends.stone.stonebindings;
import asgen.config;
import asgen.utils : isRemote;

class StonePackageIndex : PackageIndex
{
private:
    string rootDir;
    Package[][string] pkgCache;
    bool[string] indexChanged;

protected:
    string tmpDir;

public:
    this(string dir)
    {
        pkgCache.clear();
        this.rootDir = dir;
        if (!dir.isRemote && !std.file.exists(dir))
            throw new Exception("Directory '%s' does not exist.".format(dir));

        auto conf = Config.get();
        tmpDir = buildPath(conf.getTmpDir, dir.baseName);
    }

    void release()
    {
        pkgCache.clear();
        indexChanged = null;
    }

    private string getIndexFile(string suite, string section, string arch)
    {
        // For stone repositories, we expect stone.index in the arch directory
        return buildPath(rootDir, arch, "stone.index");
    }

    protected StonePackage newPackage(string name, string ver, string arch)
    {
        return new StonePackage(name, ver, arch);
    }

    private StonePackage[] loadPackages(string suite, string section, string arch, bool withLongDescs = true)
    {
        auto indexFname = getIndexFile(suite, section, arch);
        if (!std.file.exists(indexFname))
        {
            logWarning("Stone package index file '%s' does not exist.", indexFname);
            return [];
        }

        logDebug("Opening stone index: %s", indexFname);

        File file;
        try {
            file = File(indexFname, "rb");
        } catch (Exception e) {
            logError("Failed to open stone index file: %s - %s", indexFname, e.msg);
            return [];
        }

        StoneReader* reader;
        StoneHeaderVersion version_;

        StoneReadVTable vtable;
        vtable.read = &readShim;
        vtable.seek = &seekShim;

        if (stone_read(&file, vtable, &reader, &version_) != 0)
        {
            logError("Failed to read stone index file: %s", indexFname);
            file.close();
            return [];
        }

        scope(exit)
        {
            if (reader !is null)
                stone_reader_destroy(reader);
            if (file.isOpen())
                file.close();
        }

        StoneHeaderV1 header;
        if (stone_reader_header_v1(reader, &header) != 0)
        {
            logError("Failed to read stone header from: %s", indexFname);
            return [];
        }

        StonePackage[string] pkgs;

        // Process each payload (each represents a package)
        int currentPayload = 0;
        while (currentPayload < header.num_payloads)
        {
            StonePayload* payload;
            if (stone_reader_next_payload(reader, &payload) < 0)
                break;

            StonePayloadHeader payloadHeader;
            if (stone_payload_header(payload, &payloadHeader) != 0)
            {
                logWarning("Failed to read payload header, skipping");
                stone_payload_destroy(payload);
                currentPayload++;
                continue;
            }

            // Only process meta payloads for package information
            if (payloadHeader.kind == StonePayloadKind.STONE_PAYLOAD_KIND_META)
            {
                auto pkg = processMetaPayload(payload, &payloadHeader, arch);
                if (pkg !is null && pkg.isValid())
                {
                    // Filter out duplicate packages, keeping the most recent version
                    auto epkg = pkgs.get(pkg.name, null);
                    if (epkg !is null)
                    {
                        // Simple version comparison - in reality you'd want proper version comparison
                        if (epkg.ver >= pkg.ver)
                        {
                            stone_payload_destroy(payload);
                            currentPayload++;
                            continue;
                        }
                    }

                    pkgs[pkg.name] = pkg;
                }
            }

            stone_payload_destroy(payload);
            currentPayload++;
        }

        return array(pkgs.byValue);
    }

    private StonePackage processMetaPayload(StonePayload* payload, StonePayloadHeader* header, string arch)
    {
        auto pkg = newPackage("", "", arch);
        string packageUri = "";

        for (int i = 0; i < header.num_records; i++)
        {
            StonePayloadMetaRecord record;
            if (stone_payload_next_meta_record(payload, &record) < 0)
                break;

            // Extract key metadata fields using enum values
            switch (record.tag)
            {
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_NAME:
                pkg.name = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_VERSION:
                pkg.ver = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_ARCHITECTURE:
                pkg.arch = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_SUMMARY:
                pkg.summary = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_DESCRIPTION:
                pkg.description = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_HOMEPAGE:
                pkg.homepage = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_LICENSE:
                pkg.license = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_SOURCE_ID:
                pkg.sourceId = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_PACKAGE_URI:
                packageUri = stoneStringToD(record.primitive_payload.string);
                break;
            default:
                // Ignore other fields for now
                break;
            }
        }

        // Set the package filename based on the package URI
        if (!packageUri.empty)
        {
            auto fullPath = buildPath(rootDir, arch, packageUri);
            pkg.filename(fullPath);
        }

        return pkg;
    }



    Package[] packagesFor(string suite, string section, string arch, bool withLongDescs = true)
    {
        immutable id = "%s/%s/%s".format(suite, section, arch);
        if (id !in pkgCache)
        {
            auto pkgs = loadPackages(suite, section, arch, withLongDescs);
            synchronized (this)
                pkgCache[id] = to!(Package[])(pkgs);
        }

        return pkgCache[id];
    }

    Package packageForFile(string fname, string suite = null, string section = null)
    {
        logDebug("Loading single stone package: %s", fname);

        File file;
        try {
            file = File(fname, "rb");
        } catch (Exception e) {
            logError("Failed to open stone package file: %s - %s", fname, e.msg);
            throw new Exception("Unable to open stone package file");
        }

        StoneReader* reader;
        StoneHeaderVersion version_;

        StoneReadVTable vtable;
        vtable.read = &readShim;
        vtable.seek = &seekShim;

        if (stone_read(&file, vtable, &reader, &version_) != 0)
        {
            logError("Failed to read stone package file: %s", fname);
            file.close();
            throw new Exception("Unable to read stone package file");
        }

        scope(exit)
        {
            if (reader !is null)
                stone_reader_destroy(reader);
            if (file.isOpen())
                file.close();
        }

        StoneHeaderV1 header;
        if (stone_reader_header_v1(reader, &header) != 0)
        {
            logError("Failed to read stone header from: %s", fname);
            throw new Exception("Unable to read stone header");
        }

        StonePackage pkg = null;

        // Process payloads to find metadata
        int currentPayload = 0;
        while (currentPayload < header.num_payloads)
        {
            StonePayload* payload;
            if (stone_reader_next_payload(reader, &payload) < 0)
                break;

            StonePayloadHeader payloadHeader;
            if (stone_payload_header(payload, &payloadHeader) != 0)
            {
                logWarning("Failed to read payload header, skipping");
                stone_payload_destroy(payload);
                currentPayload++;
                continue;
            }

            if (payloadHeader.kind == StonePayloadKind.STONE_PAYLOAD_KIND_META)
            {
                pkg = processMetaPayload(payload, &payloadHeader, "");
                if (pkg !is null)
                {
                    pkg.filename = fname;
                    stone_payload_destroy(payload);
                    break;
                }
            }

            stone_payload_destroy(payload);
            currentPayload++;
        }

        if (pkg is null)
            throw new Exception("Unable to read metadata from stone package %s".format(fname));

        if (!pkg.isValid())
            throw new Exception("Invalid stone package metadata in %s".format(fname));

        // ensure we have a meaningful temporary directory name
        pkg.updateTmpDirPath();

        return pkg.to!Package;
    }

    final bool hasChanges(DataStore dstore, string suite, string section, string arch)
    {
        import std.json;
        import std.datetime : SysTime;

        auto indexFname = getIndexFile(suite, section, arch);
        // if the file doesn't exist, we will emit a warning later anyway, so we just ignore this here
        if (!std.file.exists(indexFname))
            return true;

        // check our cache on whether the index had changed
        if (indexFname in indexChanged)
            return indexChanged[indexFname];

        SysTime mtime;
        SysTime atime;
        std.file.getTimes(indexFname, atime, mtime);
        auto currentTime = mtime.toUnixTime();

        auto repoInfo = dstore.getRepoInfo(suite, section, arch);
        scope (exit)
        {
            repoInfo.object["mtime"] = JSONValue(currentTime);
            dstore.setRepoInfo(suite, section, arch, repoInfo);
        }

        if ("mtime" !in repoInfo.object)
        {
            indexChanged[indexFname] = true;
            return true;
        }

        auto pastTime = repoInfo["mtime"].integer;
        if (pastTime != currentTime)
        {
            indexChanged[indexFname] = true;
            return true;
        }

        indexChanged[indexFname] = false;
        return false;
    }
}
