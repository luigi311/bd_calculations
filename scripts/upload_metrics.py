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
res_vmaf_mean = 10
res_ssim2_mean = 11
res_vmaf_5th = 12
res_ssim2_5th = 13

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
cal_vmaf_mean = 9
cal_ssim2_mean = 10
cal_vmaf_5th = 11
cal_ssim2_5th = 12


def get_values_from_table(cur, table):
    return statment_fetchall(cur, f"SELECT * FROM {table}")


def statment_fetchall(cur, statement):
    cur.execute(f"{statement}")
    return cur.fetchall()


def statment_fetchone(cur, statement):
    cur.execute(f"{statement}")
    return cur.fetchone()


def lookup_to_dictionary(lookup):
    return {row[1]: row[0] for row in lookup}


def row_in_data(row, cur, encoders_lookup, videos_lookup, types):
    if types == "calculations":
        statement = f"""
            SELECT * FROM calculations
            WHERE
                baseline_encoder_fkey = {encoders_lookup[row[cal_base_encoder]]}
                AND baseline_encoder_commit = '{row[cal_base_commit]}'
                AND baseline_encoder_preset = '{row[cal_base_preset]}'
                AND target_encoder_fkey = {encoders_lookup[row[cal_tar_encoder]]}
                AND target_encoder_commit = '{row[cal_tar_commit]}'
                AND target_encoder_preset = '{row[cal_tar_preset]}'
                AND video_fkey = {videos_lookup[row[cal_video]]}
        """

        if statment_fetchone(cur, statement):
            return True
    elif types == "results":
        statement = f"""
            SELECT * FROM results
            WHERE
                encoder_fkey = {encoders_lookup[row[res_encoder]]}
                AND commit = '{row[res_commit]}'
                AND preset = '{row[res_preset]}'
                AND video_fkey = {videos_lookup[row[res_video]]}
                AND quality = '{row[res_quality]}'
        """
        if statment_fetchone(cur, statement):
            return True

    return False


def add_to_lookup(cur, conn, record, lookup):
    # Add video to videos lookup
    cur.execute(f"INSERT INTO {lookup} (name) VALUES ('{record}')")
    conn.commit()
    lookup_values = lookup_to_dictionary(get_values_from_table(cur, lookup))

    return lookup_values


def calculations(cur, conn, csv_data, encoders_lookup, videos_lookup, timestamp):
    for row in csv_data:
        # Add baseline encoder to encoders lookup if it does not exist
        if row[cal_base_encoder] not in encoders_lookup:
            # Update encoders list
            encoders_lookup = add_to_lookup(cur, conn, row[cal_base_encoder], "encoders_lookup")
        
        # Add target encoder to encoders lookup if it does not exist
        if row[cal_tar_encoder] not in encoders_lookup:
            # Update encoders list
            encoders_lookup = add_to_lookup(cur, conn, row[cal_tar_encoder], "encoders_lookup")

        # Add video to videos lookup if it does not exist
        if row[cal_video] not in videos_lookup:
            # Update videos list
            videos_lookup = add_to_lookup(cur, conn, row[cal_video], "videos_lookup")

        # If row is in the database skip
        if row_in_data(row, cur, encoders_lookup, videos_lookup, "calculations"):
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
                , ssimulacra2
                , vmaf_5th
                , ssimulacra2_5th
            ) VALUES (
                '{timestamp}'
                , {encoders_lookup[row[cal_base_encoder]]}
                , '{row[cal_base_commit]}'
                , '{row[cal_base_preset]}'
                , {encoders_lookup[row[cal_tar_encoder]]}
                , '{row[cal_tar_commit]}'
                , '{row[cal_tar_preset]}'
                , {videos_lookup[row[cal_video]]}
                , '{row[cal_encode_time]}'
                , '{row[cal_decode_time]}'
                , '{row[cal_vmaf_mean]}'
                , '{row[cal_ssim2_mean]}'
                , '{row[cal_vmaf_5th]}'
                , '{row[cal_ssim2_5th]}'
            )"""
        )
    
    conn.commit()


def results(cur, conn, csv_data, encoders_lookup, videos_lookup, timestamp):
    for row in csv_data:
        # Add encoder to encoders lookup if it does not exist
        if row[res_encoder] not in encoders_lookup:
            # Update encoders list
            encoders_lookup = add_to_lookup(cur, conn, row[res_encoder], "encoders_lookup")
        
        # Add video to videos lookup if it does not exist
        if row[res_video] not in videos_lookup:
            # Update videos list
            videos_lookup = add_to_lookup(cur, conn, row[res_video], "videos_lookup")

        # If row is in the database skip
        if row_in_data(row, cur, encoders_lookup, videos_lookup, "results"):
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
                , ssimulacra2
                , vmaf_5th
                , ssimulacra2_5th
            ) VALUES (
                '{timestamp}'
                , {encoders_lookup[row[res_encoder]]}
                , '{row[res_commit]}'
                , '{row[res_preset]}'
                , {videos_lookup[row[res_video]]}
                , '{row[res_size]}'
                , '{row[res_quality]}'
                , '{row[res_bitrate]}'
                , '{row[res_1_encode_time]}'
                , '{row[res_2_encode_time]}'
                , '{row[res_decode_time]}'
                , '{row[res_vmaf_mean]}'
                , '{row[res_ssim2_mean]}'
                , '{row[res_vmaf_5th]}'
                , '{row[res_ssim2_5th]}'
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

                encoders_lookup = lookup_to_dictionary(get_values_from_table(cur, "encoders_lookup"))
                videos_lookup = lookup_to_dictionary(get_values_from_table(cur, "videos_lookup"))

                # Convert epoch time to postgres timestamp with mst timezone
                timestamp_statement = f"to_timestamp({os.path.getmtime(args.input)})"

                # get timestamp from database
                timestamp = statment_fetchall(cur, f"SELECT {timestamp_statement}")[0][0]

                with open(args.input) as csvfile:
                    reader = csv.reader(csvfile, delimiter=",")
                    # Skip headers
                    next(reader)

                    csv_data = [row for row in reader]

                    if args.type == "calculations":
                        calculations(cur, conn, csv_data, encoders_lookup, videos_lookup, timestamp)
                    elif args.type == "results":
                        results(cur, conn, csv_data, encoders_lookup, videos_lookup, timestamp)
                    else:
                        raise Exception("Invalid type argument")
    except Exception as err:
        print(f"Unexpected {err=}, {type(err)=}")
        print(traceback.format_exc())


if __name__ == "__main__":
    main()
