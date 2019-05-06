#!/usr/bin/env bash
#
#   main.sh -- functions related to top level operations
#   functions: Core Prompt Usage Cancel
#

[[ "$LIBPACAUR_MAIN_SH" ]] && return
LIBPACAUR_MAIN_SH=1

LIBPACAUR="${LIBPACAUR:-'/usr/share/pacaur'}"

source "$LIBPACAUR/utils.sh"
source "$LIBPACAUR/pkgs.sh"
source "$LIBPACAUR/deps.sh"
source "$LIBPACAUR/checks.sh"

# Start core functionality of pacaur
# Usage: Core
Core() {
    GetIgnoredPkgs
    GetIgnoredGrps
    (( UPGRADE )) && UpgradeAur
    IgnoreChecks
    DepsSolver
    IgnoreDepsChecks
    ProviderChecks
    ConflictChecks
    ReinstallChecks
    OutOfDateChecks
    OrphanChecks
    Prompt
    MakePkgs
}

# Format output information of the current operation and ask user to continue
# Usage: Prompt
Prompt() {
    local i binaryksize sumk summ builtpkg cachedpkgs stroldver strnewver strsize depsver
    local repodepspkgsver strrepodlsize strrepoinsize strsumk strsumm lreposizelabel lreposize
    # global repodepspkgs repodepsSver depsAname depsAver depsArepo depsAcached lname lver lsize
    # global deps depsQver repodepspkgs repodepsSrepo repodepsQver repodepsSver
    # compute binary size
    if [[ "${repodepspkgs[*]}" ]]; then
        binaryksize=($(expac -S1 '%k' "${repodepspkgs[@]}"))
        binarymsize=($(expac -S1 '%m' "${repodepspkgs[@]}"))
        sumk=0
        summ=0
        for i in "${!repodepspkgs[@]}"; do
            GetBuiltPkg "${repodepspkgs[$i]}-${repodepsSver[$i]}" "$(pacman-conf CacheDir)"
            [[ "$builtpkg" ]] && binaryksize[$i]=0
            sumk="$((sumk + "${binaryksize[$i]}"))"
            summ="$((summ + "${binarymsize[$i]}"))"
        done
        sumk="$((sumk / 1048576)).$((sumk / 1024 % 1024 * 100 / 1024))"
        summ="$((summ / 1048576)).$((summ / 1024 % 1024 * 100 / 1024))"
    fi

    # cached packages check
    for i in "${!depsAname[@]}"; do
        [[ ! "$PKGDEST" ]] || (( REBUILD )) && break
        GetBuiltPkg "${depsAname[$i]}-${depsAver[$i]}" "$PKGDEST"
        [[ "$builtpkg" ]] && cachedpkgs+=("${depsAname[$i]}") && depsAcached[$i]=$"(cached)" || depsAcached[$i]=""
        unset builtpkg
    done

    if [[ "$(pacman-conf VerbosePkgLists)" ]]; then
        straurname=$"AUR Packages  (${#deps[@]})"; strreponame=$"Repo Packages (${#repodepspkgs[@]})"
        stroldver=$"Old Version"; strnewver=$"New Version"; strsize=$"Download Size"
        depsArepo=("${depsAname[@]/#/aur/}")
        lname="$(GetLength "${depsArepo[@]}" "${repodepsSrepo[@]}" "$straurname" "$strreponame")"
        lver="$(GetLength "${depsQver[@]}" "${depsAver[@]}" "${repodepsQver[@]}" "${repodepsSver[@]}" "$stroldver" "$strnewver")"
        lsize="$(GetLength "$strsize")"

        # local version column cleanup
        for i in "${!deps[@]}"; do
            [[ "${depsQver[$i]}" =~ '%' ]] && unset depsQver[$i]
        done
        # show detailed output
        printf "\n${WHITE}%-${lname}s  %-${lver}s  %-${lver}s${ALL_OFF}\n\n" "$straurname" "$stroldver" "$strnewver"
        for i in "${!deps[@]}"; do
            printf "%-${lname}s  ${RED}%-${lver}s${ALL_OFF}  ${GREEN}%-${lver}s${ALL_OFF}  %${lsize}s\n" "${depsArepo[$i]}" "${depsQver[$i]}" "${depsAver[$i]}" "${depsAcached[$i]}";
        done

        if [[ "${repodepspkgs[*]}" ]]; then
            for i in "${!repodepspkgs[@]}"; do
                binarysize[$i]="$((binaryksize[$i] / 1048576)).$((binaryksize[$i] / 1024 % 1024 * 100 / 1024))"
            done
            printf "\n${WHITE}%-${lname}s  %-${lver}s  %-${lver}s  %s${ALL_OFF}\n\n" "$strreponame" "$stroldver" "$strnewver" "$strsize"
            for i in "${!repodepspkgs[@]}"; do
                printf "%-${lname}s  ${RED}%-${lver}s${ALL_OFF}  ${GREEN}%-${lver}s${ALL_OFF}  %${lsize}s\n" "${repodepsSrepo[$i]}" "${repodepsQver[$i]}" "${repodepsSver[$i]}" $"${binarysize[$i]} MiB";
            done
        fi
    else
        # show version
        for i in "${!deps[@]}"; do
            depsver="${depsver}${depsAname[$i]}-${depsAver[$i]}  "
        done
        for i in "${!repodepspkgs[@]}"; do
            repodepspkgsver="${repodepspkgsver}${repodepspkgs[$i]}-${repodepsSver[$i]}  "
        done
        printf "\n${WHITE}%-16s${ALL_OFF} %s\n" $"AUR Packages  (${#deps[@]})" "$depsver"
        [[ "${repodepspkgs[*]}" ]] &&
            printf "${WHITE}%-16s${ALL_OFF} %s\n" $"Repo Packages (${#repodepspkgs[@]})" "$repodepspkgsver"
    fi

    if [[ "${repodepspkgs[*]}" ]]; then
        strrepodlsize=$"Repo Download Size:"; strrepoinsize=$"Repo Installed Size:"; strsumk=$"$sumk MiB"
        strsumm=$"$summ MiB" lreposizelabel="$(GetLength "$strrepodlsize" "$strrepoinsize")"
        lreposize="$(GetLength "$strsumk" "$strsumm")"
        printf "\n${WHITE}%-${lreposizelabel}s${ALL_OFF}  %${lreposize}s\n" "$strrepodlsize" "$strsumk"
        printf "${WHITE}%-${lreposizelabel}s${ALL_OFF}  %${lreposize}s\n" "$strrepoinsize" "$strsumm"
    fi

    printf '\n'
    if (( INSTALLPKG )); then
        Proceed "y" $"Proceed with installation?" || exit "$E_FAIL"
    else
        Proceed "y" $"Proceed with download?" || exit "$E_FAIL"
    fi
}

# Print application usage commands
# Usage: Usage
Usage() {
    printf "%s\n" $"usage:  pacaur <operation> [options] [target(s)] -- See also pacaur(8)"
    printf "%s\n" $"operations:"
    printf "%s\n" $" pacman extension"
    printf "%s\n" $"   -S, -Ss, -Si, -Sw, -Su, -Qu, -Sc, -Scc"
    printf "%s\n" $"                    extend pacman operations to the AUR"
    printf "%s\n" $" general"
    printf "%s\n" $"   -v, --version    display version information"
    printf "%s\n" $"   -h, --help       display help information"
    printf '\n'
    printf "%s\n" $"options:"
    printf "%s\n" $" pacman extension - can be used with the -S, -Ss, -Si, -Sw, -Su, -Sc, -Scc operations"
    printf "%s\n" $"   -a, --aur        only search, build, install or clean target(s) from the AUR"
    printf "%s\n" $"   -r, --repo       only search, build, install or clean target(s) from the repositories"
    printf "%s\n" $" general"
    printf "%s\n" $"   -e, --edit       edit target(s) PKGBUILD and view install script"
    printf "%s\n" $"   -q, --quiet      show less information for query and search"
    printf "%s\n" $"   --devel          consider AUR development packages upgrade"
    printf "%s\n" $"   --foreign        consider already installed foreign dependencies"
    printf "%s\n" $"   --ignore         ignore a package upgrade (can be used more than once)"
    printf "%s\n" $"   --needed         do not reinstall already up-to-date target(s)"
    printf "%s\n" $"   --noconfirm      do not prompt for any confirmation"
    printf "%s\n" $"   --noedit         do not prompt to edit files"
    printf "%s\n" $"   --rebuild        always rebuild package(s)"
    printf "%s\n" $"   --silent         silence output"
    exit "$E_OK"
}

# Delete lock files and exit pacaur
# Usage: Cancel
Cancel() {
    printf '\n'
    rm -f "${tmpdir:?}"/pacaur.{build,sudov}.lck
    exit
}

# vim:set ts=4 sw=4 et:
