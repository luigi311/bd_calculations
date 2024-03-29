#!/usr/bin/env bash

set -e

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

# Source: https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

CONTAINER_SYSTEM="podman"
OUTPUT="${HOME}/Videos"

get_remote_commit() {
    local COMMIT

    COMMIT=$(git ls-remote "$1" HEAD | cut -f1)
    echo "$COMMIT"
}

get_docker_commit() {
    local COMMIT

    COMMIT=$(${CONTAINER_SYSTEM} run --rm bd_calculations cat "/${1}")
    echo "$COMMIT"
}

update_container_image() {

    # Check latest commit for encoders
    COMMIT_X264=$(get_remote_commit "https://code.videolan.org/videolan/x264.git")
    COMMIT_X265=$(get_remote_commit "https://bitbucket.org/multicoreware/x265_git")
    COMMIT_AOMENC=$(get_remote_commit "https://aomedia.googlesource.com/aom")
    COMMIT_RAV1E=$(get_remote_commit "https://github.com/xiph/rav1e.git")
    COMMIT_SVT_AV1=$(get_remote_commit "https://gitlab.com/AOMediaCodec/SVT-AV1.git")
    COMMIT_VVENCAP=$(get_remote_commit "https://github.com/fraunhoferhhi/vvenc")

    # Check latest commit for encoders in container
    DOCKER_X264=$(get_docker_commit "x264")
    DOCKER_X265=$(get_docker_commit "x265")
    DOCKER_AOMENC=$(get_docker_commit "aomenc")
    DOCKER_RAV1E=$(get_docker_commit "rav1e")
    DOCKER_SVT_AV1=$(get_docker_commit "svt-av1")
    DOCKER_VVENCAP=$(get_docker_commit "vvencapp")

    # Check if any of the commits are different
    if [ "$COMMIT_X264" != "$DOCKER_X264" ] || \
        [ "$COMMIT_X265" != "$DOCKER_X265" ] || \
        [ "$COMMIT_AOMENC" != "$DOCKER_AOMENC" ] || \
        [ "$COMMIT_RAV1E" != "$DOCKER_RAV1E" ] || \
        [ "$COMMIT_SVT_AV1" != "$DOCKER_SVT_AV1" ] || \
        [ "$COMMIT_VVENCAP" != "$DOCKER_VVENCAP" ]
    then
        echo "Updating container image..."

        echo "x264:     $DOCKER_X264 -> $COMMIT_X264"
        echo "x265:     $DOCKER_X265 -> $COMMIT_X265"
        echo "aomenc:   $DOCKER_AOMENC -> $COMMIT_AOMENC"
        echo "rav1e:    $DOCKER_RAV1E -> $COMMIT_RAV1E"
        echo "svt-av1:  $DOCKER_SVT_AV1 -> $COMMIT_SVT_AV1"
        echo "vvencapp: $DOCKER_VVENCAP -> $COMMIT_VVENCAP"

        ${CONTAINER_SYSTEM} image prune -a -f
        ${CONTAINER_SYSTEM} build -t "bd_calculations" "${SCRIPT_DIR}" --no-cache
    fi
}

N_THREADS=-1
METRIC_WORKERS=1

# Source: http://mywiki.wooledge.org/BashFAQ/035
while :; do
    case "$1" in
        -h | -\? | --help)
            help
            exit 0
            ;;
        -c | --container)
            if [ "$2" ]; then
                CONTAINER_SYSTEM="$2"
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
        --nthreads)
            if [ "$2" ]; then
                N_THREADS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        --metricworkers)
            if [ "$2" ]; then
                METRIC_WORKERS="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
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

if [ "$N_THREADS" -eq -1 ]; then
    N_THREADS=$(( 8 < $(nproc) ? 8 : $(nproc) ))
fi

# Check for new encoder commits and update container image if necessary
update_container_image

ENCODERS=("x264" "aomenc" "rav1e" "svt-av1" "x265" "vvencapp")
VIDEOS=("Big Buck Bunny 1080p.mkv" "Tears of Steel 1080p.mkv" "Fallout 1080p.mkv")
THREADS=$(nproc)
ENC_WORKERS=1

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        printf "Running %s\n" "$ENCODER"
        printf "%s\n" "$VIDEO"
        ${CONTAINER_SYSTEM} run --rm -it -v "${OUTPUT}:/videos:z" -v "${SCRIPT_DIR}:/app:z" bd_calculations scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality_${ENCODER}" --preset "steps/preset_${ENCODER}" -e "${ENC_WORKERS}" --threads "${THREADS}" --metricworkers "$METRIC_WORKERS" --nthreads "$N_THREADS" --decode --crf --pass 1 --resume
    done
done


mkdir -p "${OUTPUT}/bd_calculations"
RESULT_CSV="${OUTPUT}/bd_calculations/results.csv"

echo "Encoder, Commit, Preset, Video, Size, Quality, Bitrate, First Encode Time, Second Encode Time, Decode Time, VMAF, SSIMULACRA2" > "${RESULT_CSV}"

for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(find "${OUTPUT}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==1{ print $2 }')
    find "${OUTPUT}/${ENCODER}/${LASTHASH}/" -name '*.stats' -exec awk '{print $0}' {} + >> "${RESULT_CSV}"
done

echo "Uploading results"
${CONTAINER_SYSTEM} run --rm -it -v "${OUTPUT}:/${OUTPUT}:z" -v "${SCRIPT_DIR}:/app:z" bd_calculations scripts/upload_metrics.py --input "${RESULT_CSV}" --type "results"

echo "Generating All BD Features"
OUTDIR=$(dirname "${RESULT_CSV}")
for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(find "${OUTPUT}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==1{ print $2 }')
    PRESETS=$(find "${OUTPUT}/${ENCODER}/${LASTHASH}/" -mindepth 2 -maxdepth 2 -type d -printf "%f\n" | sort -n)
    for PRESET in ${PRESETS}; do
        ${CONTAINER_SYSTEM} run --rm -it -v "${OUTPUT}:/${OUTPUT}:z" -v "${SCRIPT_DIR}:/app:z" bd_calculations scripts/bd_features.py --input "${RESULT_CSV}" --output "${OUTDIR}/${ENCODER}_${PRESET}_bd_rates.csv" --encoder "${ENCODER}" --commit "${LASTHASH}" --preset "${PRESET}"
    done
done

echo "Combining all BD Features"
# Combine all BD features into one file
# Get header from first file
FIRST=$(find "${OUTDIR}" -name "*_bd_rates.csv" -print -quit)
head -n1 "${FIRST}" > "${OUTDIR}/all_bd_rates.csv"
for FILE in "${OUTDIR}"/*_bd_rates.csv; do
    tail -n+2 "${FILE}" >> "${OUTDIR}/all_bd_rates.csv"
done

echo "Uploading BD Features"
${CONTAINER_SYSTEM} run --rm -it -v "${OUTPUT}:/${OUTPUT}:z" -v "${SCRIPT_DIR}:/app:z" bd_calculations scripts/upload_metrics.py --input "${OUTDIR}/all_bd_rates.csv" --type "calculations"
