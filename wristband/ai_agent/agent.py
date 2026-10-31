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

    activity_agent = ActivityMonitorAgent(band_id)

    activity_report = activity_agent.monitor_activity()

    # --------------------------------
    # AGENT 2: SAFETY INTELLIGENCE
    # --------------------------------

    safety_agent = SafetyIntelligenceAgent()

    safety_decision = safety_agent.evaluate_safety(
        activity_report
    )

    # --------------------------------
    # AGENT 3: CAREGIVER RESPONSE
    # --------------------------------

    caregiver_agent = CaregiverResponseAgent(band_id)

    caregiver_result = caregiver_agent.respond_to_safety_alert(
        safety_decision
    )

    # --------------------------------
    # SAVE FINAL AI INSIGHTS
    # --------------------------------

    routine_insights = (
        activity_report.get("routineInsights") or {}
    )

    final_result = {
        **routine_insights,

        "bandId": band_id,

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

        "latestSteps": activity_report.get("latestSteps", 0),

        "averageActivity": activity_report.get(
            "averageActivity", 0
        ),

        "totalRecords": activity_report.get("totalRecords", 0),

        "caregiverResponse": caregiver_result
    }

    save_ai_insights(band_id, final_result)

    print("\n========================================")
    print("       MULTI-AGENT EXECUTION COMPLETE")
    print("========================================")

    print(json.dumps(final_result, indent=4))


if __name__ == "__main__":
    run_agent()