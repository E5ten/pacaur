#!/usr/bin/env bash
#
#   aur.sh -- functions related to cache management
#   functions: UpgradeAur CleanCache

[[ "${LIBPACAUR_CACHE_SH:-}" ]] && return
LIBPACAUR_CACHE_SH=1

LIBPACAUR="${LIBPACAUR:-/usr/share/pacaur}"

source "$LIBPACAUR/utils.sh"
source "$LIBPACAUR/info.sh"

# Upgrade needed AUR packages
# usage: UpgradeAur()
UpgradeAur() {
    local foreignpkgs allaurpkgs aurforeignpkgs i
    # global aurpkgs
    Note "i" $"${WHITE}Starting AUR upgrade...${ALL_OFF}"
    foreignpkgs=($("$PACMAN" -Qmq))
    SetInfo "${foreignpkgs[@]}"
    allaurpkgs=($(GetInfo "Name"))

    # foreign packages check
    aurforeignpkgs=($(CommArr 'allaurpkgs' 'foreignpkgs' '-13'))
    for i in "${aurforeignpkgs[@]}"; do
        Note "w" $"${WHITE}$i${ALL_OFF} is ${YELLOW}not present${ALL_OFF} in AUR -- skipping"
    done

    # use auracle to find out of date AUR packages
    mapfile -t < <(auracle sync -q) aurpkgs

    # add devel packages
    if (( DEVEL )); then
        for i in "${allaurpkgs[@]}"; do
            [[ "$i" =~ $vcs && ! " ${aurpkgs[*]} " =~ " $i " ]] && aurpkgs+=("$i")
        done
    fi

    aurpkgs+=("${pkgs[@]}")

    # avoid possible duplicate
    aurpkgs=($(printf '%s\n' "${aurpkgs[@]}" | sort -u))

    NothingToDo "${aurpkgs[@]}"
}

# Clean AUR cache, including sources and clone directories. This function lets
# users select what content is deleted
# usage: CleanCache( $packages )
CleanCache() {
    local i cachepkgs
    cachedir=($(pacman-conf CacheDir))
    [[ "${cachedir[*]}" ]] && cachedir=("${cachedir[@]%/}") && PKGDEST="${PKGDEST%/}"
    if [[ "$PKGDEST" && ! " ${cachedir[*]} " =~ " $PKGDEST " ]]; then
        (( CCOUNT == 1 )) && printf "\n%s\n %s\n" $"Packages to keep:" $"All locally installed packages"
        printf "\n%s %s\n" $"AUR cache directory:" "$PKGDEST"
        if (( CCOUNT == 1 )); then
            if Proceed "y" $"Do you want to remove all other packages from AUR cache?"; then
                printf "%s\n" $"removing old packages from cache..."
                cachepkgs=("${PKGDEST:?}"/*); cachepkgs=("${cachepkgs[@]##*/}")
                for i in "${cachepkgs[@]%-*}"; do
                    [[ "$i" != "$(expac -Q '%n-%v' "${i%-*-*}")" ]] && rm "${PKGDEST:?}/$i"-*
                done
            fi
        else
            Proceed "n" $"Do you want to remove ALL files from AUR cache?" ||
                printf "%s\n" $"removing all files from AUR cache..." &&
                rm "${PKGDEST:?}"/* &>/dev/null
        fi
    fi

    if [[ -d "$SRCDEST" ]]; then
        (( CCOUNT == 1 )) &&
            printf "\n%s\n %s\n" $"Sources to keep:" $"All development packages sources"
        printf "\n%s %s\n" $"AUR source cache directory:" "$SRCDEST"
        if (( CCOUNT == 1 )); then
            Proceed "y" $"Do you want to remove all non development files from AUR source cache?" &&
                printf "%s\n" $"removing non development files from source cache..." &&
                rm -f "${SRCDEST:?}"/* &>/dev/null
        else
            Proceed "n" $"Do you want to remove ALL files from AUR source cache?" ||
                printf "%s\n" $"removing all files from AUR source cache..." &&
                rm -rf "${SRCDEST:?}"/*
        fi
    fi
    if [[ -d "$clonedir" ]]; then
        if (( CCOUNT == 1 )); then
            if [[ ! "${pkgs[*]}" ]]; then
                printf "\n%s\n %s\n" $"Clones to keep:" $"All locally installed clones"
            else
                printf "\n%s\n %s\n" $"Clones to keep:" $"All other locally installed clones"
            fi
        fi
        printf "\n%s %s\n" $"AUR clone directory:" "$clonedir"
        if (( CCOUNT == 1 )); then
            mapfile -t < <(expac -Q '%e' $("$PACMAN" -Qmq)) foreignpkgsbase
            # get target
            if [[ "${pkgs[*]}" ]]; then
                mapfile -t < <(expac -Q '%e' "${pkgs[@]}") pkgsbase
                mapfile -t < <(CommArr 'pkgsbase' 'foreignpkgsbase' '-12') aurpkgsbase
                if Proceed "y" $"Do you want to remove ${aurpkgsbase[*]} clones from AUR clone directory?"; then
                    printf "%s\n\n" $"removing uninstalled clones from AUR clone cache..."
                    for i in "${aurpkgsbase[@]}"; do
                        [[ -d "$clonedir/$i" ]] && rm -rf "${clonedir:?}/$i"
                    done
                fi
            else
                if Proceed "y" $"Do you want to remove all uninstalled clones from AUR clone directory?"; then
                    printf "%s\n\n" $"removing uninstalled clones from AUR clone cache..."
                    for i in "${clonedir:?}/"*; do
                        [[ -d "$i" && ! " ${foreignpkgsbase[*]} " =~ " $i " ]] &&
                            rm -rf "${clonedir:?}/$i"
                    done
                fi
                if [[ ! "$PKGDEST" || ! "$SRCDEST" ]]; then
                    if Proceed "y" $"Do you want to remove all untracked files from AUR clone directory?"; then
                        printf "%s\n" $"removing untracked files from AUR clone cache..."
                        for i in "${clonedir:?}/"*; do
                            [[ -d "$i" ]] &&
                                git --git-dir="$i/.git" --work-tree="$i" clean -ffdx &>/dev/null
                        done
                    fi
                fi
            fi
        else
            if ! Proceed "n" $"Do you want to remove ALL clones from AUR clone directory?"; then
                printf "%s\n" $"removing all clones from AUR clone cache..."
                for i in "${clonedir:?}/"*; do
                    [[ -d "$i" ]] && rm -rf "$i"
                done
            fi
        fi
    fi
    exit "$E_OK"
}

# vim:set ts=4 sw=4 et:
