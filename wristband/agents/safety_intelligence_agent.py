from anomaly_detector import detect_anomalies


class SafetyIntelligenceAgent:

    def evaluate_safety(self, activity_report):

        print("\n===================================")
        print("   SAFETY INTELLIGENCE AGENT")
        print("===================================")

        # Check whether activity data exists
        if not activity_report.get("success"):

            return {
                "status": "COLLECTING_DATA",
                "anomaly_detected": False,
                "message": "Waiting for activity data.",
                "recommendedAction": "Continue monitoring."
            }

        # Retrieve activity information
        records = activity_report["records"]

        activity_values = [
            record["activity"]
            for record in records
        ]

        # Detect anomalies
        print("\n[1] Evaluating activity patterns...")

        anomaly_result = detect_anomalies(activity_values)

        anomaly_status = anomaly_result.get("status")

        # Make safety decision
        print("\n[2] Making safety decision...")

        if anomaly_status == "INACTIVITY_WARNING":

            status = "INACTIVITY_WARNING"

            message = (
                "Unusual inactivity detected during the latest "
                "activity interval."
            )

            action = (
                "Consider checking whether the wearer is active and safe."
            )

        elif anomaly_status == "UNUSUALLY_LOW_ACTIVITY":

            status = "UNUSUALLY_LOW_ACTIVITY"

            message = (
                "Recent activity is significantly lower than "
                "the historical activity average."
            )

            action = "Consider contacting the wearer."

        elif anomaly_status == "UNUSUAL_ACTIVITY":

            status = "UNUSUAL_ACTIVITY"

            message = (
                "The latest activity differs from the historical pattern."
            )

            action = "Consider checking in with the wearer."

        elif anomaly_status == "COLLECTING_DATA":

            status = "COLLECTING_BASELINE"

            message = (
                "More activity data is required to establish "
                "the wearer's activity baseline."
            )

            action = "Continue collecting activity data."

        else:

            status = "NORMAL_ACTIVITY"

            message = "No unusual activity was identified."

            action = "Continue routine activity monitoring."

        # Prepare safety decision
        decision = {

            "status": status,

            "anomaly_detected": anomaly_result.get(
                "anomaly_detected", False
            ),

            "message": message,

            "recommendedAction": action,

            "anomalyDetection": anomaly_result

        }

        print("\nSafety decision completed!")
        print("Status:", status)
        print("Recommended action:", action)

        return decision