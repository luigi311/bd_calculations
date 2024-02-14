#!/usr/bin/env python3
import psycopg, os, argparse, csv, traceback

from pathlib import Path
from dotenv import load_dotenv

load_dotenv(override=True)

# CSV results columns
res_encoder = 0
res_commit = 1
res_preset = 2
res_video = 3
res_size = 4
res_quality = 5
res_bitrate = 6
res_1_encode_time = 7
res_2_encode_time = 8
res_decode_time = 9
res_vmaf = 10
res_ssim2 = 11

# CSV calculations columns
cal_base_encoder = 0
cal_base_commit = 1
cal_base_preset = 2
cal_tar_encoder = 3
cal_tar_commit = 4
cal_tar_preset = 5
cal_video = 6
cal_encode_time = 7
cal_decode_time = 8
cal_vmaf = 9
cal_ssim2 = 10


def get_values_from_table(cur, table):
    return statment_fetchall(cur, f"SELECT * FROM {table}")


def statment_fetchall(cur, statement):
    cur.execute(f"{statement}")
    return cur.fetchall()


def lookup_to_dictionary(lookup):
    return {row[1]: row[0] for row in lookup}


def row_in_data(row, cur, encoders, videos, types):
    if types == "calculations":
        statement = f"""
            SELECT * FROM calculations
            WHERE
                baseline_encoder_fkey = {encoders[row[cal_base_encoder]]}
                AND baseline_encoder_commit = '{row[cal_base_commit]}'
                AND baseline_encoder_preset = '{row[cal_base_preset]}'
                AND target_encoder_fkey = {encoders[row[cal_tar_encoder]]}
                AND target_encoder_commit = '{row[cal_tar_commit]}'
                AND target_encoder_preset = '{row[cal_tar_preset]}'
                AND video_fkey = {videos[row[cal_video]]}
        """

        if statment_fetchall(cur, statement):
            return True
    elif types == "results":
        statement = f"""
            SELECT * FROM results
            WHERE
                encoder_fkey = {encoders[row[res_encoder]]}
                AND commit = '{row[res_commit]}'
                AND preset = '{row[res_preset]}'
                AND video_fkey = {videos[row[res_video]]}
                AND quality = '{row[res_quality]}'
        """
        if statment_fetchall(cur, statement):
            return True

    return False


def add_video_if_not_exist(cur, conn, video, videos):
    # Add video to videos lookup
    cur.execute(f"INSERT INTO videos_lookup (name) VALUES ('{video}')")
    conn.commit()
    videos = lookup_to_dictionary(get_values_from_table(cur, "videos_lookup"))

    return videos


def calculations(cur, conn, reader, encoders, videos, timestamp):
    for row in reader:
        # Add video to videos lookup if it does not exist
        if row[cal_video] not in videos:
            # Update videos list
            videos = add_video_if_not_exist(cur, conn, row[cal_video], videos)

        # If row is in the database skip
        if row_in_data(row, cur, encoders, videos, "calculations"):
            continue

        # insert row into calculations table
        cur.execute(
            f"""
            INSERT INTO calculations (
                timestamp
                , baseline_encoder_fkey
                , baseline_encoder_commit
                , baseline_encoder_preset
                , target_encoder_fkey
                , target_encoder_commit
                , target_encoder_preset
                , video_fkey
                , encode_time_pct
                , decode_time_pct
                , vmaf
            ) VALUES (
                '{timestamp}'
                , {encoders[row[cal_base_encoder]]}
                , '{row[cal_base_commit]}'
                , '{row[cal_base_preset]}'
                , {encoders[row[cal_tar_encoder]]}
                , '{row[cal_tar_commit]}'
                , '{row[cal_tar_preset]}'
                , {videos[row[cal_video]]}
                , '{row[cal_encode_time]}'
                , '{row[cal_decode_time]}'
                , '{row[cal_vmaf]}'
            )"""
        )
    
    conn.commit()


def results(cur, conn, reader, encoders, videos, timestamp):
    for row in reader:
        # Add video to videos lookup if it does not exist
        if row[res_video] not in videos:
            # Update videos list
            videos = add_video_if_not_exist(cur, conn, row[res_video], videos)

        # If row is in the database skip
        if row_in_data(row, cur, encoders, videos, "results"):
            continue

        # insert row into calculations table
        cur.execute(
            f"""
            INSERT INTO results (
                timestamp
                , encoder_fkey
                , commit
                , preset
                , video_fkey
                , size
                , quality
                , bitrate
                , first_encode_time
                , second_encode_time
                , decode_time
                , vmaf
            ) VALUES (
                '{timestamp}'
                , {encoders[row[res_encoder]]}
                , '{row[res_commit]}'
                , '{row[res_preset]}'
                , {videos[row[res_video]]}
                , '{row[res_size]}'
                , '{row[res_quality]}'
                , '{row[res_bitrate]}'
                , '{row[res_1_encode_time]}'
                , '{row[res_2_encode_time]}'
                , '{row[res_decode_time]}'
                , '{row[res_vmaf]}'
            )"""
        )
    
    conn.commit()


def main():
    parser = argparse.ArgumentParser(description="Upload metrics to the database")
    parser.add_argument("--input", "-i", type=Path, help="Input File")
    parser.add_argument(
        "--type",
        "-t",
        type=str,
        choices=["calculations", "results"],
        help="calculations for bd_rate files, results for result csv files",
    )
    args = parser.parse_args()

    try:
        with psycopg.connect(
            f"dbname={os.getenv('DBNAME')} user={os.getenv('USER')} password={os.getenv('PASSWORD')} host={os.getenv('HOST')} port={os.getenv('PORT')}"
        ) as conn:

            with conn.cursor() as cur:

                encoders = lookup_to_dictionary(get_values_from_table(cur, "encoders_lookup"))
                videos = lookup_to_dictionary(get_values_from_table(cur, "videos_lookup"))

                # Convert epoch time to postgres timestamp with mst timezone
                timestamp_statement = f"to_timestamp({os.path.getmtime(args.input)})"

                # get timestamp from database
                timestamp = statment_fetchall(cur, f"SELECT {timestamp_statement}")[0][0]

                with open(args.input) as csvfile:
                    reader = csv.reader(csvfile, delimiter=",")
                    # Skip headers
                    next(reader)

                    if args.type == "calculations":
                        calculations(cur, conn, reader, encoders, videos, timestamp)
                    elif args.type == "results":
                        results(cur, conn, reader, encoders, videos, timestamp)
                    else:
                        raise Exception("Invalid type argument")
    except Exception as err:
        print(f"Unexpected {err=}, {type(err)=}")
        print(traceback.format_exc())


if __name__ == "__main__":
    main()
