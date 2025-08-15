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

#include "aerynpkg.h"
#include <filesystem>
#include <format>
#include "../../config.h"
#include "../../logging.h"
#include "../../zarchive.h"
#include "../../downloader.h"
#include "../../utils.h"
namespace ASGenerator
{
AerynPackage::AerynPackage(const std::string &pkgname, const std::string &pkgver, const std::string &pkgarch)
    : m_pkgname(pkgname),
    m_pkgver(pkgver),
    m_pkgarch(pkgarch),
    m_archive(std::make_unique<ArchiveDecompressor>())
{
    const auto &conf = Config::get();
    m_tmpDir = conf.getTmpDir() / std::format("{}-{}_{}", name(), ver(), arch());
}
std::string AerynPackage::name() const
{
    return m_pkgname;
}
void AerynPackage::setName(const std::string &val)
{
    m_pkgname = val;
}
std::string AerynPackage::ver() const
{
    return m_pkgver;
}
void AerynPackage::setVersion(const std::string &val)
{
    m_pkgver = val;
}
std::string AerynPackage::arch() const
{
    return m_pkgarch;
}
void AerynPackage::setArch(const std::string &val)
{
    m_pkgarch = val;
}
const std::unordered_map<std::string, std::string> &AerynPackage::description() const
{
    return m_desc;
}
const std::unordered_map<std::string, std::string> &AerynPackage::summary() const
{
    return m_summ;
}

std::string AerynPackage::getFilename()
{
    if (!m_localPkgFname.empty())
        return m_localPkgFname;

    if (Utils::isRemote(m_pkgFname)) {
        const auto &conf = Config::get();
        auto &dl = Downloader::get();
        const fs::path path = conf.getTmpDir()
                              / std::format(
                                  "{}-{}_{}_{}", name(), ver(), arch(), fs::path(m_pkgFname).filename().string());
        dl.downloadFile(m_pkgFname, path);
        m_localPkgFname = path;
        return m_localPkgFname;
    } else {
        m_localPkgFname = m_pkgFname;
        return m_pkgFname;
    }
}

void AerynPackage::setFilename(const std::string &fname)
{
    m_pkgFname = fname;
}

std::string AerynPackage::maintainer() const
{
    return m_pkgmaintainer;
}

void AerynPackage::setMaintainer(const std::string &maint)
{
    m_pkgmaintainer = maint;
}

void AerynPackage::setDescription(const std::string &text, const std::string &locale)
{
    m_desc[locale] = text;
}

void AerynPackage::setSummary(const std::string &text, const std::string &locale)
{
    m_summ[locale] = text;
}

std::vector<std::uint8_t> AerynPackage::getFileData(const std::string &fname)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_archive->isOpen()) {
        const auto pkgFilename = getFilename();
        auto path = Config::get().getTmpDir() / fs::path(pkgFilename).filename();
        logDebug("what {}", path.string());
        m_archive->open(pkgFilename, Config::get().getTmpDir() / fs::path(pkgFilename).filename());
        m_archive->setOptimizeRepeatedReads(true);
    }

    //logDebug("fname {}", fname);

    return m_archive->readData(fname);
}

const std::vector<std::string> &AerynPackage::contents()
{
    if (!m_contentsL.empty())
        return m_contentsL;

    ArchiveDecompressor ad;
    ad.open(getFilename());
    m_contentsL = ad.readContents();

    return m_contentsL;
}

void AerynPackage::setContents(const std::vector<std::string> &c)
{
    m_contentsL = c;
}

void AerynPackage::finish()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_archive->isOpen())
        m_archive->close();

    try {
        if (Utils::isRemote(m_pkgFname) && fs::exists(m_localPkgFname)) {
            fs::remove(m_localPkgFname);
            m_localPkgFname.clear();
        }
    } catch (const std::exception &e) {
        // we ignore any error
        logDebug("Unable to remove temporary package: {} ({})", m_localPkgFname.string(), e.what());
    }
}

} // namespace ASGenerator
