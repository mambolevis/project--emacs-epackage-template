#!/bin/sh
#
#   Copyright
#
#       Copyright (C) 2010-2012 Jari Aalto <jari.aalto@cante.net>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#   Depends
#
#       Required
#       - POSIX Shell
#
#       Depending on used transport (Vcs-Type field in file "info"):
#       - wget, git, hg, bzr, cvs, svn

set -e

VCSDIR="upstream"                               # The VCS download directory
UAGENT="Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.9.1.3) Gecko/20090913 Firefox/3.5.3";

Help ()
{
    echo "\
SYNOPSIS
    $0 [--help | --test] info

DESCRIPTION

    Examine Epackage 'info' file and download upstream.

    A shell script to download Emacs epackages. Reads information from
    epackage/info file. If the Field 'Vcs-Type' is \"http\", download
    single file to \"epackage/..\" directory. If type is anything
    else, download repository pointed by field 'Vcs-Url' into
    subdirectory \"epackage/$VCSDIR\" and copy all files recursively
    to \"epackage/..\".

OPTIONS

    -t, --test
        Run in test mode. Do not actually do anything.

    -h, --help
        Display this help text.

AUTHOR

    Jari Aalto <jari.aalto@cante.net>

    Released under license GNU GPL version 2 or (at your option) any later
    version. For more information about license, visit
    <http://www.gnu.org/copyleft/gpl.html>."

    exit 0
}

Initialize ()
{
    # Define global variables

    infofile=$EPKGDIR/info

    PKG=$(awk '/^[Pp]ackage:/  {print $2}' "$infofile" )

    VCSNAME=$(awk '/^[V]cs-[Tt]ype:/  {print $2}' "$infofile" )

    URL=$(awk '/^[Vc]cs-[Uu]rl:/  {print $2}' "$infofile" )

    ARGS=$(awk '/^[Vv]cs-[Aa]rgs:/ {sub("Vcs-Args:",""); print }' \
           "$infofile" )

    if [ ! "$PKG" ]; then
	Die "ERROR: Can't read Package: field from $infofile"
    fi

    if [ ! "$VCSNAME" ]; then
	Die "ERROR: Can't read Vcs-Type: field from $infofile"
    fi

    if [ ! "$URL" ]; then
	Die "ERROR: Can't read Vcs-Url: field from $infofile"
    fi

    unset infofile
}

Warn ()
{
    echo "$*" >&2
}


Die ()
{
    Warn "$*"
    exit 1
}

Run ()
{
    case "$*" in
        *\|*)
            if [ "$TEST" ]; then
                echo "$*"
            else
                eval "$@"
            fi
            ;;
        *)
            ${TEST:+echo} "$@"
            ;;
    esac
}

UpdateLispFiles ()
{
    dir="$1"

    if [ "$VCSNAME" = "http" ]; then
        return 0                        # Skip
    fi

    cd "$VCSDIR"

    Run tar -cf - \
      $(find . -type d \( -name .$VCSNAME -o -name .git \) -prune  \
        -a ! -name .$VCSNAME \
        -a ! -name .git \
        -o \( -type f -a ! -name .${vcs}ignore -a ! -name "*.elc" \)
       ) |
    Run tar --directory "$EPKGDIR/.." -xvf -
}

GitLog ()
{
    Run git log --max-count=1 --date=short --pretty='format:%h %ci %s%n' ||
    Run git rev-parse HEAD "|" cut -c1-7
}

Revno ()
{
    # All other VCS's will display revision during "pull/update"

    case "$VCSNAME" in
        git)
            GitLog
            ;;
        *)
            ;;
    esac
}

Vcs ()
{
    if [ ! -d "$VCSDIR" ]; then
        Run "$VCSNAME" clone "$URL" "$VCSDIR"
        ( cd "$VCSDIR" && Revno )
    else
        ( Run cd "$VCSDIR" && Run "$VCSNAME" pull && Revno )
    fi
}

Svn ()
{
    url="$1"

    if [ ! -d "$VCSDIR" ]; then
        Run "$VCSNAME" co "$URL" "$VCSDIR"
        ( cd "$VCSDIR" && Revno )
    else
        ( Run cd "$VCSDIR" && Run "$VCSNAME" update && Revno )
    fi
}

Cvs ()
{
    url="$1"

    if [ -d "$VCSDIR" ]; then
        echo "# For asked password, possibly press RETURN..."
        Run cvs -d "$url" login
        Run cvs -d "$url" co -d "$VCSDIR" $ARGS

    else
        # -f = Do not read ~/.cvsrc
        # -d = Create missing directories
        # -I = Do not use ~/.cvsignore (show all files)

        ( Run cd "$VCSDIR" && Run cvs -f update -d -I\! )
    fi
}

Main ()
{
    if [ ! "$1" ] && [ -f epackage/info ]; then
	set -- epackage/info
    fi

    if [ ! "$1" ]; then
        Warn "ERROR: Missing ARG 1, FILE (typically epackage/info)"
    fi

    if [ ! -f "$1" ]; then
        Die "ERROR: file does not exists: $1"
    fi

    EPKGDIR=$(cd $(dirname $1); pwd)

    Initialize

    for arg in "$@"                     # Command line options
    do
        case "$arg" in
            -h | --help)
                shift
                Help
                ;;
            -t | --test)
                shift
                TEST="test"
                ;;
        esac
    done

    if [ "$VCSNAME" = "git" ]; then
        Warn "[WARN] For Git, you should use: \
'git remote add upstream $URL' and work through it directly."
    fi

    case "$VCSNAME" in
        http)
            Run cd "$EPKGDIR/.."
            Run wget --user-agent="$UAGENT" \
                 --no-check-certificate \
                 --timestamping \
                "$URL" \
                "$ARGS"
            return $?
            ;;

        [a-z]*)
            Run cd "$EPKGDIR"

            if [ "$VCSNAME" = "cvs" ]; then
                Cvs "$URL"
            elif [ "$VCSNAME" = "svn" ]; then
                Svn "$URL"
            else
                Vcs "$VCSNAME" "$URL"
            fi
            ;;

        *)  Warn "[WARN] Unknown 'Vcs-Type: $VCSNAME' 'Vcs-Url: $URL'"
            return 1
            ;;
    esac

    UpdateLispFiles "$VCSNAME" "$VCSDIR"
}

Main "$@"

# End of file
