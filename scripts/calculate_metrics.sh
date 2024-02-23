#!/usr/bin/env bash

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

N_THREADS=-1


# Source: http://mywiki.wooledge.org/BashFAQ/035
while :; do
    case "$1" in
        -h | -\? | --help)
            help
            exit 0
            ;;
        -r | --reference)
            if [ "$2" ]; then
                REFERENCE="$2"
                shift
            else
                die "ERROR: $1 requires a non-empty option argument."
            fi
            ;;
        -d | --distorted)
            if [ "$2" ]; then
                DISTORTED="$2"
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

FILE=${DISTORTED%.mkv}
FILE=${FILE%.y4m}

# Keep only the first 10 columns in $File.stats to remove any metrics if they exists
awk -F, 'NR==1{printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' "${FILE}.stats" > "${FILE}.tempstats"
mv "${FILE}.tempstats" "${FILE}.stats"

VMAF_OUT_MEAN=""
VMAF_OUT_5_PERCENTILE=""

LOG=$(ffmpeg -hide_banner -loglevel error -r 24 -i "$DISTORTED" -r 24 -i "$REFERENCE" -filter_complex "libvmaf=log_path=${FILE}.json:log_fmt=json:n_threads=${N_THREADS}" -f null - 2>&1)

if [ -n "$LOG" ]; then
    printf '%s\n' "$LOG"
fi

# Parse VMAF from the json file
python scripts/parse_vmaf.py --input "${FILE}.json" --output "${FILE}.vmaf"

# Split the output into mean and 5th percentile by comma
IFS=',' read -r VMAF_MEAN VMAF_5_PERCENTILE < "${FILE}.vmaf"

if [ -n "$VMAF_MEAN" ]; then
    VMAF_OUT_MEAN="$VMAF_MEAN"
    VMAF_OUT_5_PERCENTILE="$VMAF_5_PERCENTILE"
    rm "${FILE}.json" "${FILE}.vmaf"
else
    printf "%s" "$VMAF_MEAN"
    printf "%s" "$VMAF_5_PERCENTILE"
    die "Failed to generate VMAF info ${OUTPUT}"
fi


# SSIMULACRA2
SSIM2_OUT_MEAN=""
SSIM2_OUT_5_PERCENTILE=""

OUTPUT=$(ssimulacra2_rs video -f "${N_THREADS}" "$REFERENCE" "$DISTORTED" 2>&1)

SSIM2_MEAN=$(echo "$OUTPUT" | awk '/Mean: /{print $2}')
SSIM2_5_PERCENTILE=$(echo "$OUTPUT" | awk '/^5th Percentile: /{print $3}')

if [ -n "$SSIM2_MEAN" ]; then
    SSIM2_OUT_MEAN="$SSIM2_MEAN"
    SSIM2_OUT_5_PERCENTILE="$SSIM2_5_PERCENTILE"
else
    printf "%s" "$SSIM2_MEAN"
    printf "%s" "$SSIM2_5_PERCENTILE"
    die "Failed to generate SSIM2 info ${OUTPUT}"
fi

printf ",%s,%s,%s,%s" "$VMAF_OUT_MEAN" "$SSIM2_OUT_MEAN" "$VMAF_OUT_5_PERCENTILE" "$SSIM2_OUT_5_PERCENTILE" >> "$FILE.stats"

# Remove lwi file that ssimulacra2 creates
rm -f "${DISTORTED}.lwi"
rm -f "${REFERENCE}.lwi"

# Delete video file to save space
#rm "$DISTORTED"
