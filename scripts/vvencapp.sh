#!/usr/bin/env bash

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
    help="$(cat <<EOF
Test vvencapp, will gather stats such as file size, duration of first pass and second pass and put them in a csv.
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
    QUALITY_SETTINGS="--bitrate ${QUALITY}k"
elif [ "$CRF" -ne -1 ]; then
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--qp ${QUALITY}"
else
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--qp ${QUALITY}"
fi

mkdir -p "${OUTPUT}/${TYPE}"
BASE="ffmpeg -y -hide_banner -loglevel error -i \"${INPUT}\" -strict -1 -pix_fmt yuv420p10le -f yuv4mpegpipe - | vvencapp -i - --y4m -c yuv420_10 --threads ${THREADS} --preset ${PRESET} ${QUALITY_SETTINGS}"

if [ "$PASS" -eq 1 ]; then
    FIRST_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 1 -o \"${OUTPUT}/${TYPE}/${TYPE}.h266\" " 2>&1 > "${OUTPUT}/${TYPE}/${TYPE}.info" | awk ' /Sec/ { print $2 }')
    SECOND_TIME=0
else
    FIRST_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 2 --pass 1 --rcstatsfile \"${OUTPUT}/${TYPE}/${TYPE}.json\" -o /dev/null" 2>&1 > /dev/null | awk ' /Sec/ { print $2 }')
    SECOND_TIME=$(env time --format="Sec %e" bash -c " ${BASE} --passes 2 --pass 2 --rcstatsfile \"${OUTPUT}/${TYPE}/${TYPE}.json\" -o \"${OUTPUT}/${TYPE}/${TYPE}.h266\"" 2>&1 > "${OUTPUT}/${TYPE}/${TYPE}.info" | awk ' /Sec/ { print $2 }')   
fi

if [ "$DECODE" -ne -1 ]; then
    DECODE_TIME=$(env time --format="Sec %e" bash -c " vvc_decoder -b \"${OUTPUT}/${TYPE}/${TYPE}.h266\" -o \"${OUTPUT}/${TYPE}/${TYPE}.yuv\"" 2>&1 > /dev/null | awk ' /Sec/ { print $2 }')
else
    DECODE_TIME=0
fi

# Get resolution and fps from ffprobe
FFPROBE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of default=nw=1:nk=1 "${INPUT}")
read RESOLUTION FPS <<< $(echo "${FFPROBE}" | awk 'NR==1{resolution=$0} NR==2{resolution=resolution"x"$0} NR==3{fps=$0} END{print resolution, fps}')

# Convert to y4m
ffmpeg -y -hide_banner -loglevel error -s "${RESOLUTION}" -r "${FPS}" -pix_fmt yuv420p10le -i "${OUTPUT}/${TYPE}/${TYPE}.yuv" -c copy -strict -1 "${OUTPUT}/${TYPE}/${TYPE}.y4m"

SIZE=$(du -k "${OUTPUT}/${TYPE}/${TYPE}.h266" | awk '{print $1}')
BITRATE=$(awk '/stats summary: frame=/ {print $(NF-1)}' "${OUTPUT}/${TYPE}/${TYPE}.info")

rm -f "${OUTPUT}/${TYPE}/${TYPE}.log" &&
rm -f "${OUTPUT}/${TYPE}/${TYPE}.yuv" &&
rm -f "${OUTPUT}/${TYPE}/${TYPE}.h266" &&
rm -f "${OUTPUT}/${TYPE}/${TYPE}.info"

echo -n "vvencapp,${COMMIT},${PRESET},${INPUT_NAME},${SIZE},${TYPE},${BITRATE},${FIRST_TIME},${SECOND_TIME},${DECODE_TIME}" > "${OUTPUT}/${TYPE}/${TYPE}.stats"
