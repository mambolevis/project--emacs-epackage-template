#!/bin/sh
#
#   Copyright
#
#       Copyright (C) 2010-2015 Jari Aalto <jari.aalto@cante.net>
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

unset TEST

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

InitEpackageDir ()
{
    EPKGDIR=$(cd $(dirname ${1:-.}); pwd)
}

Initialize ()
{
    if [ ! "$1" ] || [ ! -f "$1" ]; then
	Die "ERROR: Initialize(): Epackage info file missing"
    fi

    infofile=$1

    # Define global variables

    PKG=$(awk '/^[Pp]ackage:/  {print $2}' "$infofile" )

    VCSNAME=$(awk '/^[V]cs-[Tt]ype:/  {print $2}' "$infofile" )

    # This may be multiline field for http:
    #
    #  Vcs-Args: http://example.com/FILE1
    #    http://example.com/FILE2
    #    http://example.com/FILE3

    ARGS=$(awk '/^[Vv]cs-[Ar]gs:/  {print $2}' "$infofile" )

    URL=$(awk '
	header == 1 && /^[A-Za-z-]+:/ {
	    exit
        }

	header == 0 && /^[Vv]cs-[Uu]rl:/ {
	    sub("^[Vv]cs-[Uu]rl:","")
	    gsub(" ","")
	    header = 1
        }

	header == 1 {
	    if (args)
    	        args = args " " $0
	    else
	        args = $0
	}

	END {
	    print args
	}
	' "$infofile" )

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
    # If running in test mode, Add pound sign in front so that user
    # can simply "program > script.sh".
    #
    # Yes, the output will go to stderr and it would not be in the
    # script but it looks more clear to user that the message is
    # *safe* to redirect than without the pound sign:
    #
    #    command
    #    # Message
    #    command

    echo "${TEST+#}${TEST+ }$*" >&2
}


Die ()
{
    Warn "$*"
    exit 1
}

Run ()
{
    case "$*" in
        *\|*)   # PIPE
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

VcsGitRemoteUpstream ()
{
    awk '/remote .*upstream/ {i++} i == 1 && ! /[[]/ {print}' \
	.git/config
}

VcsGitConfig ()
{
    # No git, nothing to check

    [ -d .git ] || return 1

    # If there is a remote "upstream" already, use it to fetch sources.

    if VcsGitRemoteUpstream | grep -i "url.*=" ; then
	echo "\
Note: Upstream probably already in a Git branch, use:
    git checkout upstream
    git pull
    git log -1
    git tag upstream/YYYY-MM-DD{commit date}--git-COMMIT{7hex}

    # Merge to epackage branch master
    git checkout master
    git merge upstream/YYYY-MM-DD{commit date}--git-COMMIT{7hex}"

    else
	echo "\
Please follow upstream directly in a Git branch:
    git remote add upstream $URL
    git fetch upstream
    git checkout --track -b upstream upstream/master
    git tag upstream/YYYY-MM-DD{commit date}--git-COMMIT{7hex}

    # Merge to epackage branch master
    git checkout master
    git merge upstream/YYYY-MM-DD--git-COMMIT"

    fi
}

Log ()
{
    case "$VCSNAME" in
	*git*)
	    Run git log --first-parent --date=short \
		--pretty='format:%h %ci %s%d' \
		--max-count=${1:-1}
	    ;;
	*bzr*)
	    Run bzr log --limit ${1:-1}
	    ;;
	*hg*)
	    Run hg log --limit ${1:-1}
	    ;;
	*svn*)
	    Run svn log --limit ${1:-1}
	    ;;
    esac
}

Vcs ()
{
    cmd=clone

    case "$VCSNAME" in
	*bzr*)  cmd=branch ;;
    esac

    if [ ! -d "$VCSDIR" ]; then
        Run "$VCSNAME" $cmd "$URL" "$VCSDIR"
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
        ( cd "$VCSDIR" && Revno && Log )
    else
    (
	Run cd "$VCSDIR" &&
	Run "$VCSNAME" update &&
	Revno &&
	Log
    )
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

Wget1 ()
{
    url1=$1
    args2=$2

    # Option --timestamping cannot me used. Git does not preserve time
    # stamps in directory, so any "git reset", "git clone" commands
    # would use current time and invalidate original time stamps.
    #
    # NOTE: there is no way to force overwriting every file when
    # downloading files using wget.

    set -- $url1

    unset optionwget
    optionwget_noquote=$url1

    if [ $# -eq 1 ]; then
        optionwget="$(basename $url1)"	# Force overwrite
	unset optionwget_noquote
    fi

    # Quote file name for spcecial character in -O option

    Run wget --user-agent="$UAGENT" \
	--no-check-certificate \
	${optionwget:+-O} \
	${optionwget:+"$optionwget"} \
	${optionwget_noquote:-"$url1"} \
	$args2
}

Hex2Character ()
{
    # Convert HEX encoding to plain text
    echo $* | perl -ane \
    '
	s/(%([0-9a-f][0-9a-f]))/sprintf qq(%c), hex $2/egi;
	print
    '
}

Wget ()
{
    url=$1
    args=$2
    unset slow

    # emacswiki does not allow donwloading multiple files in
    # rapid successions (considered spidering)

    case "$url" in
	*emacswiki* )
	    slow=slow
	    ;;
    esac

    case "$*" in
	*%*)
	    url=$(Hex2Character $url)
	    ;;
    esac

    if [ ! "$slow" ]; then
	Wget1 "$url" "$args"
	return $?
    fi

    unset statuswget

    Warn "NOTE: Please wait, current site has limits on download parameters"

    for i in $url
    do
	Wget1 "$i" "$args"
	statuswget=$?
	Run sleep 4
    done

    return $statuswget
}

Main ()
{
    unset args

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
            -*)
                Die "ERROR: Unknown option $1. See --help"
                ;;
	    *)	args="$args $1"
		shift
		;;
        esac
    done

    if [ "$args" ]; then
	set -- $args
    elif [ ! "$1" ] && [ -f epackage/info ]; then
	set -- epackage/info
    fi

    if [ ! "$1" ]; then
        Warn "ERROR: Missing ARG 1, FILE (typically epackage/info)"
    fi

    if [ ! -f "$1" ]; then
        Die "ERROR: file does not exists: $1"
    fi

    InitEpackageDir $1
    Initialize $1	    # Parse epacakge/info for URL, ARGS ...

    case "$VCSNAME" in
        http)
            Run cd "$EPKGDIR/.."
            Wget "$URL" "$ARGS"
            return $?
            ;;

        [a-z]*)

            if [ "$VCSNAME" = "git" ]; then
	        VcsGitConfig "$URL" && return 0

		Warn "[WARN] For Git, you should use: \
		'git remote add upstream $URL' and work through it directly."

	    fi
return 1
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
