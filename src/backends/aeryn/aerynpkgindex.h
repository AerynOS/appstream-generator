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

#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>

#include <stone.h>

#include "../interfaces.h"
#include "aerynpkg.h"

namespace ASGenerator
{

class AerynPackageIndex : public PackageIndex
{
public:
    explicit AerynPackageIndex(const std::string &dir);

    void release() override;

    std::string getIndexFile(const std::string &suite, const std::string &section, const std::string &arch);

    std::vector<std::shared_ptr<Package>> packagesFor(
        const std::string &suite,
        const std::string &section,
        const std::string &arch,
        bool withLongDescs = true) override;

    std::shared_ptr<Package> packageForFile(
        const std::string &fname,
        const std::string &suite = "",
        const std::string &section = "") override;

    bool hasChanges(
        std::shared_ptr<DataStore> dstore,
        const std::string &suite,
        const std::string &section,
        const std::string &arch) override;

protected:
    virtual std::shared_ptr<AerynPackage> newPackage(
        const std::string &name,
        const std::string &ver,
        const std::string &arch);

private:
    fs::path m_rootDir;
    fs::path m_tmpDir;
    std::unordered_map<std::string, std::vector<std::shared_ptr<Package>>> m_pkgCache;
    std::mutex m_cacheMutex; // Thread safety for cache access
    std::unordered_map<std::string, bool> m_indexChanged;

    std::vector<std::shared_ptr<Package>> loadPackages(
        const std::string &suite,
        const std::string &section,
        const std::string &arch);

    std::shared_ptr<Package> processMetaPayload(
        StonePayload *payload,
        StonePayloadHeader *header,
        const std::string &arch,
        const std::string &suite
    );
};

} // namespace ASGenerator
