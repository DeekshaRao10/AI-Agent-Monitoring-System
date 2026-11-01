import os
import json

from dotenv import load_dotenv

from firebase_service import (
    initialize_firebase,
    save_ai_insights
)

from agents.activity_monitor_agent import ActivityMonitorAgent
from agents.safety_intelligence_agent import SafetyIntelligenceAgent
from agents.caregiver_response_agent import CaregiverResponseAgent


def run_agent():

    print("\n========================================")
    print("       SAFEBAND MULTI-AGENT SYSTEM")
    print("========================================")

    load_dotenv()

    band_id = os.getenv("BAND_ID")

    if not band_id:
        print("ERROR: BAND_ID missing from .env")
        return

    # Initialize Firebase
    initialize_firebase()

    # --------------------------------
    # AGENT 1: ACTIVITY MONITOR
    # --------------------------------

    print("\n[AGENT 1] Starting Activity Monitor...")

    activity_agent = ActivityMonitorAgent(band_id)

    activity_report = activity_agent.monitor_activity()

    # --------------------------------
    # AGENT 2: SAFETY INTELLIGENCE
    # --------------------------------

    print("\n[AGENT 2] Starting Safety Intelligence...")

    safety_agent = SafetyIntelligenceAgent()

    safety_decision = safety_agent.evaluate_safety(
        activity_report
    )

    # --------------------------------
    # AGENT 3: CAREGIVER RESPONSE
    # --------------------------------

    print("\n[AGENT 3] Starting Caregiver Response...")

    caregiver_agent = CaregiverResponseAgent(band_id)

    caregiver_result = caregiver_agent.respond_to_safety_alert(
        safety_decision
    )

    # --------------------------------
    # PREPARE FINAL FIREBASE DATA
    # --------------------------------

    routine_insights = (
        activity_report.get("routineInsights") or {}
    )

    final_result = {

        # Activity information
        **routine_insights,

        "bandId": band_id,

        "latestSteps": activity_report.get(
            "latestSteps",
            routine_insights.get("latestSteps", 0)
        ),

        "averageActivity": activity_report.get(
            "averageActivity",
            routine_insights.get("averageActivity", 0)
        ),

        "daysRecorded": routine_insights.get(
            "daysRecorded", 0
        ),

        "totalActivity": activity_report.get(
            "totalActivity", 0
        ),

        "totalRecords": activity_report.get(
            "totalRecords", 0
        ),

        # Safety decision
        "status": safety_decision.get("status"),

        "message": safety_decision.get("message"),

        "recommendedAction": safety_decision.get(
            "recommendedAction"
        ),

        "anomalyDetected": safety_decision.get(
            "anomaly_detected", False
        ),

        "anomalyDetection": safety_decision.get(
            "anomalyDetection", {}
        ),

        # Caregiver response
        "caregiverResponse": caregiver_result
    }

    # --------------------------------
    # SAVE TO FIREBASE
    # --------------------------------

    print("\n[FINAL] Saving AI insights to Firebase...")

    save_ai_insights(band_id, final_result)

    print("\n========================================")
    print("       MULTI-AGENT EXECUTION COMPLETE")
    print("========================================")

    print("\nFINAL FIREBASE DATA:")

    print(json.dumps(final_result, indent=4))


if __name__ == "__main__":
    run_agent()