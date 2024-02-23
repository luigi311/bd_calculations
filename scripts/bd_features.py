#!/usr/bin/env python3
# Copyright 2014 Google.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Converts video encoding result data from text files to visualization
data source."""

# __author__ = "jzern@google.com (James Zern),"
# __author__ += "jimbankoski@google.com (Jim Bankoski)"
# __author__ += "hta@gogle.com (Harald Alvestrand)"


import math
import numpy
import csv
import argparse
from pathlib import Path


def bdsnr(metric_set1, metric_set2):
    """
    BJONTEGAARD    Bjontegaard metric calculation
    Bjontegaard's metric allows to compute the average gain in psnr between two
    rate-distortion curves [1].
    rate1,psnr1 - RD points for curve 1
    rate2,psnr2 - RD points for curve 2

    returns the calculated Bjontegaard metric 'dsnr'

    code adapted from code written by : (c) 2010 Giuseppe Valenzise
    http://www.mathworks.com/matlabcentral/fileexchange/27798-bjontegaard-metric/content/bjontegaard.m
    """
    # pylint: disable=too-many-locals
    # numpy seems to do tricks with its exports.
    # pylint: disable=no-member
    # map() is recommended against.
    # pylint: disable=bad-builtin
    rate1 = [x[0] for x in metric_set1]
    psnr1 = [x[1] for x in metric_set1]
    rate2 = [x[0] for x in metric_set2]
    psnr2 = [x[1] for x in metric_set2]

    log_rate1 = list(map(math.log, rate1))
    log_rate2 = list(map(math.log, rate2))

    # Best cubic poly fit for graph represented by log_ratex, psrn_x.
    poly1 = numpy.polyfit(log_rate1, psnr1, 3)
    poly2 = numpy.polyfit(log_rate2, psnr2, 3)

    # Integration interval.
    min_int = max([min(log_rate1), min(log_rate2)])
    max_int = min([max(log_rate1), max(log_rate2)])

    # Integrate poly1, and poly2.
    p_int1 = numpy.polyint(poly1)
    p_int2 = numpy.polyint(poly2)

    # Calculate the integrated value over the interval we care about.
    int1 = numpy.polyval(p_int1, max_int) - numpy.polyval(p_int1, min_int)
    int2 = numpy.polyval(p_int2, max_int) - numpy.polyval(p_int2, min_int)

    # Calculate the average improvement.
    if max_int != min_int:
        avg_diff = (int2 - int1) / (max_int - min_int)
    else:
        avg_diff = 0.0
    return avg_diff


def bdrate(metric_set1, metric_set2):
    """
    BJONTEGAARD    Bjontegaard metric calculation
    Bjontegaard's metric allows to compute the average % saving in bitrate
    between two rate-distortion curves [1].

    rate1,psnr1 - RD points for curve 1
    rate2,psnr2 - RD points for curve 2

    adapted from code from: (c) 2010 Giuseppe Valenzise

    """
    # numpy plays games with its exported functions.
    # pylint: disable=no-member
    # pylint: disable=too-many-locals
    # pylint: disable=bad-builtin
    rate1 = [x[0] for x in metric_set1]
    psnr1 = [x[1] for x in metric_set1]
    rate2 = [x[0] for x in metric_set2]
    psnr2 = [x[1] for x in metric_set2]

    log_rate1 = list(map(math.log, rate1))
    log_rate2 = list(map(math.log, rate2))

    # Best cubic poly fit for graph represented by log_ratex, psrn_x.
    poly1 = numpy.polyfit(psnr1, log_rate1, 3)
    poly2 = numpy.polyfit(psnr2, log_rate2, 3)

    # Integration interval.
    min_int = max([min(psnr1), min(psnr2)])
    max_int = min([max(psnr1), max(psnr2)])

    # find integral
    p_int1 = numpy.polyint(poly1)
    p_int2 = numpy.polyint(poly2)

    # Calculate the integrated value over the interval we care about.
    int1 = numpy.polyval(p_int1, max_int) - numpy.polyval(p_int1, min_int)
    int2 = numpy.polyval(p_int2, max_int) - numpy.polyval(p_int2, min_int)

    # Calculate the average improvement.
    avg_exp_diff = (int2 - int1) / (max_int - min_int)

    # In really bad formed data the exponent can grow too large.
    # clamp it.
    if avg_exp_diff > 200:
        avg_exp_diff = 200

    # Convert to a percentage.
    avg_diff = (math.exp(avg_exp_diff) - 1) * 100

    return avg_diff


def avg(lst):
    return sum(lst) / len(lst)


numbers = {
    "encoder": 0,
    "commit": 1,
    "preset": 2,
    "video": 3,
    "size": 4,
    "type": 5,
    "bitrate": 6,
    "first_time": 7,
    "second_time": 8,
    "decode_time": 9,
    "vmaf": 10,
    "ssimcra2": 11,
    "vmaf_5th": 12,
    "ssimcra2_5th": 13,
}


def calculate_metrics(baseline_dataset, dataset, metric_column):
    baseline = [
        (float(x[numbers["bitrate"]]), float(x[metric_column]))
        for x in baseline_dataset
    ]
    target = [(float(x[numbers["bitrate"]]), float(x[metric_column])) for x in dataset]
    return round(bdrate(baseline, target), 3)


def baseline_check(row, args):
    return (row[numbers["encoder"]] == args.encoder) and (
        row[numbers["commit"]] == args.commit
        and (row[numbers["preset"]] == args.preset)
    )


def main():
    parser = argparse.ArgumentParser(description="Process some integers.")
    parser.add_argument("--input", "-i", type=Path, help="Input File")
    parser.add_argument(
        "--output", "-o", type=Path, default=Path("bd_rates.csv"), help="Output File"
    )
    parser.add_argument(
        "--encoder", "-e", type=str, help="Baseline Encoder", required=True
    )
    parser.add_argument(
        "--commit", "-c", type=str, help="Baseline Commit", required=True
    )
    parser.add_argument(
        "--preset", "-p", type=str, help="Baseline Preset", required=True
    )

    args = parser.parse_args()

    with open(args.input) as csvfile:
        reader = csv.reader(csvfile, delimiter=",")
        next(reader)  # Skip headers
        data = list(reader)

    commits = list(set([x[numbers["commit"]] for x in data]))

    ls = []

    videos = list(set([x[numbers["video"]] for x in data]))

    for video in videos:

        baseline_list = [
            x
            for x in data
            if x[numbers["encoder"]] == args.encoder
            and x[numbers["commit"]] == args.commit
            and x[numbers["preset"]] == args.preset
            and x[numbers["video"]] == video
        ]

        encode_baseline_time = avg(
            [
                (float(x[numbers["first_time"]]) + float(x[numbers["second_time"]]))
                for x in baseline_list
            ]
        )
        decode_baseline_time = avg(
            [float(x[numbers["decode_time"]]) for x in baseline_list]
        )

        for commit in commits:
            # Get the data for this commit not including if the commit and preset are the same as the baseline
            dataset = [
                x
                for x in data
                if x[numbers["commit"]] == commit
                and x[numbers["video"]] == video
                and not baseline_check(x, args)
            ]

            dataset_by_preset = []

            # Generate the data for this commit by preset and add it to the dataset by preset
            for preset in list(set([x[numbers["preset"]] for x in dataset])):
                dataset_by_preset.append(
                    [x for x in dataset if x[numbers["preset"]] == preset]
                )

            for preset_dataset in dataset_by_preset:
                target_encoder = preset_dataset[0][numbers["encoder"]]
                target_commit = preset_dataset[0][numbers["commit"]]
                target_preset = preset_dataset[0][numbers["preset"]]

                vmaf_mean = calculate_metrics(baseline_list, preset_dataset, numbers["vmaf_mean"])
                ssimcra2_mean = calculate_metrics(baseline_list, preset_dataset, numbers["ssimcra2_mean"])
                vmaf_5th = calculate_metrics(baseline_list, preset_dataset, numbers["vmaf_5th"])
                ssimcra2_5th = calculate_metrics(baseline_list, preset_dataset, numbers["ssimcra2_5th"])

                # Calculate time percentage difference
                if encode_baseline_time != 0:
                    encode_flag_time = avg(
                        [
                            (
                                float(x[numbers["first_time"]])
                                + float(x[numbers["second_time"]])
                            )
                            for x in preset_dataset
                        ]
                    )
                    encode_time_diff = round(
                        (
                            (encode_flag_time - encode_baseline_time)
                            / encode_baseline_time
                            * 100
                        ),
                        2,
                    )
                else:
                    encode_time_diff = 0

                if decode_baseline_time != 0:
                    decode_flag_time = avg(
                        [float(x[numbers["decode_time"]]) for x in preset_dataset]
                    )
                    decode_time_diff = round(
                        (
                            (decode_flag_time - decode_baseline_time)
                            / decode_baseline_time
                            * 100
                        ),
                        2,
                    )
                else:
                    decode_time_diff = 0

                ls.append(
                    (
                        args.encoder,
                        args.commit,
                        args.preset,
                        target_encoder,
                        target_commit,
                        target_preset,
                        video,
                        encode_time_diff,
                        decode_time_diff,
                        vmaf_mean,
                        ssimcra2_mean,
                        vmaf_5th,
                        ssimcra2_5th,
                    )
                )

    ls.sort(key=lambda x: x[1])
    with open(args.output, "w") as csvfile:
        csvwriter = csv.writer(csvfile, delimiter=",")
        csvwriter.writerow(
            [
                "Baseline Encoder",
                "Baseline Commit",
                "Baseline Preset",
                "Target Encoder",
                "Target Commit",
                "Target Preset",
                "Video",
                "Encode Time Diff Pct",
                "Decode Time Diff Pct",
                "VMAF Mean",
                "SSIMCRA2 Mean",
                "VMAF 5th",
                "SSIMCRA2 5th",
            ]
        )
        for x in ls:
            csvwriter.writerow(x)


if __name__ == "__main__":
    main()
