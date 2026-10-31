import pandas as pd
from datetime import datetime


def analyze_activity(records):

    print("\n===== SAFEBAND ACTIVITY ANALYSIS =====")

    if not records:
        return {
            "status": "NO_DATA",
            "message": "No activity records available."
        }

    # Convert Firebase records into a DataFrame
    df = pd.DataFrame(records)

    # Convert timestamps into readable dates
    df["datetime"] = pd.to_datetime(
        df["timestamp"],
        unit="s",
        errors="coerce"
    )

    df["steps"] = pd.to_numeric(
        df["steps"], errors="coerce"
    )

    df["activity"] = pd.to_numeric(
        df["activity"], errors="coerce"
    )

    df = df.dropna(
        subset=["datetime", "steps", "activity"]
    )

    if df.empty:
        return {
            "status": "INVALID_DATA",
            "message": "No valid activity records."
        }

    # Sort records by time
    df = df.sort_values("datetime")

    # Calculate total recorded activity
    total_activity = int(df["activity"].sum())

    average_activity = float(
        df["activity"].mean()
    )

    latest_steps = int(df.iloc[-1]["steps"])

    first_time = df.iloc[0]["datetime"]
    latest_time = df.iloc[-1]["datetime"]

    # Check how many different days are available
    days_recorded = df["datetime"].dt.date.nunique()

    # Display analysis
    print("Total records:", len(df))
    print("Days recorded:", days_recorded)
    print("Total recorded interval activity:", total_activity)
    print("Average activity per record:", round(average_activity, 2))
    print("Latest step counter:", latest_steps)

    print("First reading:", first_time)
    print("Latest reading:", latest_time)

    # Check whether enough historical data exists
    if days_recorded < 7:

        print("\nAI Observation:")
        print("Not enough historical data to establish")
        print("the wearer's normal daily routine.")

        return {
            "status": "COLLECTING_BASELINE",
            "totalActivity": total_activity,
            "averageActivity": average_activity,
            "latestSteps": latest_steps,
            "daysRecorded": int(days_recorded),
            "message": "Collecting historical activity data."
        }

    # Group activity by hour
    df["hour"] = df["datetime"].dt.hour

    hourly_activity = (
        df.groupby("hour")["activity"]
        .mean()
        .to_dict()
    )

    print("\nHourly Activity Pattern:")

    for hour, activity in hourly_activity.items():

        print(
            f"{int(hour):02d}:00 - "
            f"Average interval activity: {activity:.2f}"
        )

    return {
        "status": "BASELINE_AVAILABLE",
        "totalActivity": total_activity,
        "averageActivity": average_activity,
        "latestSteps": latest_steps,
        "daysRecorded": int(days_recorded),
        "message": "Historical activity analysis completed."
    }