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

#include "aerynutils.h"

#include <filesystem>
#include <format>

#include "../../logging.h"
#include "../../downloader.h"
#include "../../utils.h"
#include "config.h"

namespace fs = std::filesystem;

namespace ASGenerator
{

std::string downloadIfNecessary(const std::string &fname, const std::string &tempDir, Downloader *downloader)
{
    if (downloader == nullptr)
        downloader = &Downloader::get();

    const auto &conf = Config::get();

    if (!Utils::isRemote(fname))
    {
        return fs::path(fname);
    }

    fs::path effectiveTempDir = tempDir.empty() ? fs::path(conf.getTmpDir()) : fs::path(tempDir);

    if (!fs::exists(effectiveTempDir))
    {
        fs::create_directories(effectiveTempDir);
    }

    fs::path localPath = effectiveTempDir / fs::path(fname).filename();
    downloader->downloadFile(fname, localPath.string());

    return localPath;
}

} // namespace ASGenerator
