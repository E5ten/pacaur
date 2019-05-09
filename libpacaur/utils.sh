#!/usr/bin/env bash
#
#   utils.sh -- utility functions
#   functions: Proceed Note GetLength NothingToDo SudoV CommArr
#

[[ -v LIBPACAUR_UTILS_SH ]] && return
LIBPACAUR_UTILS_SH=1

# Print string and accept or cancel operation based on user input
# Usage: Proceed <default option ("y" or "n")> <string>
Proceed() {
    local answer ret readline=0

    [[ "$TERM" = dumb ]] || (( CLEANCACHE )) && readline=1
    case "$1" in
        y)  printf "${BLUE}%s${ALL_OFF} ${WHITE}%s${ALL_OFF}" "::" "$2 [Y/n] "
            (( NOCONFIRM )) && printf '\n' && return 0
            while true; do
                if (( readline )); then
                    read -r answer
                else
                    read -s -r -n 1 answer
                fi
                case "$answer" in
                    [Yy]|'') ret=0; break;;
                    [Nn]) ret=1; break;;
                    *) (( readline )) && ret=1 && break;;
                esac
            done;;
        n)  printf "${BLUE}%s${ALL_OFF} ${WHITE}%s${ALL_OFF}" "::" "$2 [y/N] "
            (( NOCONFIRM )) && printf '\n' && return 0
            while true; do
                if (( readline )); then
                    read -r answer
                else
                    read -s -r -n 1 answer
                fi
                case "$answer" in
                    [Nn]|'') ret=0; break;;
                    [Yy]) ret=1; break;;
                    *) (( readline )) && ret=0 && break;;
                esac
            done;;
    esac
    (( ! readline )) && printf '%s\n' "$answer"
    return "$ret"
}

# Print string with format type
# Usage: Note <letter representing format> <string>
# Formats: info (i) warning (w) fail (f) error (e)
Note() {
    case "$1" in
        i) printf '%b\n' "${BLUE}::${ALL_OFF} $2";;              # info
        w) printf '%b\n' "${YELLOW}warning:${ALL_OFF} $2" >&2;;  # warn
        f) printf '%b\n' "${RED}error:${ALL_OFF} $2" >&2;;       # fail
        e) printf '%b\n' "${RED}error:${ALL_OFF} $2" >&2;        # error
            exit "$3";;
    esac
}

# Get the length of a string
# Usage: GetLength <string(s)>...
GetLength() {
    local length=0 i
    for i in "$@"; do
        [[ "${#i}" -gt "$length" ]] && length="${#i}"
    done
    printf '%s\n' "$length"
}

# Print that there is nothing to do if there is no argument, if argument isn't
# empty just return
# Usage: NothingToDo <argument(s)>
NothingToDo() {
    [[ ! "$*" ]] && printf '%s\n' $" there is nothing to do" && exit "$E_OK" || return 0
}

# Keep sudo permissions active in the background to prevent further password
# prompts
# Usage: SudoV &
SudoV() {
    > "$tmpdir/pacaur.sudov.lck"
    while [[ -e "$tmpdir/pacaur.sudov.lck" ]]; do
        sudo "$PACMAN" -V > /dev/null
        sleep 298
    done
}

# Compare two bash arrays using comm and sort
# Usage: CommArr <first array> <second array> <args to comm>
# Arguments to comm: -12 for common elements, -13 for elements unique to second array
CommArr() {
    local array1="$1[@]" array2="$2[@]"
    comm <(printf '%s\n' "${!array1}" | sort -u) <(printf '%s\n' "${!array2}" | sort -u) "$3"
}

# vim: set ts=4 sw=4 et:
