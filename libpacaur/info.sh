#!/usr/bin/env bash
#
#   info.sh -- functions related to obtaining and reading AUR rpc information
#   functions: SetInfo GetInfo
#

[[ -v LIBPACAUR_INFO_SH ]] && return
LIBPACAUR_INFO_SH=1

# Get information from AUR RPC and sort into associative arrays by field with
# pkgnames as indices
# Usage: SetInfo( $packages )
SetInfo() {
    # Use auracle formatted info output for all aur packages passed to SetInfo, and sort it into
    # associated arrays, with the key always being a pkgname fields are delimited by \037, the unit
    # separator, to prevent the delimiter from being in the input and shifting the entire array
    unset Name PackageBase Version Maintainer OutOfDate Groups {,Make,Check}Depends Provides Conflicts
    [[ "$*" ]] || return
    declare -gA Name PackageBase Version Maintainer OutOfDate Groups {,Make,Check}Depends Provides Conflicts
    while IFS=$'\037' read -r Aname Abase Aver Amain Aood Agrps Adeps Amakedeps Acheckdeps Aprovs Aconfs; do
        Name[$Aname]="$Aname"
        PackageBase[$Aname]="$Abase"
        Version[$Aname]="$Aver"
        Maintainer[$Aname]="$Amain"
        OutOfDate[$Aname]="$Aood"
        Groups[$Aname]="$Agrps"
        Depends[$Aname]="$Adeps"
        MakeDepends[$Aname]="$Amakedeps"
        CheckDepends[$Aname]="$Acheckdeps"
        Provides[$Aname]="$Aprovs"
        Conflicts[$Aname]="$Aconfs"
    done < <(auracle info "$@" -F \
        $'{name}\037{pkgbase}\037{version}\037{maintainer}\037{outofdate:%s}\037{groups: }\037{depends: }\037{makedepends: }\037{checkdepends: }\037{provides: }\037{conflicts: }')
}

# Get information of field from a package or all packages that had information
# obtained through auracle in SetInfo
# Usage: GetInfo <field> (optional pkgname)
GetInfo() {
    local field="$1" pkgname="${2:-}"

    [[ "$pkgname" ]] && field="${field}[$pkgname]" || field="${field}[@]"

    printf '%s\n' "${!field}"
}

# vim:set ts=4 sw=4 et:
