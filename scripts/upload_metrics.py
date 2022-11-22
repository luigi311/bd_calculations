#!/usr/bin/env python3
import psycopg, os, argparse, csv, traceback

from pathlib import Path
from dotenv import load_dotenv

load_dotenv(override=True)


def get_values(cur, table):
    cur.execute(f"SELECT * FROM {table}")

    return cur.fetchall()


def select(cur, statement):
    cur.execute(f"SELECT {statement}")
    return cur.fetchall()


def lookup_to_dictionary(lookup):
    return {row[1]: row[0] for row in lookup}


def row_in_data(row, data, encoders, videos, types):
    for data_row in data:
        if types=="calculations":
            if (
                data_row[2] == encoders[row[0]] 
                and data_row[3] == row[1]
                and int(data_row[4]) == int(row[2])
                and data_row[5] == encoders[row[3]]
                and data_row[6] == row[4]
                and int(data_row[7]) == int(row[5])
                and data_row[8] == videos[row[6]]
            ):
                return True
        elif types=="results":
            if(
                data_row[2] == encoders[row[0]]
                and data_row[3] == row[1]
                and int(data_row[4]) == int(row[2])
                and data_row[5] == videos[row[3]]
                and float(data_row[6]) == float(row[4])
                and data_row[7] == row[5]
                and float(data_row[8]) == float(row[6])
                and float(data_row[9]) == float(row[7])
                and float(data_row[10]) == float(row[8])
                and float(data_row[11]) == float(row[9])
                and float(data_row[12]) == float(row[10])
            ):
                return True


    return False

def add_video_if_not_exist(cur, conn, video, videos):
    # Add video to videos lookup if not exist
    if video not in videos:
        cur.execute(
            f"INSERT INTO videos_lookup (name) VALUES ('{video}')"
        )
        conn.commit()
        videos = lookup_to_dictionary(get_values(cur, "videos_lookup"))
    
    return videos

def calculations(cur, conn, reader, encoders, videos, timestamp):
    data = get_values(cur, "calculations")
    for row in reader:
        # If row is in the database skip
        if row_in_data(row, data, encoders, videos, "calculations"):
            continue

        # Update videos list
        videos = add_video_if_not_exist(cur, conn, row[6], videos)

        # insert row into calculations table
        cur.execute(
            "INSERT INTO calculations (timestamp, baseline_encoder_fkey, baseline_encoder_commit, baseline_encoder_preset, target_encoder_fkey, target_encoder_commit, target_encoder_preset, video_fkey, encode_time_pct, decode_time_pct, vmaf) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (
                timestamp,
                encoders[row[0]],
                row[1],
                row[2],
                encoders[row[3]],
                row[4],
                row[5],
                videos[row[6]],
                row[7],
                row[8],
                row[9],
            ),
        )

def results(cur, conn, reader, encoders, videos, timestamp):
    data = get_values(cur, "results")
    for row in reader:
        # If row is in the database skip
        if row_in_data(row, data, encoders, videos, "results"):
            continue

        # Update videos list
        videos = add_video_if_not_exist(cur, conn, row[6], videos)

        # insert row into calculations table
        cur.execute(
            "INSERT INTO results (timestamp, encoder_fkey, commit, preset, video_fkey, size, quality, bitrate, first_encode_time, second_encode_time, decode_time, vmaf) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (
                timestamp,
                encoders[row[0]],
                row[1],
                row[2],
                videos[row[3]],
                row[4],
                row[5],
                row[6],
                row[7],
                row[8],
                row[9],
                row[10]
            ),
        )


def main():
    parser = argparse.ArgumentParser(description="Upload metrics to the database")
    parser.add_argument("--input", "-i", type=Path, help="Input File")
    parser.add_argument("--type", "-t", type=str, choices=["calculations", "results"], help="calculations for bd_rate files, results for result csv files")
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
