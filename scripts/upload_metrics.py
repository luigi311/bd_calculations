#!/usr/bin/env python3
import psycopg, os, argparse, csv

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


def row_in_data(row, data, encoders, videos):
    for data_row in data:
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

    return False


def main():
    parser = argparse.ArgumentParser(description="Upload metrics to the database")
    parser.add_argument("--input", "-i", type=Path, help="Input File")
    args = parser.parse_args()

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
                next(reader)

                for row in reader:
                    # Check if row is in the database
                    data = get_values(cur, "calculations")

                    # Check if row is in the database
                    if row_in_data(row, data, encoders, videos):
                        continue

                    # Check if video is in the database
                    if row[6] not in videos:
                        cur.execute(
                            f"INSERT INTO videos_lookup (name) VALUES ('{row[6]}')"
                        )
                        conn.commit()
                        videos = lookup_to_dictionary(get_values(cur, "videos_lookup"))

                    # insert row into calculations table
                    cur.execute(
                        "INSERT INTO calculations (timestamp, baseline_encoder_fkey, baseline_encoder_commit, baseline_encoder_preset, target_encoder_fkey, target_encoder_commit, target_encoder_preset, video_fkey, encode_time_pct, decode_time_pct, vmaf, ssimulacra2) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
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
                            row[10],
                        ),
                    )


if __name__ == "__main__":
    main()
