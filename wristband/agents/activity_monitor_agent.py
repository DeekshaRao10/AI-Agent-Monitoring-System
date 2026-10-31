from firebase_service import get_activity_history
from activity_analyzer import analyze_activity


class ActivityMonitorAgent:

    def __init__(self, band_id):
        self.band_id = band_id

    def monitor_activity(self):

        print("\n===================================")
        print("     ACTIVITY MONITOR AGENT")
        print("===================================")

        # 1. Retrieve activity history
        print("\n[1] Retrieving activity history...")

        records = get_activity_history(self.band_id)

        if not records:
            print("No activity records available.")

            return {
                "success": False,
                "status": "NO_DATA",
                "records": [],
                "insights": None
            }

        print(f"Retrieved {len(records)} activity records.")

        # 2. Analyze activity
        print("\n[2] Analyzing daily activity patterns...")

        insights = analyze_activity(records)

        # 3. Calculate activity statistics
        total_steps = sum(
            int(record.get("activity", 0))
            for record in records
        )

        latest_steps = int(records[-1].get("steps", 0))

        average_activity = round(
            total_steps / len(records), 2
        )

        # 4. Prepare monitoring report
        report = {
            "success": True,
            "bandId": self.band_id,
            "totalRecords": len(records),
            "totalActivity": total_steps,
            "latestSteps": latest_steps,
            "averageActivity": average_activity,
            "routineInsights": insights,
            "records": records
        }

        print("\nActivity monitoring completed!")

        print("\nActivity Summary:")
        print("Total Records:", len(records))
        print("Total Activity:", total_steps)
        print("Latest Step Counter:", latest_steps)
        print("Average Activity:", average_activity)

        return report