#!/bin/bash

# * Notes
#
# +  If the target window moves, the video does not move with it.

# * Defaults

cursor=1
framerate=30
target=fullscreen
output_file=bashcaster.mp4

gif_read_duration=2.5

confirm=true
force=

left=0
top=0
width=0
height=0

# * Functions

function check_program {
    type $1 >/dev/null \
        || error "Program not found: $1"
}

function confirm {
    if [[ $confirm ]]
    then
        yad --title "bashcaster" --text-align center --text "\n $@ \n"
    else
        true
    fi
}

function record_video {
    ffmpeg -f x11grab \
           -video_size ${width}x${height} \
           -framerate $framerate \
           -i $DISPLAY+${left},${top} \
           -draw_mouse $cursor \
           "$1" &
    ffmpeg_pid=$!

    yad --notification --image media-playback-stop --text "Click to stop recording"
    kill $ffmpeg_pid
    wait $ffmpeg_pid
}

function record_gif {
    # Record video to an MP4, then convert to GIF file ($1) to improve color
    # palette.  See <https://engineering.giphy.com/how-to-make-gifs-with-ffmpeg/>.

    local gif_file="$1"
    local temp_file="$(mktemp).mp4"

    trap "rm -fv $temp_file" EXIT INT TERM

    record_video "$temp_file"
    debug "Video recorded.  Converting to GIF..."
    convert_to_gif "$temp_file" "$gif_file"
}

function convert_to_gif {
    # Convert video file ($1) to GIF file ($2, which should end in ".gif").

    ffmpeg -i "$1" \
           -t $gif_read_duration \
           -filter_complex "[0:v] split [a][b];[a] palettegen [p];[b][p] paletteuse" \
           "$2"
}

function set_to_window_dimensions {
    confirm "Press OK, then click the window you want to record." || die "Canceled."

    local window_dimensions=$(xwininfo)

    [[ $window_dimensions =~ "Absolute upper-left X:"[[:space:]]+([[:digit:]]+) ]] && left=${BASH_REMATCH[1]}
    [[ $window_dimensions =~ "Absolute upper-left Y:"[[:space:]]+([[:digit:]]+) ]] && top=${BASH_REMATCH[1]}
    [[ $window_dimensions =~ "Width:"[[:space:]]+([[:digit:]]+) ]] && width=${BASH_REMATCH[1]}
    [[ $window_dimensions =~ "Height:"[[:space:]]+([[:digit:]]+) ]] && height=${BASH_REMATCH[1]}
}

function set_to_screen_dimensions {
    local screen_dimensions=$(xprop -root _NET_DESKTOP_GEOMETRY)

    if [[ $screen_dimensions =~ "_NET_DESKTOP_GEOMETRY(CARDINAL) = "([[:digit:]]+)", "([[:digit:]]+) ]]
    then
        width=${BASH_REMATCH[1]}
        height=${BASH_REMATCH[2]}
    else
        die "Unable to get screen dimensions from xprop."
    fi
}

# TODO: Function to get frame extents.  Like:
# extents=$(xprop _NET_FRAME_EXTENTS -id "$aw" | grep "NET_FRAME_EXTENTS" | cut -d '=' -f 2 | tr -d ' ')
# bl=$(echo $extents | cut -d ',' -f 1) # width of left border
# br=$(echo $extents | cut -d ',' -f 2) # width of right border
# t=$(echo $extents | cut -d ',' -f 3)  # height of title bar
# bb=$(echo $extents | cut -d ',' -f 4) # height of bottom border

# MAYBE: Function to get screen size, if needed.

# ** Utility

function debug {
    if [[ $debug ]]
    then
        function debug {
            echo "DEBUG: $@" >&2
        }
        debug "$@"
    else
        function debug {
            true
        }
    fi
}
function error {
    echo "ERROR: $@" >&2
    ((errors++))  # Initializes automatically
}
function die {
    error "$@"
    exit $errors
}
function usage {
    cat <<EOF
$0 [OPTIONS] OUTPUT-FILE

Bashcaster is a simple script that uses ffmpeg to record screencasts
to videos or GIFs.  It can record the whole screen or a window.  It
can optionally optimize GIFs with gifsicle.

OUTPUT-FILE should end with the desired video type's extension,
e.g. ".mp4" or ".gif".

Click the stop-icon tray notification to stop recording.

Options
  -d, --debug  Print debug info
  -h, --help   I need somebody!

  --force   Overwrite output file if it exists

  -F, --fullscreen  Record the whole screen (currently the default anyway)
  -W, --window      Select and record a window rather than the whole screen

  -c, --no-cursor   Don't record mouse cursor
  -o, --optimize    Optimize GIF with gifsicle
  -y, --no-confirm  Don't ask for confirmation before recording

  -f, --framerate NUMBER  Video framerate (default: 30)

  -l, --left NUMBER  Video left edge position (default: 0)
  -t, --top  NUMBER  Video top edge position (default: 0)

  -h, --height NUMBER  Video height
  -w, --width  NUMBER  Video width
EOF
}

# * Args

args=$(getopt -n "$0" -o cdf:Fh:now:Wy -l debug,framerate:,force,fullscreen,height:,help,no-confirm,no-cursor,optimize,width:,window -- "$@") || { usage; exit 1; }
eval set -- "$args"

while true
do
    case "$1" in
        -c|--no-cursor)
            cursor=0
            ;;
        -d|--debug)
            debug=true
            ;;
        -f|--framerate)
            shift
            framerate="$1"
            ;;
        -F|--fullscreen)
            target="fullscreen"
            ;;
        --force)
            force=true
            ;;
        --help)
            usage
            exit
            ;;
        -h|--height)
            shift
            height="$1"
            ;;
        -o|--optimize)
            check_program gifsicle
            optimize=true
            ;;
        -w|--width)
            shift
            width="$1"
            ;;
        -W|--window)
            target="window"
            ;;
        -y|--no-confirm)
            unset confirm
            ;;
        --)
            # Remaining args (required; do not remove)
            shift
            rest=("$@")
            break
            ;;
    esac

    shift
done

debug "ARGS: $args"
debug "Remaining args: ${rest[@]}"
message="${rest[@]}"

# * Main

# ** Check for requirements

for program in ffmpeg xprop xwininfo yad
do
    check_program $program
done
if [[ $errors ]]
then
    die "Please install the required programs."
fi

# ** Check output file

# Concat filename.
output_file="$rest"

# Ensure file doesn't exist.
if [[ -f $output_file ]]
then
    if [[ $force ]]
    then
        mv -v --backup=existing $output_file $output_file.bashcaster.bak
    else
        die "Output file exists and no --force: $output_file"
    fi
fi

# ** Prepare window data

case $target in
    fullscreen)
        set_to_screen_dimensions
        ;;
    window)
        set_to_window_dimensions
        ;;
esac

# ** Record video

confirm "Press OK, then recording will start in 1 second.  Click on the tray icon to stop." \
    || die "Canceled."
sleep 1

if [[ $output_file =~ \.gif$ ]]
then
    record_gif "$output_file"

    if [[ $optimize ]]
    then
        debug "Optimizing..."
        gifsicle -O3 --batch -i "$output_file"
    fi
else
    record_video "$output_file"
fi
