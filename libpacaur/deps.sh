#!/usr/bin/env bash
#
#   deps.sh -- functions related to resolving dependencies
#   functions: DepsSolver FindDepsAur SortDepsAur FindDepsAurError FindDepsRepo
#   FindDepsRepoProvider
#

[[ "$LIBPACAUR_DEPS_SH" ]] && return
LIBPACAUR_DEPS_SH=1

LIBPACAUR="${LIBPACAUR:-'/usr/share/pacaur'}"

source "$LIBPACAUR/info.sh"
source "$LIBPACAUR/utils.sh"
source "$LIBPACAUR/pkgs.sh"

# Dependency solver for both repo and AUR dependencies
# Usage: DepsSolver
DepsSolver() {
    local i aurpkgsconflicts
    # global aurpkgs aurpkgsnover aurpkgsproviders aurdeps deps errdeps
    # global errdepsnover foreignpkgs repodeps depsAname depsAver depsAood depsQver
    Note "i" $"resolving dependencies..."

    # remove AUR pkgs versioning
    aurpkgsnover=("${aurpkgs[@]%%[><=]*}")

    # set unversioned info
    SetInfo "${aurpkgsnover[@]}"

    # set targets providers
    aurpkgsproviders=("${aurpkgsnover[@]}")
    aurpkgsproviders+=($(GetInfo "Provides"))
    aurpkgsproviders=("${aurpkgsproviders[@]%%[><=]*}")

    # check targets conflicts
    aurpkgsconflicts=($(GetInfo "Conflicts"))
    if [[ "${aurpkgsconflicts[*]}" ]]; then
        aurpkgsconflicts=("${aurpkgsconflicts[@]%%[><=]*}")
        aurpkgsconflicts=($(CommArr 'aurpkgsproviders' 'aurpkgsconflicts' '-12'))
        for i in "${aurpkgsconflicts[@]}"; do
            [[ " ${aurpkgsnover[*]} " =~ " $i " ]] || continue
            [[ " $(GetInfo "Conflicts" "$i") " =~ " $i " ]] && continue
            Note "f" $"unresolvable package conflicts detected"
            Note "e" $"failed to prepare transaction (conflicting dependencies: $i)" "$E_INSTALL_DEPS_FAILED"
        done
    fi

    deps=("${aurpkgsnover[@]}")

    [[ "${foreignpkgs[*]}" ]] || foreignpkgs=($("$PACMAN" -Qmq))
    FindDepsAur "${aurpkgsnover[@]}"

    # avoid possible duplicate
    deps=($(CommArr 'aurdepspkgs' 'deps' '-13'))
    deps+=("${aurdepspkgs[@]}")

    # ensure correct dependency order
    SetInfo "${deps[@]}"
    SortDepsAur "${aurpkgs[@]}"
    deps=($(tsort <<< "${tsortdeps[@]}")) || Note "e" $"dependency cycle detected" "$E_INSTALL_DEPS_FAILED"

    # get AUR packages info
    depsAname=($(GetInfo "Name"))
    depsAver=($(GetInfo "Version"))
    depsAood=($(GetInfo "OutOfDate"))
    depsAmain=($(GetInfo "Maintainer"))
    for i in "${!depsAname[@]}"; do
        read -rd' ' < <(expac -Qs '%v' "^${depsAname[$i]}$") depsQver[$i]
        [[ "${depsQver[$i]}" ]] || depsQver[$i]="%"  # avoid empty elements shift
        [[ "${depsAname[$i]}" =~ $vcs ]] && depsAver[$i]=$"latest"
    done

    # no results check
    if [[ "${errdeps[*]}" ]]; then
        for i in "${!errdepsnover[@]}"; do
            if [[ " ${aurpkgsnover[*]} " =~ " ${errdepsnover[$i]} " ]]; then
                Note "f" $"no results found for ${errdeps[$i]}"
            else
                unset tsorterrdeps errdepslist currenterrdep
                # find relevant tsorted deps chain
                for j in "${deps[@]}"; do
                    tsorterrdeps+=("$j")
                    [[ "$j" = "${errdepsnover[$i]}" ]] && break
                done
                # reverse deps order
                for j in "${!tsorterrdeps[@]}"; do
                    tsorterrdepsrev[$j]="${tsorterrdeps[-j-1]}"
                done
                tsorterrdeps=("${tsorterrdepsrev[@]}") && unset tsorterrdepsrev
                errdepslist+=("${tsorterrdeps[0]}")
                FindDepsAurError "${tsorterrdeps[@]}"
                for j in "${!errdepslist[@]}"; do
                    [[ "${errdepslist[-j-1]}" ]] && errdepslistrev+=("${errdepslist[-j-1]}")
                done
                errdepslist=("${errdepslistrev[@]}") && unset errdepslistrev
                Note "f" $"no results found for ${errdeps[$i]} (dependency tree: ${errdepslist[*]})"
            fi
        done
        exit "$E_INSTALL_DEPS_FAILED"
    fi

    # return all binary deps
    FindDepsRepo "${repodeps[@]}"

    # avoid possible duplicate
    repodepspkgs=($(printf '%s\n' "${repodepspkgs[@]}" | sort -u))
}

# Find dependencies of of AUR packages
# Usage: FindDepsAur <aur package(s)>...
FindDepsAur() {
    local depspkgs depspkgstmp depspkgsaurtmp builtpkg vcsdepspkgs assumedepspkgs aurversionpkgs
    local aurversionpkgsname aurversionpkgsver aurversionpkgsaurver aurversionpkgsverdiff i j
    # global aurpkgsnover depspkgsaur errdeps repodeps aurdepspkgs prevdepspkgsaur foreignpkgs
    (( NODEPS && DCOUNT >= 2 )) && return

    # set info
    unset aurversionpkgs
    if [[ "${depspkgsaur[*]}" ]]; then
        SetInfo "${depspkgsaur[@]}"
        aurversionpkgs=("${prevdepspkgsaur[@]}")
    else
        SetInfo "${aurpkgsnover[@]}"
        aurversionpkgs=("${aurpkgs[@]}")
    fi

    # versioning check
    if [[ "${aurversionpkgs[*]}" ]]; then
        for i in "${!aurversionpkgs[@]}"; do
            unset aurversionpkgsname aurversionpkgsver aurversionpkgsaurver aurversionpkgsverdiff
            aurversionpkgsname="${aurversionpkgs[$i]%%[><=]*}"
            aurversionpkgsver="${aurversionpkgs[$i]##*[><=]}"
            aurversionpkgsaurver="$(GetInfo "Version" "$aurversionpkgsname")"
            aurversionpkgsverdiff="$(vercmp "$aurversionpkgsaurver" "$aurversionpkgsver")"

            # not found in AUR nor repo
            [[ ! "$aurversionpkgsaurver" && ! " ${errdeps[*]} " =~ " ${aurversionpkgs[$i]} " ]] &&
                errdeps+=("${aurversionpkgs[$i]}") && continue

            case "${aurversionpkgs[$i]}" in
                *">"*|*"<"*|*"="*)
                    # found in AUR but version not correct
                    case "${aurversionpkgs[$i]}" in
                        *">="*) [[ "$aurversionpkgsverdiff" -ge 0 ]] && continue;;
                        *"<="*) [[ "$aurversionpkgsverdiff" -le 0 ]] && continue;;
                        *">"*)  [[ "$aurversionpkgsverdiff" -gt 0 ]] && continue;;
                        *"<"*)  [[ "$aurversionpkgsverdiff" -lt 0 ]] && continue;;
                        *"="*)  [[ "$aurversionpkgsverdiff" -eq 0 ]] && continue;;
                    esac
                    [[ " ${errdeps[*]} " =~ " ${aurversionpkgs[$i]} " ]] ||
                        errdeps+=("${aurversionpkgs[$i]}");;
                *) continue;;
            esac
        done
    fi

    depspkgs=($(GetInfo "Depends"))

    # cached packages makedeps check
    if [[ ! "$PKGDEST" ]] || (( REBUILD )); then
        depspkgs+=($(GetInfo "MakeDepends"))
        (( CHECKDEPS )) && depspkgs+=($(GetInfo "CheckDepends"))
    else
        [[ ! "${depspkgsaur[*]}" ]] && depspkgsaurtmp=("${aurpkgs[@]}") ||
            depspkgsaurtmp=("${depspkgsaur[@]}")
        for i in "${!depspkgsaurtmp[@]}"; do
            local depAname="$(GetInfo "Name" "${depspkgsaurtmp[$i]}")"
            local depAver="$(GetInfo "Version" "${depspkgsaurtmp[$i]}")"
            GetBuiltPkg "$depAname-$depAver" "$PKGDEST"
            if [[ ! "$builtpkg" ]]; then
                depspkgs+=($(GetInfo "MakeDepends" "${depspkgsaurtmp[$i]}"))
                (( CHECKDEPS )) && depspkgs+=($(GetInfo "CheckDepends"))
            fi
            unset builtpkg
        done
    fi

    # remove deps provided by targets
    [[ "${aurpkgsproviders[*]}" ]] && depspkgs=($(CommArr 'aurpkgsproviders' 'depspkgs' '-13'))

    # workaround for limited RPC support of architecture dependent fields
    if [[ "${CARCH}" = 'i686' ]]; then
        for i in "${!depspkgs[@]}"; do
            [[ "${depspkgs[$i]}" =~ ^(lib32-|gcc-multilib) ]] && unset depspkgs[$i]
        done
        depspkgs=($(printf '%s\n' "${depspkgs[@]}"))
    fi

    # remove versioning
    depspkgs=("${depspkgs[@]%%[><=]*}")
    # remove installed deps
    if (( ! DEVEL )); then
        depspkgs=($("$PACMAN" -T -- "${depspkgs[@]}" | sort -u))
    else
        # check providers
        unset vcsdepspkgs
        for i in "${!depspkgs[@]}"; do
            unset j && read -rd' ' < <(expac -Qs '%n %P' "^${depspkgs[$i]}$") j
            if [[ "$j" ]]; then
                depspkgs[$i]="$j"
                (( DEVEL )) && [[ ! " ${ignoredpkgs[*]} " =~ " $j " && "$j" =~ $vcs ]] &&
                    vcsdepspkgs+=("$j")
            else
                foreignpkgs+=("${depspkgs[$i]}")
            fi
        done
        # reorder devel
        depspkgs=($("$PACMAN" -T -- "${depspkgs[@]}" | sort -u))
        depspkgs=($(CommArr 'depspkgs' 'vcsdepspkgs' '-3'))
    fi

    # split repo and AUR depends pkgs
    unset depspkgsaur
    if [[ "${depspkgs[*]}" ]]; then
        # remove all pkgs versioning
        if (( NODEPS && DCOUNT == 1 )); then
            depspkgs=("${depspkgs[@]%%[><=]*}")
        # assume installed deps
        elif [[ "${assumeinstalled[*]}" ]]; then
            # remove versioning
            assumeinstalled=("${assumeinstalled[@]%%[><=]*}")
            for i in "${!assumeinstalled[@]}"; do
                unset assumedepspkgs
                for j in "${!depspkgs[@]}"; do
                    assumedepspkgs[$j]="${depspkgs[$j]%%[><=]*}"
                    [[ " ${assumedepspkgs[*]} " =~ " ${assumeinstalled[$i]} " ]] &&
                        depspkgs[$j]="${assumeinstalled[$i]}";
                done
            done
            depspkgs=($(CommArr 'assumeinstalled' 'depspkgs' '-13'))
        fi
        if [[ "${depspkgs[*]}" ]]; then
            IFS=$'\n' mapfile -t < <(LC_ALL=C "$PACMAN" -Sp "${depspkgs[@]}" 2>&1 >/dev/null ) depspkgsaur &&
            depspkgsaur=("${depspkgsaur[@]#error: target not found: }")
            repodeps+=($(CommArr 'depspkgsaur' 'depspkgs' '-13'))
        fi
    fi
    unset depspkgs

    # remove duplicate
    [[ "${depspkgsaur[*]}" ]] && depspkgsaur=($(CommArr 'aurdepspkgs' 'depspkgsaur' '-13'))

    # dependency cycle check
    [[ "${prevdepspkgsaur[*]}" ]] && [[ "${prevdepspkgsaur[*]}" = "${depspkgsaur[*]}" ]] &&
        Note "e" $"dependency cycle detected (${depspkgsaur[*]})" "$E_INSTALL_DEPS_FAILED"

    if [[ "${depspkgsaur[*]}" ]]; then
        # store for AUR version check
        (( NODEPS )) || prevdepspkgsaur=("${depspkgsaur[@]}")
        # remove duplicates and versioning
        depspkgsaur=($(printf '%s\n' "${depspkgsaur[@]%%[><=]*}" | sort -u))
    fi

    [[ "${depspkgsaur[*]}" ]] && aurdepspkgs+=("${depspkgsaur[@]}") &&
        FindDepsAur "${depspkgsaur[@]}"
}

# Sort dependencies to ensure correct order
# Usage: SortDepsAur <aur package(s)>...
SortDepsAur() {
    local i j sortaurpkgs sortdepspkgs sortdepspkgsaur
    # global checkedsortdepspkgsaur allcheckedsortdepspkgsaur errdepsnover
    [[ "${checkedsortdepspkgsaur[*]}" ]] && sortaurpkgs=("${checkedsortdepspkgsaur[@]}") ||
        sortaurpkgs=("${aurpkgs[@]}")

    unset checkedsortdepspkgsaur
    for i in "${!sortaurpkgs[@]}"; do
        unset sortdepspkgs sortdepspkgsaur

        sortdepspkgs+=($(GetInfo "Depends" "${sortaurpkgs[$i]}"))
        sortdepspkgs+=($(GetInfo "MakeDepends" "${sortaurpkgs[$i]}"))
        (( CHECKDEPS )) && sortdepspkgs+=($(GetInfo "CheckDepends"))

        # remove versioning
        errdepsnover=("${errdeps[@]%%[><=]*}")

        # check AUR deps only
        for j in "${!sortdepspkgs[@]}"; do
            sortdepspkgs[$j]="${sortdepspkgs[$j]%%[><=]*}"
            sortdepspkgsaur+=($(GetInfo "Name" "${sortdepspkgs[$j]}"))
            # add erroneous AUR deps
            [[ " ${errdepsnover[*]} " =~ " ${sortdepspkgs[$j]} " ]] &&
                sortdepspkgsaur+=("${sortdepspkgs[$j]}")
        done

        # prepare tsort list
        if [[ ! "${sortdepspkgsaur[*]}" ]]; then
            tsortdeps+=("${sortaurpkgs[$i]} ${sortaurpkgs[$i]}")
        else
            for j in "${!sortdepspkgsaur[@]}"; do
                tsortdeps+=("${sortaurpkgs[$i]} ${sortdepspkgsaur[$j]}")
            done
        fi

        # filter non checked deps
        sortdepspkgsaur=($(CommArr 'allcheckedsortdepspkgsaur' 'sortdepspkgsaur' '-13'))
        if [[ "${sortdepspkgsaur[*]}" ]]; then
            checkedsortdepspkgsaur+=("${sortdepspkgsaur[@]}")
            allcheckedsortdepspkgsaur+=("${sortdepspkgsaur[@]}")
            allcheckedsortdepspkgsaur=($(printf '%s\n' "${allcheckedsortdepspkgsaur[@]}" | sort -u))
        fi
    done
    if [[ "${checkedsortdepspkgsaur[*]}" ]]; then
        checkedsortdepspkgsaur=($(printf '%s\n' "${checkedsortdepspkgsaur[@]}" | sort -u))
        SortDepsAur "${checkedsortdepspkgsaur[@]}"
    fi
}

# Find dependency errors in AUR packages
# Usage: FindDepsAurError <sorted_dependencies>
FindDepsAurError() {
    local i nexterrdep nextallerrdeps
    # global errdepsnover errdepslist tsorterrdeps currenterrdep

    for i in "${tsorterrdeps[@]}"; do
        [[ " ${errdepsnover[*]} " =~ " $i " || " ${errdepslist[*]} " =~ " $i " ]] || nexterrdep="$i" && break
    done

    [[ "${currenterrdep[*]}" ]] || currenterrdep="${tsorterrdeps[0]}"
    if [[ ! " ${aurpkgs[*]} " =~ " $nexterrdep " ]]; then
        nextallerrdeps=($(GetInfo "Depends" "$nexterrdep"))
        nextallerrdeps+=($(GetInfo "MakeDepends" "$nexterrdep"))
        (( CHECKDEPS )) && nextallerrdeps+=($(GetInfo "CheckDepends"))

        # remove versioning
        nextallerrdeps=("${nextallerrdeps[@]%%[><=]*}")

        [[ " ${nextallerrdeps[*]} " =~ " $currenterrdep " ]] && errdepslist+=("$nexterrdep") &&
            currenterrdep="${tsorterrdeps[0]}"
        tsorterrdeps=("${tsorterrdeps[@]:1}")
        FindDepsAurError "${tsorterrdeps[@]}"
    else
        for i in "${!aurpkgs[@]}"; do
            nextallerrdeps=($(GetInfo "Depends" "${aurpkgs[$i]}"))
            nextallerrdeps+=($(GetInfo "MakeDepends" "${aurpkgs[$i]}"))
            (( CHECKDEPS )) && nextallerrdeps+=($(GetInfo "CheckDepends"))

            # remove versioning
            nextallerrdeps=("${nextallerrdeps[@]%%[><=]*}")

            [[ " ${nextallerrdeps[*]} " =~ " $currenterrdep " ]] && errdepslist+=("${aurpkgs[$i]}")
        done
    fi
}

# Find dependencies of repository packages
# Usage: FindDepsRepo <repo package(s)>
FindDepsRepo() {
    local allrepodepspkgs repodepspkgstmp
    # global repodeps repodepspkgs
    [[ "${repodeps[*]}" ]] || return

    # reduce root binary deps
    repodeps=($(printf '%s\n' "${repodeps[@]}" | sort -u))

    # add initial repodeps
    [[ "${repodepspkgs[*]}" ]] || repodepspkgs=("${repodeps[@]}")

    # get non installed binary deps
    unset allrepodepspkgs repodepspkgstmp
    # no version check needed as all deps are repo deps
    [[ "${repodeps[*]}" ]] && allrepodepspkgs=($(expac -S1 '%E' "${repodeps[@]}"))
    [[ "${allrepodepspkgs[*]}" ]] && repodepspkgstmp=($("$PACMAN" -T -- "${allrepodepspkgs[@]}" | sort -u))

    # remove duplicate
    [[ "${repodepspkgstmp[*]}" ]] && repodepspkgstmp=($(CommArr 'repodepspkgs' 'repodepspkgstmp' '-13'))
    [[ "${repodepspkgstmp[*]}" ]] && repodepspkgs+=("${repodepspkgstmp[@]}") &&
        repodeps=("${repodepspkgstmp[@]}") && FindDepsRepo "${repodeps[@]}"
}

# Find dependency providers of packages
# Usage: FindDepsRepoProvider <repo package(s)>
FindDepsRepoProvider() {
    local allrepodepspkgs providerrepodepspkgstmp
    # global repodeps repodepspkgs
    [[ "${providerspkgs[*]}" ]] || return

    # reduce root binary deps
    providerspkgs=($(printf '%s\n' "${providerspkgs[@]}" | sort -u))

    # get non installed repo deps
    unset allproviderrepodepspkgs providerrepodepspkgstmp
    [[ "${providerspkgs[*]}" ]] && allproviderrepodepspkgs=($(expac -S1 '%E' "${providerspkgs[@]}"))
    # no version check needed as all deps are binary
    [[ "${allproviderrepodepspkgs[*]}" ]] &&
        providerrepodepspkgstmp=($("$PACMAN" -T -- "${allproviderrepodepspkgs[@]}" | sort -u))

    # remove duplicate
    [[ "${providerrepodepspkgstmp[*]}" ]] &&
        providerrepodepspkgstmp=($(CommArr 'repodepspkgs' 'providerrepodepspkgstmp' '-13'))

    [[ "${providerrepodepspkgstmp[*]}" ]] && repodepspkgs+=("${providerrepodepspkgstmp[@]}") &&
        providerspkgs=("${providerrepodepspkgstmp[@]}") && FindDepsRepoProvider "${providerspkgs[@]}"
}

# vim:set ts=4 sw=4 et:
