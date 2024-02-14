#!/usr/bin/env python3
import psycopg, os, argparse, csv, traceback

from pathlib import Path
from dotenv import load_dotenv

load_dotenv(override=True)

# Database results table columns
res_db_pkey = 0
res_db_timestamp = 1
res_db_encoder_fkey = 2
res_db_commit = 3
res_db_preset = 4
res_db_video_fkey = 5
res_db_size = 6
res_db_quality = 7
res_db_bitrate = 8
res_db_first_encode_time = 9
res_db_second_encode_time = 10
res_db_decode_time = 11
res_db_vmaf = 12
res_db_ssimulacra2 = 13

# CSV results columns
res_row_encoder = 0
res_row_commit = 1
res_row_preset = 2
res_row_video = 3
res_row_size = 4
res_row_quality = 5
res_row_bitrate = 6
res_row_first_encode_time = 7
res_row_second_encode_time = 8
res_row_decode_time = 9
res_row_vmaf = 10
res_row_ssimulacra2 = 11

# Database calculations table columns
cal_db_pkey = 0
cal_db_timestamp = 1
cal_db_base_encoder_fkey = 2
cal_db_base_encoder_commit = 3
cal_db_base_encoder_preset = 4
cal_db_tar_encoder_fkey = 5
cal_db_tar_encoder_commit = 6
cal_db_tar_encoder_preset = 7
cal_db_video_fkey = 8
cal_db_encode_time_pct = 9
cal_db_decode_time_pct = 10
cal_db_vmaf = 11
cal_db_ssimulacra2 = 12

# CSV calculations columns
cal_row_base_encoder = 0
cal_row_base_commit = 1
cal_row_base_preset = 2
cal_row_tar_encoder = 3
cal_row_tar_commit = 4
cal_row_tar_preset = 5
cal_row_video = 6
cal_row_encode_time = 7
cal_row_decode_time = 8
cal_row_vmaf = 9
cal_row_ssimulacra2 = 10


def get_values(cur, table):
    cur.execute(f"SELECT * FROM {table}")

    return cur.fetchall()


def select(cur, statement):
    cur.execute(f"SELECT {statement}")
    return cur.fetchall()


def lookup_to_dictionary(lookup):
    return {row[1]: row[0] for row in lookup}


def row_in_data(row, database, encoders, videos, types):
    for database_row in database:
        if types == "calculations":
            if (
                database_row[cal_db_base_encoder_fkey] == encoders[row[cal_row_base_encoder]]
                and database_row[cal_db_base_encoder_commit] == row[cal_row_base_commit]
                and database_row[cal_db_base_encoder_preset] == row[cal_row_base_preset]
                and database_row[cal_db_tar_encoder_fkey] == encoders[row[cal_row_tar_encoder]]
                and database_row[cal_db_tar_encoder_commit] == row[cal_row_tar_commit]
                and database_row[cal_db_tar_encoder_preset] == row[cal_row_tar_preset]
                and database_row[cal_db_video_fkey] == videos[row[cal_row_video]]
            ):
                return True
        elif types == "results":
            if (
                database_row[res_db_encoder_fkey] == encoders[row[res_row_encoder]]
                and database_row[res_db_commit] == row[res_row_commit]
                and database_row[res_db_preset] == row[res_row_preset]
                and database_row[res_db_video_fkey] == videos[row[res_row_video]]
                and float(database_row[res_db_size]) == float(row[res_row_size])
                and database_row[res_db_quality] == row[res_row_quality]
                and float(database_row[res_db_bitrate]) == float(row[res_row_bitrate])
                and float(database_row[res_db_first_encode_time]) == float(row[res_row_first_encode_time])
                and float(database_row[res_db_second_encode_time]) == float(row[res_row_second_encode_time])
                and float(database_row[res_db_decode_time]) == float(row[res_row_decode_time])
                and float(database_row[res_db_vmaf]) == float(row[res_row_vmaf])
            ):
                return True

    return False


def add_video_if_not_exist(cur, conn, video, videos):
    # Add video to videos lookup
    cur.execute(f"INSERT INTO videos_lookup (name) VALUES ('{video}')")
    conn.commit()
    videos = lookup_to_dictionary(get_values(cur, "videos_lookup"))

    return videos


def calculations(cur, conn, reader, encoders, videos, timestamp):
    database = get_values(cur, "calculations")
    for row in reader:
        # Add video to videos lookup if it does not exist
        if row[6] not in videos:
            # Update videos list
            videos = add_video_if_not_exist(cur, conn, row[cal_row_video], videos)

        # If row is in the database skip
        if row_in_data(row, database, encoders, videos, "calculations"):
            continue

        # insert row into calculations table
        cur.execute(
            """INSERT INTO calculations (timestamp
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
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                timestamp,
                encoders[row[cal_row_base_encoder]],
                row[cal_row_base_commit],
                row[cal_row_base_preset],
                encoders[row[cal_row_tar_encoder]],
                row[cal_row_tar_commit],
                row[cal_row_tar_preset],
                videos[row[cal_row_video]],
                row[cal_row_encode_time],
                row[cal_row_decode_time],
                row[cal_row_vmaf],
            ),
        )


def results(cur, conn, reader, encoders, videos, timestamp):
    database = get_values(cur, "results")
    for row in reader:
        # Add video to videos lookup if it does not exist
        if row[3] not in videos:
            # Update videos list
            videos = add_video_if_not_exist(cur, conn, row[res_row_video], videos)

        # If row is in the database skip
        if row_in_data(row, database, encoders, videos, "results"):
            continue

        # insert row into calculations table
        cur.execute(
            """INSERT INTO results (timestamp
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
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                timestamp,
                encoders[row[res_row_encoder]],
                row[res_row_commit],
                row[res_row_preset],
                videos[row[res_row_video]],
                row[res_row_size],
                row[res_row_quality],
                row[res_row_bitrate],
                row[res_row_first_encode_time],
                row[res_row_second_encode_time],
                row[res_row_decode_time],
                row[res_row_vmaf],
            ),
        )


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

                encoders = lookup_to_dictionary(get_values(cur, "encoders_lookup"))
                videos = lookup_to_dictionary(get_values(cur, "videos_lookup"))

                # Convert epoch time to postgres timestamp with mst timezone
                timestamp_statement = f"to_timestamp({os.path.getmtime(args.input)})"

                # get timestamp from database
                timestamp = select(cur, f"{timestamp_statement}")[0][0]

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
