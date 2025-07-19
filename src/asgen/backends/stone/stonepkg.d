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

module asgen.backends.stone.stonepkg;

import std.stdio : File;
import std.string : format, strip, endsWith, splitLines, join, split, toStringz;
import std.path : buildNormalizedPath, buildPath, baseName, stripExtension;
import std.array : empty, appender;
import std.file : SpanMode;
import std.file : rmdirRecurse, mkdirRecurse;
import std.typecons : Nullable;
import std.conv : to;
import std.algorithm : map;
import std.utf : toUTF8;
import std.algorithm : startsWith;
static import std.file;

import asgen.zarchive;

import asgen.config;
import asgen.logging;
import asgen.backends.interfaces;
import asgen.backends.stone.stonebindings;
import asgen.downloader : Downloader;
import asgen.utils : isRemote;

/**
 * Representation of a Stone package
 */
class StonePackage : Package
{
private:
    string pkgname;
    string pkgver;
    string pkgarch;
    string pkgmaintainer;
    string pkgSummary;
    string pkgDescription;
    string pkgHomepage;
    string pkgLicense;
    string pkgSourceId;

    bool contentsRead;
    string[] contentsL;

    string tmpDir;
    string stoneFname;
    string localStoneFname;

    StoneReader* reader;
    bool readerOpen;
    File stoneFile;

    ArchiveDecompressor archive;

    bool metadataRead;
    StonePayloadMetaRecord[] metaRecords;
    StonePayloadLayoutRecord[] layoutRecords;

public:
    final @property override string name() const
    {
        return pkgname;
    }

    final @property override string ver() const
    {
        return pkgver;
    }

    final @property override string arch() const
    {
        return pkgarch;
    }

    final @property void name(string s)
    {
        pkgname = s;
    }

    final @property void ver(string s)
    {
        pkgver = s;
    }

    final @property void arch(string s)
    {
        pkgarch = s;
    }

    final @property override const(string[string]) description() const
    {
        if (pkgDescription.empty)
            return (string[string]).init;
        return ["C": pkgDescription];
    }

    final @property override const(string[string]) summary() const
    {
        if (pkgSummary.empty)
            return (string[string]).init;
        return ["C": pkgSummary];
    }

    final @property void filename(string fname)
    {
        stoneFname = fname;
        localStoneFname = null;
    }

    override final
    string getFilename()
    {
        if (!localStoneFname.empty)
            return localStoneFname;

        if (stoneFname.isRemote)
        {
            synchronized (this)
            {
                // Double-check pattern to avoid race conditions
                if (!localStoneFname.empty)
                    return localStoneFname;

                auto dl = Downloader.get;

                // Ensure the temporary directory exists
                if (!std.file.exists(tmpDir))
                    mkdirRecurse(tmpDir);

                // Make filename unique by including package name/version to avoid conflicts
                immutable uniqueFilename = format("%s-%s-%s_%s", name, ver, arch, stoneFname
                        .baseName);
                immutable path = buildNormalizedPath(tmpDir, uniqueFilename);

                dl.downloadFile(stoneFname, path);
                localStoneFname = path;
                return localStoneFname;
            }
        }
        else
        {
            localStoneFname = stoneFname;
            return stoneFname;
        }
    }

    override
    final @property string maintainer() const
    {
        return pkgmaintainer;
    }

    final @property void maintainer(string maint)
    {
        pkgmaintainer = maint;
    }

    final @property void summary(string s)
    {
        pkgSummary = s;
    }

    final @property void description(string d)
    {
        pkgDescription = d;
    }

    final @property void homepage(string h)
    {
        pkgHomepage = h;
    }

    final @property void license(string l)
    {
        pkgLicense = l;
    }

    final @property void sourceId(string sid)
    {
        pkgSourceId = sid;
    }

    this(string pname, string pver, string parch)
    {
        pkgname = pname;
        pkgver = pver;
        pkgarch = parch;

        contentsRead = false;
        metadataRead = false;
        readerOpen = false;

        updateTmpDirPath();
    }

    ~this()
    {
        // Clean up in destructor
        finish();
    }

    final void updateTmpDirPath()
    {
        auto conf = Config.get();
        tmpDir = buildPath(conf.getTmpDir(), format("%s-%s_%s", name, ver, arch));
    }

    private void ensureReaderOpen()
    {
        if (readerOpen)
            return;

        synchronized (this)
        {
            if (readerOpen)
                return;

            auto fileName = getFilename();
            try
            {
                stoneFile = File(fileName, "rb");
            }
            catch (Exception e)
            {
                throw new Exception("Failed to open stone package file: " ~ fileName ~ " - " ~ e
                        .msg);
            }

            StoneReadVTable vtable;
            vtable.read = &readShim;
            vtable.seek = &seekShim;

            StoneHeaderVersion version_;
            if (stone_read(&stoneFile, vtable, &reader, &version_) != 0)
            {
                if (stoneFile.isOpen())
                    stoneFile.close();
                throw new Exception("Failed to read stone package file: " ~ fileName);
            }
            readerOpen = true;
        }
    }

    private void readMetadata()
    {
        if (metadataRead)
            return;

        synchronized (this)
        {
            if (metadataRead)
                return;

            ensureReaderOpen();

            StoneHeaderV1 header;
            if (stone_reader_header_v1(reader, &header) != 0)
            {
                throw new Exception("Failed to read stone header");
            }

            // Process payloads to extract metadata
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

                switch (payloadHeader.kind)
                {
                case StonePayloadKind.STONE_PAYLOAD_KIND_META:
                    processMetaPayload(payload, &payloadHeader);
                    break;
                case StonePayloadKind.STONE_PAYLOAD_KIND_LAYOUT:
                    processLayoutPayload(payload, &payloadHeader);
                    break;
                default:
                    // Skip other payload types for now
                    break;
                }

                stone_payload_destroy(payload);
                currentPayload++;
            }

            metadataRead = true;
        }
    }

    private void processMetaPayload(StonePayload* payload, StonePayloadHeader* header)
    {
        for (int i = 0; i < header.num_records; i++)
        {
            StonePayloadMetaRecord record;
            if (stone_payload_next_meta_record(payload, &record) < 0)
                break;

            metaRecords ~= record;

            // Extract key metadata fields using enum values
            switch (record.tag)
            {
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_NAME:
                pkgname = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_VERSION:
                pkgver = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_ARCHITECTURE:
                pkgarch = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_SUMMARY:
                pkgSummary = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_DESCRIPTION:
                pkgDescription = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_HOMEPAGE:
                pkgHomepage = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_LICENSE:
                pkgLicense = stoneStringToD(record.primitive_payload.string);
                break;
            case StonePayloadMetaTag.STONE_PAYLOAD_META_TAG_SOURCE_ID:
                pkgSourceId = stoneStringToD(record.primitive_payload.string);
                break;
            default:
                // Ignore other fields for now
                break;
            }
        }
    }

    private void processLayoutPayload(StonePayload* payload, StonePayloadHeader* header)
    {
        for (int i = 0; i < header.num_records; i++)
        {
            StonePayloadLayoutRecord record;
            if (stone_payload_next_layout_record(payload, &record) < 0)
                break;

            layoutRecords ~= record;
        }
    }

    override final
    const(ubyte)[] getFileData(string fname)
    {
        synchronized (this)
        {
            if (!archive.isOpen)
            {
                archive.open(this.getFilename);
            }
            return archive.readData(fname);
        }
    }

    @property override final
    string[] contents()
    {
        //if (contentsRead)
        //    return contentsL;

        if (!this.contentsL.empty)
            return this.contentsL;

        synchronized (this)
        {
            try
            {
                if (!archive.isOpen)
                {
                    //archive.open(this.getFilename); huh?
                    archive.open(getFilename());
                }
                //contentsL = archive.readContents();
                this.contentsL = archive.readContents();
                contentsRead = true;
            }
            catch (Exception e)
            {
                logError("Failed to read contents from stone package %s: %s", name, e.msg);
            }
        }
        return contentsL;
    }

    @property
    void contents(string[] c)
    {
        contentsL = c;
    }

    override final
    void cleanupTemp()
    {
        synchronized (this)
        {
            if (stoneFile.isOpen)
            {
                stoneFile.close();
            }

            if (archive.isOpen)
            {
                archive.close();
            }

            try
            {
                if (std.file.exists(tmpDir))
                {
                    /* Whenever we delete the temporary directory, we need to
                     * forget about the local file too, since (if it's remote) that
                     * was downloaded into there. */
                    logDebug("Deleting temporary directory %s", tmpDir);
                    localStoneFname = null;
                    //rmdirRecurse(tmpDir);
                }
            }
            catch (Exception e)
            {
                // we ignore any error
                logDebug("Unable to remove temporary directory: %s (%s)", tmpDir, e.msg);
            }

            if (readerOpen && reader !is null)
            {
                stone_reader_destroy(reader);
                reader = null;
                readerOpen = false;
            }
        }
    }

    override final
    void finish()
    {
        cleanupTemp();
    }
}
