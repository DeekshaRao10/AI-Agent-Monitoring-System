import os
import firebase_admin

from firebase_admin import credentials, db
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("FIREBASE_DATABASE_URL")


def initialize_firebase():

    if not firebase_admin._apps:

        cred = credentials.Certificate(
            os.path.join(
                os.path.dirname(__file__),
                "serviceAccountKey.json"
            )
        )

        firebase_admin.initialize_app(
            cred,
            {"databaseURL": DATABASE_URL}
        )

    print("Firebase connected successfully!")


def get_activity_history(band_id):

    ref = db.reference(f"activity_history/{band_id}")

    records = ref.get()

    if not records:
        print("No activity records found.")
        return []

    history = []

    for record_id, values in records.items():

        history.append({
            "record_id": record_id,
            "steps": values.get("steps", 0),
            "activity": values.get("activitySincePrevious", 0),
            "timestamp": values.get("timestamp", 0)
        })

    history.sort(key=lambda x: x["timestamp"])

    return history
def save_ai_insights(band_id, insights):
    from datetime import datetime, timezone

    insights["lastUpdated"] = int(
        datetime.now(timezone.utc).timestamp()
    )

    ref = db.reference(f"ai_insights/{band_id}")
    ref.set(insights)

    print("AI insights successfully saved to Firebase!")