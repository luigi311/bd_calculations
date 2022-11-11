#!/usr/bin/env bash

# Source: http://mywiki.wooledge.org/BashFAQ/035
die() {
    printf '%s\n' "$1" >&2
    #exit 1
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

LOG=$(ffmpeg -hide_banner -loglevel error -i "$DISTORTED" -i "$REFERENCE" -filter_complex "libvmaf=log_path=${FILE}.json:log_fmt=json:n_threads=${N_THREADS}" -f null - 2>&1)

if [ -n "$LOG" ]; then
    die "$LOG"
fi

# vmaf 2.X
VMAF=$(jq '.["pooled_metrics"]["vmaf"]["mean"]' "${FILE}.json")
if [ "$VMAF" == "null" ]; then
    # vmaf 1.X
    VMAF=$(jq '.["VMAF score"]' "${FILE}.json")
fi

if [ -n "$VMAF" ]; then
    printf "%s" "$VMAF" >> "$FILE.stats"
    #rm "${FILE}.json"
else
    printf "%s" "$VMAF"
    die "Failed to generate VMAF info ${OUTPUT}"
fi


## SSIMULACRA2
#OUTPUT=$(ssimulacra2_rs video "$REFERENCE" "$DISTORTED")
#
#SSIM2=$(echo "$OUTPUT" | awk ' { print $7 } ')
#
#if [ -n "$SSIM2" ]; then
#    echo -n ",$SSIM2" >> "${FILE}.stats"
#else
#    die "Failed to generate SSIM2 info ${OUTPUT}"
#fi