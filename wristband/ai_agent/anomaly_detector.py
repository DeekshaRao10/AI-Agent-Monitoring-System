import numpy as np
from sklearn.ensemble import IsolationForest


def detect_anomalies(activity_values):

    print("\n===== SAFEBAND AI ANOMALY DETECTION =====")

    # Convert activity values into numerical data
    activity_values = np.array(activity_values, dtype=float)

    # Remove invalid values
    activity_values = activity_values[
        np.isfinite(activity_values)
    ]

    if len(activity_values) == 0:
        return {
            "anomaly_detected": False,
            "status": "COLLECTING_DATA",
            "message": "No valid activity data available."
        }

    latest_activity = float(activity_values[-1])

    # Calculate historical activity baseline
    average_activity = float(np.mean(activity_values))
    std_activity = float(np.std(activity_values))

    print("Total records:", len(activity_values))
    print("Average activity:", round(average_activity, 2))
    print("Latest activity:", latest_activity)

    # Need sufficient data to establish a baseline
    if len(activity_values) < 5:

        return {
            "anomaly_detected": False,
            "status": "COLLECTING_DATA",
            "message": "Collecting more activity data.",
            "latestActivity": latest_activity,
            "averageActivity": round(average_activity, 2)
        }

    # Detect unusually low activity
    if latest_activity == 0 and average_activity > 0:

        print("Unusual inactivity detected!")

        return {
            "anomaly_detected": True,
            "status": "INACTIVITY_WARNING",
            "message": (
                "No steps were recorded in the latest interval. "
                "Consider checking whether the wearer is active."
            ),
            "latestActivity": latest_activity,
            "averageActivity": round(average_activity, 2)
        }

    # Detect activity significantly below historical average
    if (
        average_activity > 0
        and latest_activity < average_activity * 0.25
    ):

        print("Unusually low activity detected!")

        return {
            "anomaly_detected": True,
            "status": "UNUSUALLY_LOW_ACTIVITY",
            "message": (
                "Recent activity is significantly lower "
                "than the historical average."
            ),
            "latestActivity": latest_activity,
            "averageActivity": round(average_activity, 2)
        }

    # Isolation Forest anomaly detection
    if len(activity_values) >= 20:

        data = activity_values[:-1].reshape(-1, 1)

        model = IsolationForest(
            contamination=0.10,
            random_state=42
        )

        model.fit(data)

        latest_data = np.array(
            [[latest_activity]]
        )

        prediction = model.predict(latest_data)[0]

        if prediction == -1:

            print("Unusual activity pattern detected!")

            return {
                "anomaly_detected": True,
                "status": "UNUSUAL_ACTIVITY",
                "message": (
                    "Latest activity differs significantly "
                    "from the historical activity pattern."
                ),
                "latestActivity": latest_activity,
                "averageActivity": round(average_activity, 2)
            }

    print("Activity pattern appears consistent.")

    return {
        "anomaly_detected": False,
        "status": "NORMAL_ACTIVITY",
        "message": "No unusual activity detected.",
        "latestActivity": latest_activity,
        "averageActivity": round(average_activity, 2)
    }