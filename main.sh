#!/usr/bin/env bash

set -e

# Source: https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

CONTAINER_SYSTEM="podman"
SOURCE="${HOME}/Videos"

get_remote_commit() {
    local COMMIT
    
    COMMIT=$(git ls-remote "$1" HEAD | cut -f1)
    echo "$COMMIT"
}

get_docker_commit() {
    local COMMIT
    
    COMMIT=$(${CONTAINER_SYSTEM} run --rm bd_calculations /bin/bash -c "cd /${1}; git log --pretty=tformat:'%H' -n1 .")
    echo "$COMMIT"
}

update_container_image() {

    # Check latest commit for encoders
    COMMIT_X265=$(get_remote_commit "https://github.com/videolan/x265.git")
    COMMIT_AOMENC=$(get_remote_commit "https://aomedia.googlesource.com/aom")
    COMMIT_RAV1E=$(get_remote_commit "https://github.com/xiph/rav1e.git")
    COMMIT_SVT_AV1=$(get_remote_commit "https://gitlab.com/AOMediaCodec/SVT-AV1.git")

    DOCKER_X265=$(get_docker_commit "x265")
    DOCKER_AOMENC=$(get_docker_commit "aomenc")
    DOCKER_RAV1E=$(get_docker_commit "rav1e")
    DOCKER_SVT_AV1=$(get_docker_commit "svt-av1")

    # Check if any of the commits are different
    if [ "$COMMIT_X265" != "$DOCKER_X265" ] || [ "$COMMIT_AOMENC" != "$DOCKER_AOMENC" ] || [ "$COMMIT_RAV1E" != "$DOCKER_RAV1E" ] || [ "$COMMIT_SVT_AV1" != "$DOCKER_SVT_AV1" ]; then
        echo "Updating container image..."

        if [ -n "$(${CONTAINER_SYSTEM} images -q bd_calculations:latest 2> /dev/null)" ]; then
            echo "x265: $DOCKER_X265 -> $COMMIT_X265"
            echo "aomenc: $DOCKER_AOMENC -> $COMMIT_AOMENC"
            echo "rav1e: $DOCKER_RAV1E -> $COMMIT_RAV1E"
            echo "svt-av1: $DOCKER_SVT_AV1 -> $COMMIT_SVT_AV1"
        fi

        ${CONTAINER_SYSTEM} image prune -a -f
        ${CONTAINER_SYSTEM} build -t "bd_calculations" "${SCRIPT_DIR}"
    fi
}


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
        -s | --source)
            if [ "$2" ]; then
                SOURCE="$2"
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


# Update container image
update_container_image

ENCODERS=("x265" "aomenc" "rav1e" "svt-av1")
VIDEOS=("Big Buck Bunny.mkv")
THREADS=$(nproc --all)
ENC_WORKERS=1

for ENCODER in "${ENCODERS[@]}"; do
    printf "Running %s\n" "$ENCODER"
    for VIDEO in "${VIDEOS[@]}"; do
        printf "%s\n" "$VIDEO"
        ${CONTAINER_SYSTEM} run --rm -v "${SOURCE}:/videos:z" -v "${SCRIPT_DIR}:/app:z" bd_calculations scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality" --preset "steps/preset_${ENCODER}" -e "${ENC_WORKERS}" --threads "${THREADS}" --decode --vbr --resume
    done
done


mkdir -p "${SOURCE}/bd_calculations"
RESULT_CSV="${SOURCE}/bd_calculations/results.csv"

echo "Encoder, Commit, Preset, Video, Size, Quality, Bitrate, First Encode Time, Second Encode Time, Decode Time, VMAF" > "${RESULT_CSV}"

for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(find "${SOURCE}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==1{ print $2 }')
    find "${SOURCE}/${ENCODER}/${LASTHASH}/" -name '*.stats' -exec awk '{print $0}' {} + >> "${RESULT_CSV}"
done


echo "Generating All BD Features"
OUTDIR=$(dirname "${RESULT_CSV}")
for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(find "${SOURCE}/${ENCODER}" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %f\n" | sort -nr | awk 'NR==1{ print $2 }')
    PRESETS=$(find "${SOURCE}/${ENCODER}/${LASTHASH}/" -mindepth 2 -maxdepth 2 -type d -printf "%f\n" | sort -n)
    for PRESET in ${PRESETS}; do
        scripts/bd_features.py --input "${RESULT_CSV}" --output "${OUTDIR}/${ENCODER}_${PRESET}_bd_rates.csv" --encoder "${ENCODER}" --commit "${LASTHASH}" --preset "${PRESET}"
    done
done


echo "Uploading all BD Features"
for FILE in "${OUTDIR}"/*_bd_rates.csv; do
    scripts/upload_metrics.py --input "${FILE}"
done
