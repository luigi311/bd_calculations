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
VMAF_OUT=""

LOG=$(ffmpeg -hide_banner -loglevel error -r 24 -i "$DISTORTED" -r 24 -i "$REFERENCE" -filter_complex "libvmaf=log_path=${FILE}.json:log_fmt=json:n_threads=${N_THREADS}" -f null - 2>&1)

if [ -n "$LOG" ]; then
    printf '%s\n' "$LOG"
fi

# vmaf 2.X
VMAF=$(jq '.["pooled_metrics"]["vmaf"]["mean"]' "${FILE}.json")
if [ "$VMAF" == "null" ]; then
    # vmaf 1.X
    VMAF=$(jq '.["VMAF score"]' "${FILE}.json")
fi

# Keep only the first 10 columns in $File.stats to remove any metrics if they exists
awk -F, 'NR==1{printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' "${FILE}.stats" > "${FILE}.tempstats"
mv "${FILE}.tempstats" "${FILE}.stats"

if [ -n "$VMAF" ]; then
    VMAF_OUT="$VMAF"
    rm "${FILE}.json"
else
    printf "%s" "$VMAF"
    die "Failed to generate VMAF info ${OUTPUT}"
fi


## SSIMULACRA2
#SSIM2_OUT=""
#OUTPUT=$(ssimulacra2_rs video -f "${N_THREADS}" "$REFERENCE" "$DISTORTED")
#
#SSIM2=$(echo "$OUTPUT" | awk 'NR==2{ print $2 } ')
#
#if [ -n "$SSIM2" ]; then
#    SSIM2_OUT="$SSIM2"
#else
#    die "Failed to generate SSIM2 info ${OUTPUT}"
#fi

#printf ",%s,%s" "$VMAF_OUT" "$SSIM2_OUT" >> "$FILE.stats"
printf ",%s" "$VMAF_OUT" >> "$FILE.stats"

# Delete video file to save space
rm "$DISTORTED"
