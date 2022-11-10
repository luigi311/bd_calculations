#!/usr/bin/env bash

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
    help="$(cat <<EOF
Test multiple encoding flags simultaneously, will gather stats such as file size, duration of first pass and second pass,
    visual metric scores and put them in a csv. Optionally can calulate bd_rate with that csv for all flags
Usage:
    ./run.sh [options]
Example:
    ./run.sh --flags arguments.aomenc --encworkers 12
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
    --q                             Use q mode   (applies to aomenc only)                           (default for aomenc)
    --cq                            Use cq mode  (applies to aomenc only)
    --vbr                           Use vbr mode (applies to aomenc/x265 only)
    --crf                           Use crf mode (applies to x265 only)                             (default for x265)
    --decode                        Test decoding speed
EOF
)"
    echo "$help"
}

OUTPUT="output"
INPUT="video.mkv"
CSV="stats.csv"
METRIC_WORKERS=1
THREADS=-1
N_THREADS=-1
Q=-1
CQ=-1
VBR=-1
CRF=-1
CBR=-1
MANUAL=0
BD=-1
SAMPLES=-1
SAMPLETIME=60
ENCODER="aomenc"
SUPPORTED_ENCODERS="aomenc:svt-av1:x265:rav1e"

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
                MANUAL=1
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
        --resume)
            RESUME="--resume"
            ;;
        -f | --flags)
            if [ "$2" ]; then
                FLAGS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -t | --threads)
            if [ "$2" ]; then
                THREADS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --q)
            if [ "$VBR" -ne -1 ] || [ "$CQ" -ne -1 ] || [ "$CRF" -ne -1 ] || [ "$CBR" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            Q=1
            ;;
        --cq)
            if [ "$VBR" -ne -1 ] || [ "$Q" -ne -1 ] || [ "$CRF" -ne -1 ] || [ "$CBR" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            CQ=1
            ;;
        --vbr)
            if [ "$Q" -ne -1 ] || [ "$CQ" -ne -1 ] || [ "$CRF" -ne -1 ] || [ "$CBR" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            VBR=1
            ;;
        --crf)
            if [ "$VBR" -ne -1 ] || [ "$Q" -ne -1 ] || [ "$CQ" -ne -1 ] || [ "$CBR" -ne -1 ]; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            CRF=1
            ;;
        --cbr)
            if [ "$VBR" -ne -1 ] || [ "$Q" -ne -1 ] || [ "$CQ" -ne -1 ] || [ "$CRF" -ne -1 ] ; then
                die "Can not set VBR, CQ, q and CRF at the same time"
            fi
            CBR=1
            ;;
        --bd)
            if [ "$2" ]; then
                BD=1
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
                PRESET="--preset $2"
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

if [ "$THREADS" -eq -1 ]; then
    if [ "$ENCODER" == "aomenc" ]; then
        THREADS=4
    elif [ "$ENCODER" == "svt-av1" ]; then
        THREADS=18
    elif [ "$ENCODER" == "x265" ]; then
        THREADS=4
    elif [ "$ENCODER" == "rav1e" ]; then
        THREADS=4
    else
        die "Threads not set"
    fi
fi

if [ "$N_THREADS" -eq -1 ]; then
    N_THREADS=8
fi

# Set job amounts for encoding
if [ "$MANUAL" -ne 1 ]; then
    ENC_WORKERS=$(( (100 / "$THREADS") ))
    METRIC_WORKERS=$(( (100 / "$N_THREADS") ))
    ENC_WORKERS="${ENC_WORKERS}%"
    METRIC_WORKERS="${METRIC_WORKERS}%"
fi

# Set encoding settings
if [ "$Q" -ne -1 ]; then
    if [ "$ENCODER" == "aomenc" ]; then
        ENCODING="--q"
    else
        die "q is not supported by $ENCODER"
    fi
elif [ "$CQ" -ne -1 ]; then
    if [ "$ENCODER" == "aomenc" ] || [ "$ENCODER" == "svt-av1" ]; then
        ENCODING="--cq"
    else
        die "cq is not supported by $ENCODER"
    fi
elif [ "$VBR" -ne -1 ]; then
    if [ "$ENCODER" == "aomenc" ] || [ "$ENCODER" == "svt-av1" ] || [ "$ENCODER" == "x265" ] || [ "$ENCODER" == "x264" ]; then
        ENCODING="--vbr"
    else
        die "vbr is not supported by $ENCODER"
    fi
elif [ "$CRF" -ne -1 ]; then
    if [ "$ENCODER" == "x265" ] || [ "$ENCODER" == "x264" ]; then
        ENCODING="--crf"
    else
        die "crf is not supported by $ENCODER"
    fi
elif [ "$CBR" -ne -1 ]; then
    # TODO: Implement CBR on all encoders
    if [ "$ENCODER" == "x264" ]; then
        ENCODING="--cbr"
    else
        die "cbr is not supported by $ENCODER"
    fi
else
    if [ "$ENCODER" == "aomenc" ]; then
        ENCODING="--q"
    elif [ "$ENCODER" == "x265" ] || [ "$ENCODER" == "x264" ]; then
        ENCODING="--crf"
    elif [ "$ENCODER" == "svt-av1" ]; then
        ENCODING="--cq"
    fi
fi

# Check if files exist
if [ ! -f "$INPUT" ]; then
    die "$INPUT file does not exist"
fi

if [ "$SAMPLES" -ne -1 ]; then
    echo "Creating Sample"
    mkdir -p split
    ffmpeg -y -hide_banner -loglevel error -i "$INPUT" -c copy -map 0:v -segment_time $SAMPLETIME -f segment split/%05d.mkv
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
      rm *
      find ./*.mkv | sed 's:\ :\\\ :g' | sed 's/.\///' |sed 's/^/file /' | sed 's/mkv/mkv\nduration '$SAMPLETIME'/' > concat.txt; ffmpeg -y -hide_banner -loglevel error -f concat -i concat.txt -c copy output.mkv; rm concat.txt
      mv output.mkv ../
    )
    rm -rf split
    INPUT="output.mkv"
fi


mkdir -p "${OUTPUT}"

# Get hash
HASH=$(cd "/${ENCODER}" && git rev-parse HEAD)
LASTHASH=$(ls -lt ${OUTPUT} | awk 'NR==2{ print $9 }')
VIDEO=$(basename "$INPUT" | sed 's/\(.*\)\..*/\1/')

OUTPUTFINAL="${OUTPUT}/${ENCODER}/${HASH}/${VIDEO}/${PRESET}"
mkdir -p "${OUTPUTFINAL}"
CSV="${OUTPUTFINAL}/${CSV}"


echo "Encoding"
parallel -j "$ENC_WORKERS" $DISTRIBUTE --joblog "${OUTPUTFINAL}/encoding.log" $RESUME --bar -a "$BD_FILE" "scripts/${ENCODER}.sh" --input "$INPUT" --output "${OUTPUTFINAL}" --threads "$THREADS" "$ENCODING" --quality "{1}" --flag "baseline" $PRESET $PASS $DECODE


echo "Calculating Metrics"
find "$OUTPUTFINAL" -name "*.mkv" | parallel -j "$METRIC_WORKERS" $DISTRIBUTE --joblog "${OUTPUTFINAL}/metrics.log" $RESUME --bar scripts/calculate_metrics.sh --distorted {} --reference "$INPUT" --nthreads "$N_THREADS"

echo "Creating CSV"
echo "Commit, Size, Quality, Preset, Bitrate, First Encode Time, Second Encode Time, Decode Time, VMAF" > "$CSV"

if [ ! -z "$LASTHASH" ]; then
    find "${OUTPUT}/${ENCODER}/${LASTHASH}/${VIDEO}/${PRESET}" -name '*.stats' -exec awk '{print $0}' {} + >> "$CSV"
fi

find "${OUTPUTFINAL}" -name '*.stats' -exec awk '{print $0}' {} + >> "$CSV"

if [ ! -z "$LASTHASH" ]; then
    echo "Calculating bd_rates"
    scripts/bd_features.py --input "$CSV" --output "${CSV%.csv}_bd_rates.csv" --baseline "${LASTHASH}"
fi
