#!/usr/bin/env bash
#
#    checks.sh -- functions related to checking operations
#    functions: IgnoreChecks IgnoreDepsChecks ProviderChecks ConflictChecks
#    ReinstallChecks OutOfDateChecks OrphanChecks CheckRequires
#

[[ "$LIBPACAUR_CHECKS_SH" ]] && return
LIBPACAUR_CHECKS_SH=1

LIBPACAUR="${LIBPACAUR:-'/usr/share/pacaur'}"

source "$LIBPACAUR/info.sh"

# Check packages to be ignored during installation or upgrade
# Usage: IgnoreChecks
IgnoreChecks() {
    local checkaurpkgs checkaurpkgsAver checkaurpkgsQver checkaurpkgsgrp i
    # global aurpkgs rmaurpkgs
    [[ "${ignoredpkgs[*]}" || "${ignoredgrps[*]}" ]] || return

    # remove AUR pkgs versioning
    aurpkgsnover=("${aurpkgs[@]%%[><=]*}")

    # check targets
    SetInfo "${aurpkgsnover[@]}"
    checkaurpkgs=($(GetInfo "Name"))
    errdeps=($(CommArr 'aurpkgsnover' 'checkaurpkgs' '-3'))
    unset aurpkgsnover

    checkaurpkgsAver=($(GetInfo "Version"))
    mapfile -t < <(expac -Qv '%v' "${checkaurpkgs[@]}" 2>&1) checkaurpkgsQver
    for i in "${!checkaurpkgs[@]}"; do
        [[ "${checkaurpkgs[$i]}" =~ $vcs ]] && checkaurpkgsAver[$i]=$"latest"
        unset isignored
        if [[ " ${ignoredpkgs[*]} " =~ " ${checkaurpkgs[$i]} " ]]; then
            isignored=1
        elif [[ "${ignoredgrps[*]}" ]]; then
            unset checkaurpkgsgrp
            checkaurpkgsgrp=($(GetInfo "Groups" "${checkaurpkgs[$i]}"))
            checkaurpkgsgrp+=($(expac -Q '%G' "${checkaurpkgs[$i]}"))
            for j in "${checkaurpkgsgrp[@]}"; do
                [[ " ${ignoredgrps[*]} " =~ " $j " ]] && isignored=1
            done
        fi

        if [[ "$isignored" ]] ; then
            if (( ! UPGRADE )); then
                if (( ! NOCONFIRM )); then
                    if ! Proceed "y" $"${checkaurpkgs[$i]} is in IgnorePkg/IgnoreGroup. Install anyway?"; then
                        Note "w" $"skipping target: ${WHITE}${checkaurpkgs[$i]}${ALL_OFF}"
                        rmaurpkgs+=("${checkaurpkgs[$i]}")
                        continue
                    fi
                else
                    Note "w" $"skipping target: ${WHITE}${checkaurpkgs[$i]}${ALL_OFF}"
                    rmaurpkgs+=("${checkaurpkgs[$i]}")
                    continue
                fi
            else
                Note "w" $"${WHITE}${checkaurpkgs[$i]}${ALL_OFF}: ignoring package upgrade (${RED}${checkaurpkgsQver[$i]}${ALL_OFF} => ${GREEN}${checkaurpkgsAver[$i]}${ALL_OFF})"
                rmaurpkgs+=("${checkaurpkgs[$i]}")
                continue
            fi
        fi
        aurpkgsnover+=("${checkaurpkgs[$i]}")
    done

    aurpkgs=("${aurpkgsnover[@]}")
    NothingToDo "${aurpkgs[@]}"
}

# Check packages needed as dependencies to see if they're ignored
# Usage: IgnoreDepsChecks
IgnoreDepsChecks() {
    local i
    # global ignoredpkgs aurpkgs aurdepspkgs aurdepspkgsgrp repodepspkgsgrp rmaurpkgs deps repodepspkgs
    [[ "${ignoredpkgs[*]}" || "${ignoredgrps[*]}" ]] || return

    # add checked targets and preserve tsorted order
    deps=("${deps[@]:0:${#aurpkgs[@]}}")

    # check dependencies
    for i in "${repodepspkgs[@]}"; do
        unset isignored
        if [[ " ${ignoredpkgs[*]} " =~ " $i " ]]; then
            isignored=1
        elif [[ "${ignoredgrps[*]}" ]]; then
            unset repodepspkgsSgrp repodepspkgsQgrp
            repodepspkgsgrp=($(expac -S1 '%G' "$i"))
            repodepspkgsgrp+=($(expac -Q '%G' "$i"))
            for j in "${repodepspkgsgrp[@]}"; do
                [[ " ${ignoredgrps[*]} " =~ " $j " ]] && isignored=1
            done
        fi

        if [[ "$isignored" ]]; then
            (( ! UPGRADE )) && Note "w" $"skipping target: ${WHITE}$i${ALL_OFF}" ||
                Note "w" $"${WHITE}$i${ALL_OFF}: ignoring package upgrade"
            Note "e" $"Unresolved dependency '${WHITE}$i${ALL_OFF}'" "$E_INSTALL_DEPS_FAILED"
        fi
    done
    for i in "${aurdepspkgs[@]}"; do
        # skip already checked dependencies
        [[ " ${aurpkgs[*]} " =~ " $i " ]] && continue
        [[ " ${rmaurpkgs[*]} " =~ " $i " ]] &&
            Note "e" $"Unresolved dependency '${WHITE}$i${ALL_OFF}'" "$E_INSTALL_DEPS_FAILED"

        unset isignored
        if [[ " ${ignoredpkgs[*]} " =~ " $i " ]]; then
            isignored=1
        elif [[ "${ignoredgrps[*]}" ]]; then
            unset aurdepspkgsgrp
            aurdepspkgsgrp=($(GetInfo "Groups" "$i"))
            aurdepspkgsgrp+=($(expac -Q '%G' "$i"))
            for j in "${aurdepspkgsgrp[@]}"; do
                [[ " ${ignoredgrps[*]} " =~ " $j " ]] && isignored=1
            done
        fi

        if [[ "$isignored" ]]; then
            if (( ! NOCONFIRM )); then
                if ! Proceed "y" $"$i dependency is in IgnorePkg/IgnoreGroup. Install anyway?"; then
                    Note "w" $"skipping target: ${WHITE}$i${ALL_OFF}"
                    Note "e" $"Unresolved dependency '${WHITE}$i${ALL_OFF}'" "$E_INSTALL_DEPS_FAILED"
                fi
            else
                (( UPGRADE )) && Note "w" $"${WHITE}$i${ALL_OFF}: ignoring package upgrade" ||
                    Note "w" $"skipping target: ${WHITE}$i${ALL_OFF}"
                Note "e" $"Unresolved dependency '${WHITE}$i${ALL_OFF}'" "$E_INSTALL_DEPS_FAILED"
            fi
        fi
        deps+=("$i")
    done
}

# Check package and dependency providers
# Usage: ProviderChecks
ProviderChecks() {
    local providersdeps providersdepsnover providers repodepspkgsprovided providerspkgs provided
    local nb providersnb
    # global repodepspkgs repoprovidersconflictingpkgs repodepsSver repodepsSrepo repodepsQver
    [[ "${repodepspkgs[*]}" ]] || return

    # filter directly provided deps
    noprovidersdeps=($(expac -S1 '%n' "${repodepspkgs[@]}"))
    providersdeps=($(CommArr 'noprovidersdeps' 'repodepspkgs' '-13'))

    # remove installed providers
    providersdeps=($("$PACMAN" -T -- "${providersdeps[@]}" | sort -u))

    for i in "${!providersdeps[@]}"; do
        # check versioning
        unset providersdepsname providersdepsver providersdepsSname providersdepsSver
        providersdepsname="${providersdeps[$i]%%[><=]*}"
        providersdepsver="${providersdeps[$i]##*[><=]}"
        providersdepsSname=($(expac -Ss '%n' "^${providersdepsname[$i]}$"))
        providersdepsSver=($(expac -Ss '%v' "^${providersdepsname[$i]}$"))

        case "${providersdeps[$i]}" in
            *">"*|*"<"*|*"="*)
                for j in "${!providersdepsSname[@]}"; do
                    unset providersdepverdiff
                    providersdepsverdiff="$(vercmp "$providersdepsver" "${providersdepsSver[j]}")"
                    # found in repo but version not correct
                    case "${providersdeps[$i]}" in
                        *">="*) [[ "$providersdepsverdiff" -ge 0 ]] && continue;;
                        *"<="*) [[ "$providersdepsverdiff" -le 0 ]] && continue;;
                        *">"*)  [[ "$providersdepsverdiff" -gt 0 ]] && continue;;
                        *"<"*)  [[ "$providersdepsverdiff" -lt 0 ]] && continue;;
                        *"="*)  [[ "$providersdepsverdiff" -eq 0 ]] && continue;;
                    esac
                    providersdepsnover+=("${providersdepsSname[j]}")
                done
            ;;
        esac

        # remove versioning
        providersdeps[$i]="${providersdeps[$i]%%[><=]*}"

        # list providers
        providers=($(expac -Ss '%n' "^${providersdeps[$i]}$" | sort -u))

        # filter out non matching versioned providers
        [[ "${providersdepsnover[*]}" ]] && providers=($(CommArr 'providersdepsnover' 'providers' '-12'))

        # skip if provided in dependency chain
        unset repodepspkgsprovided
        for j in "${!providers[@]}"; do
            [[ " ${repodepspkgs[*]} " =~ " ${providers[$j]} " ]] && repodepspkgsprovided='true'
        done
        [[ "$repodepspkgsprovided" ]] && continue

        # skip if already provided
        if [[ "${providerspkgs[*]}" ]]; then
            providerspkgs=($(printf '%s|' "${providerspkgs[@]}"))
            providerspkgs=("${providerspkgs[@]%|}")
            provided+=($(expac -Ss '%S' "^(${providerspkgs[*]})$"))
            [[ " ${provided[*]} " =~ " ${providersdeps[$i]} " ]] && continue
        fi

        if (( ! NOCONFIRM && "${#providers[*]}" > 1 )); then
            Note "i" $"${WHITE}There are ${#providers[@]} providers available for ${providersdeps[$i]}:${ALL_OFF}"
            expac -S1 '   %!) %n (%r) ' "${providers[@]}"

            nb=-1
            providersnb="$[[ "${providers[@]}" -1 ]]" # count from 0
            while [[ "$nb" -lt 0 || "$nb" -ge "${#providers}" ]]; do
                printf "\n%s " $"Enter a number (default=0):"
                case "$TERM" in
                    dumb)
                    read -r nb
                    ;;
                    *)
                    read -r -n "${#providersnb}" nb
                    printf '\n'
                    ;;
                esac

                case "$nb" in
                    [0-9]|[0-9][0-9]) if [[ "$nb" -lt 0 || "$nb" -ge "${#providers[@]}" ]]; then
                            printf '\n'
                            Note "f" $"invalid value: $nb is not between 0 and $providersnb" && ((i--))
                        else
                            break
                        fi;;
                    '') nb=0;;
                    *) Note "f" $"invalid number: $nb";;
                esac
            done
        else
            nb=0
        fi
        providerspkgs+=("${providers[$nb]}")
    done

    # add selected providers to repo deps
    repodepspkgs+=("${providerspkgs[@]}")

    # store for installation
    repoprovidersconflictingpkgs+=("${providerspkgs[@]}")

    FindDepsRepoProvider "${providerspkgs[@]}"

    # get binary packages info
    if [[ "${repodepspkgs[*]}" ]]; then
        repodepspkgs=($(expac -S1 '%n' "${repodepspkgs[@]}" | sort -u))
        repodepsSver=($(expac -S1 '%v' "${repodepspkgs[@]}"))
        repodepsQver=($(expac -Q '%v' "${repodepspkgs[@]}"))
        repodepsSrepo=($(expac -S1 '%r/%n' "${repodepspkgs[@]}"))
    fi
}

# Check conflicting packages and dependencies
# Usage: ConflictChecks
ConflictChecks() {
    local allQprovides allQconflicts Aprovides Aconflicts aurconflicts aurAconflicts Qrequires i j
    local k l repodepsprovides repodepsconflicts checkedrepodepsconflicts repodepsconflictsname
    local repodepsconflictsver localver repoconflictingpkgs
    # global deps depsAname aurdepspkgs aurconflictingpkgs aurconflictingpkgskeep aurconflictingpkgsrm
    # global depsQver repodepspkgs repoconflictingpkgskeep repoconflictingpkgsrm repoprovidersconflictingpkgs
    Note "i" $"looking for inter-conflicts..."

    allQprovides=($(expac -Q '%n'))
    allQprovides+=($(expac -Q '%S')) # no versioning
    allQconflicts=($(expac -Q '%C'))

    # AUR conflicts
    Aprovides=("${depsAname[@]}")
    Aprovides+=($(GetInfo "Provides"))
    Aconflicts=($(GetInfo "Conflicts"))
    # remove AUR versioning
    Aprovides=("${Aprovides[@]%%[><=]*}")
    Aconflicts=("${Aconflicts[@]%%[><=]*}")
    aurconflicts=($(CommArr 'Aprovides' 'allQconflicts' '-12'))
    aurconflicts+=($(CommArr 'Aconflicts' 'allQprovides' '-12'))
    aurconflicts=($(printf '%s\n' "${aurconflicts[@]}" | sort -u))

    for i in "${aurconflicts[@]}"; do
        unset aurAconflicts
        [[ " ${depsAname[*]} " =~ " $i " ]] && aurAconflicts=("$i")
        for j in "${depsAname[@]}"; do
            [[ " $(GetInfo "Conflicts" "$j") " =~ " $i " ]] && aurAconflicts+=("$j")
        done

        for j in "${aurAconflicts[@]}"; do
            unset k Aprovides
            read -rd' ' < <(expac -Qs '%n %P' "^$i$") k
            (( ! INSTALLPKG )) && [[ ! " ${aurdepspkgs[*]} " =~ " $j " ]] && continue # download only
            [[ "$j" = "$k" || ! "$k" ]] && continue # skip if reinstalling or if no conflict exists

            Aprovides=("$j")
            if (( ! NOCONFIRM )) && [[ ! " ${aurconflictingpkgs[*]} " =~ " $k " ]]; then
                if ! Proceed "n" $"$j and $k are in conflict ($i). Remove $k?"; then
                    aurconflictingpkgs+=("$j" "$k")
                    aurconflictingpkgskeep+=("$j")
                    aurconflictingpkgsrm+=("$k")
                    for k in "${!depsAname[@]}"; do
                        [[ " ${depsAname[$l]} " =~ "$k" ]] && read -rd' ' < <(expac -Qs '%v' "^$k$") depsQver[$l]
                    done
                    Aprovides+=($(GetInfo "Provides" "$j"))
                    # remove AUR versioning
                    Aprovides=("${Aprovides[@]%%[><=]*}")
                    [[ ! " ${Aprovides[*]} ${aurconflictingpkgsrm[*]} " =~ " $k " ]] && CheckRequires "$k"
                    break
                else
                    Note "f" $"unresolvable package conflicts detected"
                    Note "f" $"failed to prepare transaction (conflicting dependencies)"
                    if (( UPGRADE )); then
                        Qrequires=($(expac -Q '%N' "$i"))
                        Note "e" $"$j and $k are in conflict (required by ${Qrequires[*]})" "$E_INSTALL_DEPS_FAILED"
                    else
                        Note "e" $"$j and $k are in conflict" "$E_INSTALL_DEPS_FAILED"
                    fi
                fi
            fi
            Aprovides+=($(GetInfo "Provides" "$j"))
            # remove AUR versioning
            Aprovides=("${Aprovides[@]%%[><=]*}")
            [[ ! " ${Aprovides[*]} ${aurconflictingpkgsrm[*]} " =~ " $k " ]] && CheckRequires "$k"
        done
    done

    NothingToDo "${deps[@]}"

    # repo conflicts
    if [[ "${repodepspkgs[*]}" ]]; then
        repodepsprovides=("${repodepspkgs[@]}")
        repodepsprovides+=($(expac -S1 '%S' "${repodepspkgs[@]}")) # no versioning
        repodepsconflicts=($(expac -S1 '%H' "${repodepspkgs[@]}"))

        # versioning check
        unset checkedrepodepsconflicts
        for i in "${!repodepsconflicts[@]}"; do
            unset repodepsconflictsname repodepsconflictsver localver
            repodepsconflictsname="${repodepsconflicts[$i]%%[><=]*}"
            repodepsconflictsver="${repodepsconflicts[$i]##*[><=]}"
            local localver="$(expac -Q '%v' "$repodepsconflictsname")"
            local repodepsconflictsverdiff="$(vercmp "$repodepsconflictsver" "$localver")"

            if [[ "$localver" ]]; then
                case "${repodepsconflicts[$i]}" in
                    *">="*) (( "$repodepsconflictsverdiff" >= 0 )) && continue;;
                    *"<="*) (( "$repodepsconflictsverdiff" <= 0 )) && continue;;
                    *">"*)  (( "$repodepsconflictsverdiff" > 0 ))  && continue;;
                    *"<"*)  (( "$repodepsconflictsverdiff" < 0 ))  && continue;;
                    *"="*)  (( "$repodepsconflictsverdiff" = 0 ))  && continue;;
                esac
                checkedrepodepsconflicts+=("$repodepsconflictsname")
            fi
        done

        repoconflicts+=($(CommArr 'repodepsprovides' 'allQconflicts' '-12'))
        repoconflicts+=($(CommArr 'checkedrepodepsconflicts' 'allQprovides' '-12'))
        repoconflicts=($(printf '%s\n' "${repoconflicts[@]}" | sort -u))
    fi

    for i in "${repoconflicts[@]}"; do
        unset Qprovides
        unset j && read -rd' ' < <(expac -Ss '%n %C %S' "^$i$") j
	    unset k && read -rd' ' < <(expac -Qs '%n %C %S' "^$i$") k
        [[ "$j" = "$k" || ! "$k" ]] && continue # skip when no conflict with repopkgs
        if (( ! NOCONFIRM )) && [[ ! " ${repoconflictingpkgs[*]} " =~ " $k " ]]; then
            if ! Proceed "n" $"$j and $k are in conflict ($i). Remove $k?"; then
                repoconflictingpkgs+=("$j" "$k")
                repoconflictingpkgskeep+=("$j")
                repoconflictingpkgsrm+=("$k")
                repoprovidersconflictingpkgs+=("$j")
                Qprovides=($(expac -Ss '%S' "^$k$"))
                [[ ! " ${Qprovides[*]} ${repoconflictingpkgsrm[*]} " =~ " $k " ]] && CheckRequires "$k"
                break
            else
                Note "f" $"unresolvable package conflicts detected"
                Note "f" $"failed to prepare transaction (conflicting dependencies)"
                if (( UPGRADE )); then
                    Qrequires=($(expac -Q '%N' "$i"))
                    Note "e" $"$j and $k are in conflict (required by ${Qrequires[*]})" "$E_INSTALL_DEPS_FAILED"
                else
                    Note "e" $"$j and $k are in conflict" "$E_INSTALL_DEPS_FAILED"
                fi
            fi
        fi
        Qprovides=($(expac -Ss '%S' "^$k$"))
        [[ ! " ${Qprovides[*]} " =~ " $k " ]] && CheckRequires "$k"
    done
}

# Check which packages are going to be reinstalled
# Usage: ReinstallChecks
ReinstallChecks() {
    local i depsAtmp
    # global aurpkgs aurdepspkgs deps aurconflictingpkgs depsAname depsQver depsAver depsAood depsAmain
    depsAtmp=("${depsAname[@]}")
    for i in "${!depsAtmp[@]}"; do
        [[ ! " ${aurpkgs[*]} " =~ " ${depsAname[$i]} " ]] ||
            [[ " ${aurconflictingpkgs[*]} " =~ " ${depsAname[$i]} " ]] && continue
        [[ ! "${depsQver[$i]}" || "${depsQver[$i]}" = '%' ]] ||
            [[ "$(vercmp "${depsAver[$i]}" "${depsQver[$i]}")" -gt 0 ]] && continue
        (( ! INSTALLPKG )) && [[ ! " ${aurdepspkgs[*]} " =~ " ${depsAname[$i]} " ]] && continue
        if [[ "${depsAname[$i]}" =~ $vcs ]]; then
            Note "w" $"${WHITE}${depsAname[$i]}${ALL_OFF} latest revision -- fetching"
        else
            if (( ! NEEDED )); then
                Note "w" $"${WHITE}${depsAname[$i]}-${depsQver[$i]}${ALL_OFF} is up to date -- reinstalling"
            else
                Note "w" $"${WHITE}${depsAname[$i]}-${depsQver[$i]}${ALL_OFF} is up to date -- skipping"
                mapfile -t < <(printf ' %s \n' "${deps[@]}") deps
                deps=($(printf '%s\n' "${deps[@]// ${depsAname[$i]} /}"))
                unset "depsAname[$i]" "depsQver[$i]" "depsAver[$i]" "depsAood[$i]" "depsAmain[$i]"
            fi
        fi
    done
    (( NEEDED )) && depsAname=("${depsAname[@]}") && depsQver=("${depsQver[@]}") &&
        depsAver=("${depsAver[@]}") && depsAood=("${depsAood[@]}") && depsAmain=("${depsAmain[@]}")
    NothingToDo "${deps[@]}"
}

# Check out of date packages
# Usage: OutOfDateChecks
OutOfDateChecks() {
    local i
    # global depsAname depsAver depsAood
    for i in "${!depsAname[@]}"; do
        (( depsAood[$i] > 0 )) &&
            Note "w" $"${WHITE}${depsAname[$i]}-${depsAver[$i]}${ALL_OFF} has been flagged ${RED}out of date${ALL_OFF} on ${YELLOW}$(printf '%(%c)T\n' "${depsAood[$i]}")${ALL_OFF}"
    done
}

# Check orphaned packages
# Usage: OrphanChecks
OrphanChecks() {
    local i
    # global depsAname depsAver depsAmain
    for i in "${!depsAname[@]}"; do
        [[ "${depsAmain[$i]}" = 'null' || ! "${depsAmain[$i]}" ]] &&
            Note "w" $"${WHITE}${depsAname[$i]}-${depsAver[$i]}${ALL_OFF} is ${RED}orphaned${ALL_OFF} in AUR"
    done
}

# Check that all dependencies are satisfied
# Usage: CheckRequires <packages>
CheckRequires() {
    local Qrequires=($(expac -Q '%N' "$@"))
    if [[ "${Qrequires[*]}" ]]; then
        Note "f" $"failed to prepare transaction (could not satisfy dependencies)"
        Note "e" $"${Qrequires[@]}: requires $@" "$E_INSTALL_DEPS_FAILED"
    fi
}

# vim:set ts=4 sw=4 et:
