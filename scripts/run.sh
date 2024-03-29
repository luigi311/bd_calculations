#!/usr/bin/env bash

set -e

calculate_bd() {
    FOUND=0

    TEMP_CSV="${OUTPUTFINAL}/${1}/${CSV}"
    echo "Encoder, Commit, Preset, Video, Size, Quality, Bitrate, First Encode Time, Second Encode Time, Decode Time, VMAF Mean, SSIMULACRA2 Mean, VMAF 5th, SSIMULACRA2 5th" > "${TEMP_CSV}"

    if [ -n "$LASTHASH" ]; then
        find "${OUTPUT}/${ENCODER}/${LASTHASH}/${VIDEO}/${1}" -name '*.stats' -exec awk '{print $0}' {} + >> "${TEMP_CSV}" && FOUND=1
    fi

    find "${OUTPUTFINAL}/${1}" -name '*.stats' -exec awk '{print $0}' {} + >> "${TEMP_CSV}"

    if [ -n "$LASTHASH" ] && [ "$FOUND" -eq 1 ]; then
        echo "BD Features"
        scripts/bd_features.py --input "${TEMP_CSV}" --output "${TEMP_CSV%.csv}_bd_rates.csv" --encoder "${ENCODER}" --commit "${LASTHASH}" --preset "${1}"
        echo "Upload calculations"
        scripts/upload_metrics.py --input "${TEMP_CSV%.csv}_bd_rates.csv" --type "calculations"
    fi

}

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
    help="$(cat <<EOF
Test multiple encodes simultaneously, will gather stats such as file size, duration of first pass and second pass,
    visual metric scores and put them in a csv. Optionally can calulate bd_rate with that csv
Usage:
    ./run.sh [options]
Example:
    ./run.sh --encworkers 12
General Options:
    -h/--help                       Print this help screen
    -i/--input          [file]      Video source to use                                             (default video.mkv)
    -o/--output         [folder]    Output folder to place all encoded videos and stats files       (default output)
    --bd                [file]      File that contains different qualities to test for bd_rate
    -c/--csv            [file]      CSV file to output final stats for all encodes to               (default stats.csv)
    -e/--encworkers     [number]    Number of encodes to run simultaneously                         (defaults threads/encoding threads)
    -m/--metricworkers  [number]    Number of vmaf calculations to run simultaneously               (defaults 1)
    --resume                        Resume option for parallel, will use encoding.log and vmaf.log  (default false)
Encoding Settings:
    --enc               [string]    Encoder to test, supports aomenc and x265                       (default aomenc)
    -t/--threads        [number]    Amount of aomenc threads each encode should use                 (default 4)
    --preset            [number]    Set cpu-used/preset used by encoder                             (default 6)
    --pass              [number]    Set amount of passes for encoder
    --vbr                           Use vbr mode
    --crf                           Use crf mode                                                    (default)
    --decode                        Test decoding speed
EOF
)"
    echo "$help"
}

OUTPUT="output"
INPUT="video.mkv"
CSV="stats.csv"
ENC_WORKERS=-1
METRIC_WORKERS=-1
THREADS=-1
N_THREADS=-1
VBR=-1
CRF=-1
SAMPLES=-1
SAMPLETIME=60
ENCODER="aomenc"
SUPPORTED_ENCODERS="aomenc:svt-av1:x265:x264:rav1e:vvencapp"

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
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -o | --output)
            if [ "$2" ]; then
                OUTPUT="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --enc)
            if [ "$2" ]; then
                ENCODER="$2"
                # https://stackoverflow.com/questions/8063228/how-do-i-check-if-a-variable-exists-in-a-list-in-bash#comment91727359_46564084
                if [[ ":$SUPPORTED_ENCODERS:" != *:$ENCODER:* ]]; then
                    die "$2 not supported"
                fi
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -c | --csv)
            if [ "$2" ]; then
                CSV="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -e | --encworkers)
            if [ "$2" ]; then
                ENC_WORKERS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -m | --metricworkers)
            if [ "$2" ]; then
                METRIC_WORKERS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -n | --nthreads)
            if [ "$2" ]; then
                N_THREADS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --resume)
            RESUME="--resume --resume-failed"
            ;;
        -t | --threads)
            if [ "$2" ]; then
                THREADS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --vbr)
            if [ "$CRF" -ne -1 ]; then
                die "Can not set VBR and CRF at the same time"
            fi
            VBR=1
            ;;
        --crf)
            if [ "$VBR" -ne -1 ]; then
                die "Can not set VBR and CRF at the same time"
            fi
            CRF=1
            ;;
        --bd)
            if [ "$2" ]; then
                BD_FILE="$2"
                if [ ! -f "$BD_FILE" ]; then
                    die "$BD_FILE file does not exist"
                fi
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --preset)
            if [ "$2" ]; then
                PRESET_FILE="$2"
                if [ ! -f "$PRESET_FILE" ]; then
                    die "$PRESET_FILE file does not exist"
                fi
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --pass)
            if [ "$2" ]; then
                PASS="--pass $2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --decode)
            DECODE="--decode"
            ;;
        --samples)
            if [ "$2" ]; then
                SAMPLES="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --sampletime)
            if [ "$2" ]; then
                SAMPLETIME="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty argument."
            fi
            ;;
        --distribute)
            DISTRIBUTE="--sshloginfile .. --workdir . --sshdelay 0.2"
            ;;
        --) # End of all options.
            shift
            break
            ;;
        -?*)
            die "Error: Unknown option : $1"
            ;;
        *) # Default case: No more options, so break out of the loop.
            break ;;
    esac
    shift
done

if [ "${THREADS}" -eq -1 ]; then
    if [ "${ENCODER}" == "svt-av1" ]; then
        THREADS=18
    else
        THREADS=8
    fi

    # Cap threads to nproc
    if [ "${THREADS}" -gt "$(nproc)" ]; then
        THREADS="$(nproc)"
    fi
fi

if [ "${N_THREADS}" -eq -1 ]; then
    # Set to 8 or nproc
    N_THREADS=$(( 8 < $(nproc) ? 8 : $(nproc) ))
fi

# Set job amounts for encoding
if [ "${ENC_WORKERS}" -eq -1 ]; then
    ENC_WORKERS=$(( (100 / "$THREADS") + 20 ))
    ENC_WORKERS="${ENC_WORKERS}%"
fi

if [ "${METRIC_WORKERS}" -eq -1 ]; then
    METRIC_WORKERS=$(( (100 / "$N_THREADS") + 20 ))
    METRIC_WORKERS="${METRIC_WORKERS}%"
fi

# Set encoding settings
if [ "${VBR}" -ne -1 ]; then
    ENCODING="--vbr"
elif [ "${CRF}" -ne -1 ]; then
    ENCODING="--crf"
else
    ENCODING="--crf"
fi

# Check if files exist
if [ ! -f "${INPUT}" ]; then
    die "${INPUT} file does not exist"
fi

if [ ! -f "${PRESET_FILE}" ]; then
    die "${PRESET_FILE} file does not exist"
fi

if [ ! -f "${BD_FILE}" ]; then
    die "${BD_FILE} file does not exist"
fi

if [ "$SAMPLES" -ne -1 ]; then
    echo "Creating Sample"
    mkdir -p split
    ffmpeg -y -hide_banner -loglevel error -i "$INPUT" -c copy -map 0:v -segment_time "$SAMPLETIME" -f segment split/%05d.mkv
    COUNT=$(( $(find split | wc -l ) - 2 ))
    if [ $COUNT -eq 0 ]; then COUNT=1; fi
    INCR=$((COUNT / SAMPLES))
    if [ $INCR -eq 0 ]; then INCR=1; fi
    for ((COUNTER=0; COUNTER<COUNT; COUNTER++))
    do
        if [ "$COUNTER" -eq 0 ]; then
          GLOBIGNORE=$(printf "%0*d.mkv" 5 "$COUNTER")
        elif (( COUNTER % INCR == 0 )); then
          GLOBIGNORE+=$(printf ":%0*d.mkv" 5 "$COUNTER")
        fi
    done
    (
      cd split || exit
      rm ./*
      find ./*.mkv | sed 's:\ :\\\ :g' | sed 's/.\///' |sed 's/^/file /' | sed 's/mkv/mkv\nduration '$SAMPLETIME'/' > concat.txt; ffmpeg -y -hide_banner -loglevel error -f concat -i concat.txt -c copy output.mkv; rm concat.txt
      mv output.mkv ../
    )
    rm -rf split
    INPUT="output.mkv"
fi


mkdir -p "${OUTPUT}/${ENCODER}"

# Get hash
HASH=$(cat "/${ENCODER}")
LASTHASH=$(find "${OUTPUT}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==1{ print $2 }')

if [ "${LASTHASH}" == "${HASH}" ]; then
    echo "Hashes match, going back further"
    LASTHASH=$(find "${OUTPUT}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==2{ print $2 }')
fi

echo "Last hash: ${LASTHASH}"
echo "Current hash: ${HASH}"

VIDEO=$(basename "${INPUT}" | sed 's/\(.*\)\..*/\1/')

OUTPUTFINAL="${OUTPUT}/${ENCODER}/${HASH}/${VIDEO}"
mkdir -p "${OUTPUTFINAL}"

echo "Encoding"
parallel -j "${ENC_WORKERS}" $DISTRIBUTE --joblog "${OUTPUTFINAL}/encoding.log" $RESUME --bar -a "${PRESET_FILE}" -a "${BD_FILE}" "scripts/${ENCODER}.sh" --input \""${INPUT}"\" --output \""${OUTPUTFINAL}/{1}"\" --threads "${THREADS}" "${ENCODING}" --quality "{2}" --preset "{1}" --commit "${HASH}" $PASS $DECODE


echo "Calculating Metrics"
if [ "${ENCODER}" == "vvencapp" ]; then
    METRIC_EXTENSION="y4m"
else
    METRIC_EXTENSION="mkv"
fi
find "${OUTPUTFINAL}" -name "*.${METRIC_EXTENSION}" | parallel -j "${METRIC_WORKERS}" $DISTRIBUTE --joblog "${OUTPUTFINAL}/metrics.log" $RESUME --bar scripts/calculate_metrics.sh --distorted {} --reference \""${INPUT}"\" --nthreads "${N_THREADS}"

echo "Calculating BD Rates"
find "${OUTPUTFINAL}" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' FOLDER
do
    PRESET=$(basename "${FOLDER}")
    calculate_bd "${PRESET}"
done
