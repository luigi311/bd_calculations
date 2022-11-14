#!/usr/bin/env bash

podman image prune -a -f
podman build -t "bd-compare" .

SOURCE="${HOME}/Videos"
ENCODERS=("x265" "aomenc")
VIDEOS=("bbb_shorter.mkv")

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        podman run --rm -v "${SOURCE}:/videos:z" -v "$(pwd):/app:z" bd-compare scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality_${ENCODER}" --preset "steps/preset_${ENCODER}" --resume -e 2 --decode
    done
done


mkdir -p "${SOURCE}/bd_calculations"
RESULT_CSV="${SOURCE}/bd_calculations/results.csv"

echo "Encoder, Commit, Preset, Video, Size, Quality, Bitrate, First Encode Time, Second Encode Time, Decode Time, VMAF" > "${RESULT_CSV}"

for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(ls -lt "${SOURCE}/${ENCODER}" | awk 'NR==2{ print $9 }')
    find "${SOURCE}/${ENCODER}/${LASTHASH}/" -name '*.stats' -exec awk '{print $0}' {} + >> "${RESULT_CSV}"
done


echo "Generating All BD Features"
OUTDIR=$(dirname "${RESULT_CSV}")
for ENCODER in "${ENCODERS[@]}"; do
    LASTHASH=$(ls -lt "${SOURCE}/${ENCODER}" | awk 'NR==2{ print $9 }')
    PRESETS=$(find "${SOURCE}/${ENCODER}/${LASTHASH}/" -mindepth 2 -maxdepth 2 -type d | awk -F'/' '{print $NF}')
    for PRESET in ${PRESETS}; do
        scripts/bd_features.py --input "${RESULT_CSV}" --output "${OUTDIR}/${ENCODER}_${PRESET}_bd_rates.csv" --encoder "${ENCODER}" --commit "${LASTHASH}" --preset "${PRESET}"
    done
done


echo "Uploading all BD Features"
for FILE in "${OUTDIR}"/*_bd_rates.csv; do
    scripts/upload_metrics.py --input "${FILE}"
done
