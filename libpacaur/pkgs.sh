#!/usr/bin/env bash
#
#   pkgs.sh -- functions related to operations with packages
#   functions: ClassifyPkgs DownloadPkgs EditPkgs MakePkgs GetIgnoredPkgs
#   GetIgnoredGrps GetBuiltPkg GetPkgBase GetInstallScripts
#

[[ "$LIBPACAUR_PKGS_SH" ]] && return
LIBPACAUR_PKGS_SH=1

LIBPACAUR="${LIBPACAUR:-'/usr/share/pacaur'}"
source "$LIBPACAUR/info.sh"
source "$LIBPACAUR/utils.sh"

# Classify the list of packages passed into repository and AUR packages
# Usage: ClassifyPkgs <package(s)>
ClassifyPkgs() {
    local noaurpkgs norepopkgs
    # global aurpkgs repopkgs
    (( REPO )) && repopkgs=("${pkgs[@]}")
    if (( AUR )); then
        for i in "${pkgs[@]}"; do
            [[ "$i" = aur/* ]] && aurpkgs+=("${i:4}") && continue # search aur/pkgs in AUR
            aurpkgs+=("$i")
        done
    fi
    if (( ! AUR && ! REPO )); then
        unset noaurpkgs
        for i in "${pkgs[@]}"; do
            [[ "$i" = aur/* ]] && aurpkgs+=("${i:4}") && continue # search aur/pkgs in AUR
            noaurpkgs+=("$i")
        done
        [[ "${noaurpkgs[*]}" ]] &&
            IFS=$'\n' mapfile -t < <(LC_ALL=C "$PACMAN" -Sp "${noaurpkgs[@]}" 2>&1 >/dev/null) norepopkgs &&
            norepopkgs=("${norepopkgs[@]#error: target not found: }")
        for i in "${norepopkgs[@]}"; do
            # do not search repo/pkgs in AUR
            [[ " ${noaurpkgs[*]} " =~ [a-zA-Z0-9\.\+-]+\/"$i"[^a-zA-Z0-9\.\+-] ]] || aurpkgs+=("$i")
        done
        repopkgs=($(CommArr 'aurpkgs' 'noaurpkgs' '-13'))
    fi
}

# Download AUR packages into their clone directories. If the directory exists,
# clean it and update the repository
# Usage: DownloadPkgs <package(s)>
DownloadPkgs() {
    local i
    # global basepkgs
    Note "i" $"${WHITE}Retrieving package(s)...${ALL_OFF}"
    GetPkgbase "$@"

    # no results check
    [[ ! "${basepkgs[*]}" ]] && Note "e" $"no results found" "$E_INSTALL_DEPS_FAILED"

    # reset
    for i in "${basepkgs[@]}"; do
        if [[ -d "$clonedir/$i" ]]; then
            git -C "$clonedir/$i" reset --hard HEAD -q # updated pkgver of vcs packages block pull
            [[ "$displaybuildfiles" = diff ]] &&
                git -C "$clonedir/$i" rev-parse HEAD > "$clonedir/$i/.git/HEAD.prev"
        fi
    done

    # clone
    auracle -C "$clonedir" clone "$@" >/dev/null ||
        Note "e" $"failed to retrieve packages" "$E_INSTALL_DEPS_FAILED"
}

# Show PKGBUILD and install scripts of AUR packages
# Usage: EditPkgs <aur package(s)>
EditPkgs() {
    local viewed i j erreditpkg
    # global cachedpkgs installscripts editor
    (( NOEDIT )) && return
    unset viewed
    for i in "$@"; do
        [[ " ${cachedpkgs[*]} " =~ " $i " ]] && continue
        GetInstallScripts "$i"
        if (( ! PACE )); then
            if [[ "$displaybuildfiles" = diff && -e "$clonedir/$i/.git/HEAD.prev" ]]; then
                local prev="$(<"$clonedir/$i/.git/HEAD.prev")"
                # show diff
                if git -C "$clonedir/$i" diff --quiet --no-ext-diff "$prev" -- . ':!\.SRCINFO'; then
                    Note "w" $"${WHITE}$i${ALL_OFF} build files are up-to-date -- skipping"
                else
                    if Proceed "y" $"View $i build files diff?"; then
                        git -C "$clonedir/$i" diff --no-ext-diff "$prev" -- . ':!\.SRCINFO' ||
                            erreditpkg+=("$i")
                        Note "i" $"${WHITE}$i${ALL_OFF} build files diff viewed"; viewed=1
                    fi
                fi
            elif [[ ! "$displaybuildfiles" = none ]]; then
                # show pkgbuild
                if Proceed "y" $"View $i PKGBUILD?"; then
                    if [[ -e "$clonedir/$i/PKGBUILD" ]]; then
                        "$editor" "$clonedir/$i/PKGBUILD" &&
                            Note "i" $"${WHITE}$i${ALL_OFF} PKGBUILD viewed" || erreditpkg+=("$i")
                    else
                        Note "e" $"Could not open ${WHITE}$i${ALL_OFF} PKGBUILD" "$E_MISSING_FILE"
                    fi
                fi
                # show install script
                if [[ "${installscripts[*]}" ]]; then
                    for j in "${installscripts[@]}"; do
                        if Proceed "y" $"View $j script?"; then
                            if [[ -e "$clonedir/$i/$j" ]]; then
                                "$editor" "$clonedir/$i/$j" &&
                                    Note "i" $"${WHITE}$j${ALL_OFF} script viewed" ||
                                    erreditpkg+=("$i")
                            else
                                Note "e" $"Could not open ${WHITE}$j${ALL_OFF} script" "$E_MISSING_FILE"
                            fi
                        fi
                    done
                fi
            fi
        else
            # show pkgbuild and install script
            if [[ -e "$clonedir/$i/PKGBUILD" ]]; then
                "$editor" "$clonedir/$i/PKGBUILD" &&
                    Note "i" $"${WHITE}$i${ALL_OFF} PKGBUILD viewed" || erreditpkg+=("$i")
            else
                Note "e" $"Could not open ${WHITE}$i${ALL_OFF} PKGBUILD" "$E_MISSING_FILE"
            fi
            if [[ "${installscripts[*]}" ]]; then
                for j in "${installscripts[@]}"; do
                    if [[ -e "$clonedir/$i/$j" ]]; then
                        "$editor" "$clonedir/$i/$j" &&
                            Note "i" $"${WHITE}$j${ALL_OFF} script viewed" || erreditpkg+=("$i")
                    else
                        Note "e" $"Could not open ${WHITE}$j${ALL_OFF} script" "$E_MISSING_FILE"
                    fi
                done
            fi
        fi
    done

    if [[ "${erreditpkg[*]}" ]]; then
        for i in "${erreditpkg[@]}"; do
            Note "f" $"${WHITE}$i${ALL_OFF} errored on exit"
        done
        exit "$E_FAIL"
    fi

    if [[ "$displaybuildfiles" = diff && "$viewed" ]]; then
        if (( INSTALLPKG )); then
            Proceed "y" $"Proceed with installation?" || exit
        else
            Proceed "y" $"Proceed with download?" || exit
        fi
    fi
}

# Build and install AUR packages with makepkg
# Usage: MakePkgs
MakePkgs() {
    local i j k oldorphanpkgs neworphanpkgs orphanpkgs oldoptionalpkgs newoptionalpkgs optionalpkgs
    local errinstall pkgsdepslist vcsclients vcschecked aurpkgsAver aurpkgsQver
    local builtpkgs builtdepspkgs basepkgsupdate checkpkgsdepslist deplist isaurdeps makedeps
    # global deps basepkgs sudoloop pkgsbase pkgsdeps aurpkgs aurdepspkgs builtpkg errmakepkg
    # global repoprovidersconflictingpkgs

    # download
    DownloadPkgs "${deps[@]}"
    EditPkgs "${basepkgs[@]}"

    # current orphan and optional packages
    oldorphanpkgs=($("$PACMAN" -Qdtq))
    oldoptionalpkgs=($("$PACMAN" -Qdttq))
    oldoptionalpkgs=($(CommArr 'oldorphanpkgs' 'oldoptionalpkgs' '-13'))

    # initialize sudo
    if sudo -n "$PACMAN" -V > /dev/null || sudo -v; then
        [[ "$sudoloop" = true ]] && SudoV &
    fi

    # split packages support
    for i in "${!pkgsbase[@]}"; do
        for j in "${!deps[@]}"; do
            [[ "${pkgsbase[$i]}" = "${pkgsbase[$j]}" && ! " ${pkgsdeps[*]} " =~ " ${deps[$j]} " ]] &&
                pkgsdeps+=("${deps[$j]}")
        done
        pkgsdeps+=("%")
    done
    deplist="${pkgsdeps[@]}"; deplist="${deplist// % /|}"; deplist="${deplist//%}"
    deplist="${deplist// /,}"; deplist="${deplist//|/ }"; deplist="${deplist%, }"
    pkgsdeps=($(printf '%s\n' ${deplist% ,})); pkgsdeps=("${pkgsdeps[@]%,}")

    # reverse deps order
    for i in "${!basepkgs[@]}"; do
        basepkgsrev[$i]="${basepkgs[-i-1]}"
    done
    basepkgs=("${basepkgsrev[@]}") && unset basepkgsrev
    for i in "${!pkgsdeps[@]}"; do
        pkgsdepsrev[$i]="${pkgsdeps[-i-1]}"
    done
    pkgsdeps=("${pkgsdepsrev[@]}") && unset pkgsdepsrev

    # integrity check
    for i in "${!basepkgs[@]}"; do
        # get split packages list
        read -rd',' -a pkgsdepslist <<< "${pkgsdeps[$i]}"

        # cache check
        unset builtpkg
        if [[ ! "${basepkgs[$i]}" =~ $vcs ]]; then
            for j in "${pkgsdepslist[@]}"; do
                [[ "$PKGDEST" ]] && (( ! REBUILD )) && GetBuiltPkg "$j-$(GetInfo "Version" "$j")" "$PKGDEST"
            done
        fi

        # install vcs clients (checking pkgbase extension only does not take fetching specific
        # commit into account)
        unset vcsclients
        makedeps=($(GetInfo "MakeDepends" "${basepkgs[$i]}"))
        for k in git subversion mercurial bzr cvs darcsl; do
            [[ " ${makedeps[*]} " =~ " $k " ]] && vcsclients+=("$k")
        done
        unset makedeps
        for j in "${vcsclients[@]}"; do
            if [[ ! "${vcschecked[*]}" =~ "$j" ]]; then
                expac -Qs '' "^$j$" || sudo "$PACMAN" -S --asdeps --noconfirm -- "$j"
                vcschecked+=("$j")
            fi
        done

        if [[ ! "$builtpkg" ]] || (( REBUILD )); then
            cd "${clonedir:?}/${basepkgs[$i]}" || exit "$E_MISSING_FILE"
            Note "i" $"Checking ${WHITE}${pkgsdeps[$i]}${ALL_OFF} integrity..."
            if [[ "$silent" = true ]]; then
                makepkg -f --verifysource "${MAKEPKG_OPTS[@]}" &>/dev/null
            else
                makepkg -f --verifysource "${MAKEPKG_OPTS[@]}" >/dev/null
            fi
            (($? > 0)) && errmakepkg+=("${pkgsdeps[$i]}")
            # extraction, prepare and pkgver update
            Note "i" $"Preparing ${WHITE}${pkgsdeps[$i]}${ALL_OFF}..."
            if [[ "$silent" = true ]]; then
                makepkg -od --skipinteg "${MAKEPKG_OPTS[@]}" &>/dev/null
            else
                makepkg -od --skipinteg "${MAKEPKG_OPTS[@]}"
            fi
            (($? > 0)) && errmakepkg+=("${pkgsdeps[$i]}")
        fi
    done
    if [[ "${errmakepkg[*]}" || "${errinstall[*]}" ]]; then
        for i in "${errmakepkg[@]}"; do
            Note "f" $"failed to verify integrity or prepare ${WHITE}$i${ALL_OFF} package"
        done
        # remove sudo lock
        rm -f "${tmpdir:?}/pacaur.sudov.lck"
        exit "$E_FAIL"
    fi

    # check database lock
    [[ -e "/var/lib/pacman/db.lck" ]] && Note "e" $"db.lck exists in /var/lib/pacman" "$E_FAIL"

    # set build lock
    [[ -e "$tmpdir/pacaur.build.lck" ]] && Note "e" $"pacaur.build.lck exists in $tmpdir" "$E_FAIL"
    > "$tmpdir/pacaur.build.lck"

    # install provider packages and repo conflicting packages that makepkg --noconfirm cannot handle
    if [[ "${repoprovidersconflictingpkgs[*]}" ]]; then
        Note "i" $"Installing ${WHITE}${repoprovidersconflictingpkgs[@]}${ALL_OFF} dependencies..."
        sudo "$PACMAN" -S ${repoprovidersconflictingpkgs[@]} --ask 36 --asdeps --noconfirm
    fi

    # main
    for i in "${!basepkgs[@]}"; do
        # get split packages list
        read -rd',' -a pkgsdepslist <<< "${pkgsdeps[$i]}"

        cd "$clonedir/${basepkgs[$i]}" || exit "$E_MISSING_FILE"
        # retrieve updated version
        mapfile -d'-' -t < <(makepkg --packagelist) k && aurpkgsAver="${k[-3]}-${k[-2]}"; unset k
        # build devel if necessary only (supported protocols only)
        if [[ "${basepkgs[$i]}" =~ $vcs ]]; then
            # check split packages update
            unset basepkgsupdate checkpkgsdepslist
            for j in "${pkgsdepslist[@]}"; do
                read -rd' ' < <(expac -Qs '%v' "^$j$") aurpkgsQver
                if (( NEEDED && ! REBUILD )) && [[ "$aurpkgsQver" ]] &&
                    (( "$(vercmp "$aurpkgsQver" "$aurpkgsAver")" >= 0 )); then
                    Note "w" $"${WHITE}$j${ALL_OFF} is up-to-date -- skipping" && continue
                else
                    basepkgsupdate='true'; checkpkgsdepslist+=("$j")
                fi
            done
            [[ "$basepkgsupdate" ]] && pkgsdepslist=("${checkpkgsdepslist[@]}") || continue
        fi

        # check package cache
        for j in "${pkgsdepslist[@]}"; do
            unset builtpkg
            [[ "$PKGDEST" ]] && (( ! REBUILD )) && GetBuiltPkg "$j-$aurpkgsAver" "$PKGDEST"
            if [[ "$builtpkg" ]]; then
                if [[ " ${aurdepspkgs[*]} " =~ " $j " ]] || (( INSTALLPKG )); then
                    Note "i" $"Installing ${WHITE}$j${ALL_OFF} cached package..."
                    sudo "$PACMAN" -U --ask 36 ${PACMAN_OPTS[@]/--quiet} --noconfirm -- "$builtpkg"
                    [[ " ${aurpkgs[*]} " =~ " $j " ]] ||
                        sudo "$PACMAN" -D "$j" --asdeps ${PACMAN_OPTS[@]} &>/dev/null
                else
                    Note "w" $"Package ${WHITE}$j${ALL_OFF} already available in cache"
                fi
                pkgsdeps=("${pkgsdeps[@]/#$j,}"); pkgsdeps=("${pkgsdeps[@]/%,$j}")
                pkgsdeps=("${pkgsdeps[@]//,$j,/,}")
                for k in "${!pkgsdeps[@]}"; do
                    [[ "${pkgsdeps[k]}" = "$j" ]] && pkgsdeps[k]='%'
                done
                continue
            fi
        done
        [[ "${pkgsdeps[$i]}" = '%' ]] && continue

        # build
        Note "i" $"Building ${WHITE}${pkgsdeps[$i]}${ALL_OFF} package(s)..."

        # install then remove binary deps
        MAKEPKG_OPTS=("${MAKEPKG_OPTS[@]/-r/}")

        if (( ! INSTALLPKG )); then
            unset isaurdeps
            for j in "${pkgsdepslist[@]}"; do
                [[ " ${aurdepspkgs[*]} " =~ " $j " ]] && isaurdeps=1
            done
            [[ "$isaurdeps" ]] && MAKEPKG_OPTS+=("-r")
        fi

        if [[ "$silent" = true ]]; then
            makepkg -sefc "${MAKEPKG_OPTS[@]}" --noconfirm &>/dev/null
        else
            makepkg -sefc "${MAKEPKG_OPTS[@]}" --noconfirm
        fi

        # error check
        (($? > 0)) && errmakepkg+=("${pkgsdeps[$i]}") && continue # skip install

        # retrieve filename
        unset builtpkgs builtdepspkgs
        for j in "${pkgsdepslist[@]}"; do
            unset builtpkg
            if [[ "$PKGDEST" ]]; then
                GetBuiltPkg "$j-$aurpkgsAver" "$PKGDEST"
            else
                GetBuiltPkg "$j-$aurpkgsAver" "${clonedir:?}/${basepkgs[$i]}"
            fi
            [[ " ${aurdepspkgs[*]} " =~ " $j " ]] && builtdepspkgs+=("$builtpkg") || builtpkgs+=("$builtpkg")
        done

        # install
        if (( INSTALLPKG || ! "${#builtpkgs[*]}" )); then
            Note "i" $"Installing ${WHITE}${pkgsdeps[$i]}${ALL_OFF} package(s)..."
            sudo "$PACMAN" -U ${builtdepspkgs[@]} ${builtpkgs[@]} --ask 36 ${PACMAN_OPTS[@]/--quiet} --noconfirm
        fi

        # set dep status
        if (( INSTALLPKG )); then
            for j in "${pkgsdepslist[@]}"; do
                [[ ! " ${aurpkgs[*]} " =~ " $j " ]] && sudo "$PACMAN" -D "$j" --asdeps &>/dev/null
                (( ASDEPS )) && sudo "$PACMAN" -D "$j" --asdeps &>/dev/null
                (( ASEXPLICIT )) && sudo "$PACMAN" -D "$j" --asexplicit &>/dev/null
            done
        fi
    done

    # remove AUR deps
    if (( ! INSTALLPKG )); then
        [[ "${aurdepspkgs[*]}" ]] && aurdepspkgs=($(expac -Q '%n' "${aurdepspkgs[@]}"))
        [[ "${aurdepspkgs[*]}" ]] && Note "i" $"Removing installed AUR dependencies..." &&
            sudo "$PACMAN" -Rsn "${aurdepspkgs[@]}" --noconfirm
        # readd removed conflicting packages
        [[ "${aurconflictingpkgsrm[*]}" ]] &&
            sudo "$PACMAN" -S ${aurconflictingpkgsrm[@]} --ask 36 --asdeps --needed --noconfirm
        [[ "${repoconflictingpkgsrm[*]}" ]] &&
            sudo "$PACMAN" -S ${repoconflictingpkgsrm[@]} --ask 36 --asdeps --needed --noconfirm
    fi

    # remove locks
    rm "${tmpdir:?}/pacaur.build.lck"
    rm -f "${tmpdir:?}/pacaur.sudov.lck"

    # new orphan and optional packages check
    orphanpkgs=($("$PACMAN" -Qdtq))
    neworphanpkgs=($(CommArr 'oldorphanpkgs' 'orphanpkgs' '-13'))
    for i in "${neworphanpkgs[@]}"; do
        Note "w" $"${WHITE}$i${ALL_OFF} is now an ${YELLOW}orphan${ALL_OFF} package"
    done
    optionalpkgs=($("$PACMAN" -Qdttq))
    optionalpkgs=($(CommArr 'orphanpkgs' 'optionalpkgs' '-13'))
    newoptionalpkgs=($(CommArr 'oldoptionalpkgs' 'optionalpkgs' '-13'))
    for i in "${newoptionalpkgs[@]}"; do
        Note "w" $"${WHITE}$i${ALL_OFF} is now an ${YELLOW}optional${ALL_OFF} package"
    done

    # makepkg and install failure check
    if [[ "${errmakepkg[*]}" ]]; then
        for i in "${errmakepkg[@]}"; do
            Note "f" $"failed to build ${WHITE}$i${ALL_OFF} package(s)"
        done
        exit "$E_PACKAGE_FAILED"
    fi
    [[ "${errinstall[*]}" ]] && exit  "$E_INSTALL_FAILED"
}

# Get the list of ignored packages from pacman's configureation file
# Usage: GetIgnoredPkgs
GetIgnoredPkgs() {
    # global ignoredpkgs
    ignoredpkgs+=($(pacman-conf IgnorePkg))
    ignoredpkgs=("${ignoredpkgs[@]//,/ }")
}

# Get the list of ignored groups from pacman's configureation file
# Usage: GetIgnoredGrps
GetIgnoredGrps() {
    # global ignoredgrps
    ignoredgrps+=($(pacman-conf IgnoreGroup))
    ignoredgrps=("${ignoredgrps[@]//,/ }")
}

# get install scrips of the AUR package
# Usage: GetInstallScrips <aur package>
GetInstallScripts() {
    local installscriptspath
    # global installscripts
    [[ ! -d "$clonedir/$1" ]] && return
    unset installscriptspath installscripts
    shopt -s nullglob
    installscriptspath=($(printf '%s\n' "$clonedir/$1/"*'.install'))
    shopt -u nullglob
    [[ "${installscriptspath[*]}" ]] && installscripts=("${installscriptspath[@]##*/}")
}

# Get the complete path of the built package
# GetBuiltPkg <package version> <package dest>
GetBuiltPkg() {
    local ext
    # global builtpkg
    # check PKGEXT suffix first, then default .xz suffix for repository packages in pacman cache
    # and lastly all remaining suffixes in case PKGEXT is locally overridden
    for ext in "$PKGEXT" .pkg.tar{.xz,,.gz,.bz2,.lzo,.lrz,.Z}; do
        builtpkg="$2/$1-${CARCH}${ext}"
        [[ -f "$builtpkg" ]] || builtpkg="$2/$1-any${ext}"
        [[ -f "$builtpkg" ]] && break
    done
    [[ -f "$builtpkg" ]] || unset builtpkg
}

# Get packages bases from information arrays
# GetPkgbase <aur package>
GetPkgbase() {
    local i
    # global pkgsbase basepkgs
    SetInfo "$@"
    for i in "$@"; do
        pkgsbase+=($(GetInfo "PackageBase" "$i"))
    done
    for i in "${pkgsbase[@]}"; do
        [[ " ${basepkgs[*]} " =~ " $i " ]] || basepkgs+=("$i")
    done
}

# vim:set ts=4 sw=4 et:
