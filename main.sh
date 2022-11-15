#!/usr/bin/env bash

set -e

CONTAINER_SYSTEM="podman"

# Run via CONTAINER_SYSTEM

$CONTAINER_SYSTEM image prune -a -f
$CONTAINER_SYSTEM build -t "bd-compare" .

SOURCE="${HOME}/Videos"
ENCODERS=("x265" "aomenc" "rav1e")
VIDEOS=("Big Buck Bunny.mkv")

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        $CONTAINER_SYSTEM run --rm -v "${SOURCE}:/videos:z" -v "$(pwd):/app:z" bd-compare scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality" --preset "steps/preset_${ENCODER}" -e 2 --threads 6 --decode --vbr --resume
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
