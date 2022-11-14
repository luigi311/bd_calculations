#!/usr/bin/env bash

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
    help="$(cat <<EOF
Test x265 flag, will gather stats such as file size, duration of first pass and second pass and put them in a csv.
Usage: 
    ./encoder.sh [options]
Example:
    ./encoder.sh -i video.mkv -f "--kf-max-dist=360 --enable-keyframe-filtering=0" -t 8 --q --quality 30 
Encoding Options:
    -i/--input   [file]     Video source to use                                                 (default video.mkv)
    -o/--output  [folder]   Output folder to place encoded videos and stats files               (default output)
    -f/--flag    [string]   Flag to test, surround in quotes to prevent issues                  (default baseline)
    -t/--threads [number]   Amount of threads to use                                            (default 4)
    --quality    [number]   Bitrate for vbr, cq-level for q/cq mode, crf                        (default 50)
    --preset     [number]   Set encoding preset, aomenc higher is faster, x265 lower is faster  (default 6)
    --pass       [number]   Set amount of passes                                                (default 1)
    --vbr                   Use vbr mode (applies to aomenc/x265 only)
    --crf                   Use crf mode (applies to x265 only)                                 (default)
EOF
            )"
            echo "$help"
}

OUTPUT="output"
INPUT="video.mkv"
FLAG="baseline"
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
        -f | --flag)
            if [ "$2" ]; then
                FLAG="$2"
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

# Remove any potential characters that might cause issues in folder names
FOLDER1=$(echo "$FLAG" | sed ' s/--//g; s/=//g; s/ //g; s/:/_/g')
# Get last 120 characters of flags for folder name to prevent length issues
if [ "${#FOLDER1}" -ge 120 ]; then
    FOLDER=${FOLDER1: -120}
else
    FOLDER="$FOLDER1"
fi

# Baseline is with no flag, rest requires a : due to x265 parms format
if [ "$FLAG" == "baseline" ]; then
    FLAG=""
else
    FLAG=":${FLAG}"
fi

# Set the encoding mode of vbr/crf along with a default
if [ "$VBR" -ne -1 ]; then
    TYPE="vbr${QUALITY}"
    QUALITY_SETTINGS="--bitrate ${QUALITY}"
elif [ "$CRF" -ne -1 ]; then
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--crf ${QUALITY}"
else
    TYPE="crf${QUALITY}"
    QUALITY_SETTINGS="--crf ${QUALITY}"
fi

mkdir -p "$OUTPUT/${FOLDER}_${TYPE}"
BASE="ffmpeg -y -hide_banner -loglevel error -i \"$INPUT\" -strict -1 -pix_fmt yuv420p10le -f yuv4mpegpipe - | x265 --log-level 0 --no-progress --input - --y4m --pools ${THREADS} --preset ${PRESET} ${QUALITY_SETTINGS}"

if [ "$VBR" -ne -1 ] || [ "$PASS" -eq 1 ]; then
    FIRST_TIME=$(env time --format="Sec %e" bash -c " $BASE --pass 1 --stats \"$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.log\"" 2>&1 | awk ' /Sec/ { print $2 }')
    SECOND_TIME=$(env time --format="Sec %e" bash -c " $BASE --pass 2 --stats \"$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.log\" -o \"$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.h265\"" 2>&1 | awk ' /Sec/ { print $2 }')
else
    FIRST_TIME=$(env time --format="Sec %e" bash -c " $BASE -o \"$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.h265\" " 2>&1 | awk ' /Sec/ { print $2 }')
    SECOND_TIME=0
fi

ERROR=$(ffmpeg -y -hide_banner -loglevel error -i "${OUTPUT}/${FOLDER}_${TYPE}/${FOLDER}_${TYPE}.h265" -c copy "${OUTPUT}/${FOLDER}_${TYPE}/${FOLDER}_${TYPE}.mp4" 2>&1)
ERROR2=$(ffmpeg -y -hide_banner -loglevel error -i "${OUTPUT}/${FOLDER}_${TYPE}/${FOLDER}_${TYPE}.mp4" -c copy "${OUTPUT}/${FOLDER}_${TYPE}/${FOLDER}_${TYPE}.mkv" 2>&1)
if [ -n "$ERROR" ] || [ -n "$ERROR2" ]; then
    die "$FLAG failed ${ERROR} ${ERROR2}"
fi

if [ "$DECODE" -ne -1 ]; then
    DECODE_TIME=$(env time --format="Sec %e" bash -c " ffmpeg -hide_banner -loglevel error -i \"$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.mkv\" -f null -" 2>&1 | awk ' /Sec/ { print $2 }')
else
    DECODE_TIME=0
fi

rm -f "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.log" &&
rm -f "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.webm" &&
rm -f "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.h265" &&
rm -f "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.mp4" &&
rm -f "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.log.cutree" 

SIZE=$(du "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.mkv" | awk '{print $1}') &&
BITRATE=$(ffprobe -i "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.mkv" 2>&1 | awk ' /bitrate:/ { print $(NF-1) }')
echo -n "x265,${COMMIT},${PRESET},${INPUT_NAME},${SIZE},${TYPE},${BITRATE},${FIRST_TIME},${SECOND_TIME},${DECODE_TIME}," > "$OUTPUT/${FOLDER}_$TYPE/${FOLDER}_$TYPE.stats"
