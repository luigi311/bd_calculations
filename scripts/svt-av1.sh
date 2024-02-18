#!/usr/bin/env bash

set -e

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
    help="$(cat <<EOF
Test svt-av1, will gather stats such as file size, duration of first pass and second pass and put them in a csv.
Usage: 
    ./encoder.sh [options]
Example:
    ./encoder.sh -i video.mkv -t 8 --q --quality 30 
Encoding Options:
    -i/--input   [file]     Video source to use                                                 (default video.mkv)
    -o/--output  [folder]   Output folder to place encoded videos and stats files               (default output)
    -t/--threads [number]   Amount of threads to use                                            (default 4)
    --quality    [number]   Bitrate for vbr, cq-level for q/cq mode, crf                        (default 50)
    --preset     [number]   Set encoding preset, higher is faster                               (default 6)
    --crf                   Use q mode                                                          (default)
    --vbr                   Use vbr mode 
    --decode                Test decoding speed
EOF
            )"
            echo "$help"
}

OUTPUT="output"
INPUT="video.mkv"
THREADS=-1
PRESET=0
VBR=-1
CRF=-1
QUALITY=50
PASS=1
DECODE=-1
COMMIT="-1"

# Source: http://mywiki.wooledge.org/BashFAQ/035
while :; do
    case "$1" in
        -h | -\? | --help)
            help
            exit 0
            ;;
        -i | --input)
            if [ "$2" ]; then
                INPUT="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        -o | --output)
            if [ "$2" ]; then
                OUTPUT="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        -t | --threads)
            if [ "$2" ]; then
                THREADS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --vbr)
            if [ "$CRF" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            VBR=1
            ;;
        --crf)
            if [ "$VBR" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            CRF=1
            ;;
        --quality)
            if [ "$2" ]; then
                QUALITY="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --preset)
            if [ "$2" ]; then
                PRESET="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --pass)
            if [ "$2" ]; then
                PASS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --commit)
            if [ "$2" ]; then
                COMMIT="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --decode)
            DECODE=1
            ;;
        --) # End of all options.
            shift
            break
            ;;
        -?*)
            echo "Unknown option: $1 ignored"
            ;;
        *) # Default case: No more options, so break out of the loop.
            break ;;
    esac
    shift
done

if [ "$COMMIT" = "-1" ]; then
    die "Please set commit hash"
fi

if [ "$THREADS" -eq -1 ]; then
    THREADS=$(( 4 < $(nproc) ? 4 : $(nproc) ))
fi

INPUT_NAME=$(basename "$INPUT")
INPUT_NAME="${INPUT_NAME%.*}"

# Set the encoding mode of vbr/crf along with a default
if [ "$VBR" -ne -1 ]; then
    TYPE="vbr${QUALITY}"
    QUALITY_SETTINGS="--rc 1 --tbr ${QUALITY}"
elif [ "$CRF" -ne -1 ]; then
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--rc 0 --crf ${QUALITY}"
else
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--rc 0 --crf ${QUALITY}"
fi

mkdir -p "${OUTPUT}/${TYPE}"
BASE="ffmpeg -y -hide_banner -loglevel error -i \"${INPUT}\" -strict -1 -pix_fmt yuv420p10le -f yuv4mpegpipe - | SvtAv1EncApp --progress 0 -i stdin --lp ${THREADS} --preset ${PRESET} --tile-columns 2 --tile-rows 1 ${QUALITY_SETTINGS}"

if [ "$PASS" -eq 1 ]; then
    FIRST_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 1 -b \"${OUTPUT}/${TYPE}/${TYPE}.ivf\"" 2>&1 | awk ' /Sec/ { print $2 }')
    SECOND_TIME=0
else
    FIRST_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 2 --pass 1 --stats \"${OUTPUT}/${TYPE}/${TYPE}.log\" -b /dev/null" 2>&1 | awk ' /Sec/ { print $2 }')
    SECOND_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 2 --pass 2 --stats \"${OUTPUT}/${TYPE}/${TYPE}.log\" -b \"${OUTPUT}/${TYPE}/${TYPE}.ivf\"" 2>&1 | awk ' /Sec/ { print $2 }')
fi

ERROR=$(ffmpeg -y -hide_banner -loglevel error -i "${OUTPUT}/${TYPE}/${TYPE}.ivf" -c:v copy "${OUTPUT}/${TYPE}/${TYPE}.mkv" 2>&1)
if [ -n "$ERROR" ]; then
    rm -rf "${OUTPUT}/${TYPE}"
    die "SVT-AV1 failed to encode ${TYPE}"
fi

if [ "$DECODE" -ne -1 ]; then
    DECODE_TIME=$(env time --format="Sec %e" bash -c " dav1d -i \"${OUTPUT}/${TYPE}/${TYPE}.ivf\" -o /dev/null" 2>&1 | awk ' /Sec/ { print $2 }')
else
    DECODE_TIME=0
fi

SIZE=$(du -k "${OUTPUT}/${TYPE}/${TYPE}.ivf" | awk '{print $1}')
BITRATE=$(ffprobe -i "${OUTPUT}/${TYPE}/${TYPE}.mkv" 2>&1 | awk ' /bitrate:/ { print $(NF-1) }')

rm -f "${OUTPUT}/${TYPE}/${TYPE}.log" &&
rm -f "${OUTPUT}/${TYPE}/${TYPE}.ivf" &&
rm -f "${OUTPUT}/${TYPE}/${TYPE}.json" 

echo -n "svt-av1,${COMMIT},${PRESET},${INPUT_NAME},${SIZE},${TYPE},${BITRATE},${FIRST_TIME},${SECOND_TIME},${DECODE_TIME}" > "${OUTPUT}/${TYPE}/${TYPE}.stats"
