from firebase_admin import db, firestore, messaging
from datetime import datetime, timezone


class CaregiverResponseAgent:

    def __init__(self, band_id):
        self.band_id = band_id
        self.firestore = firestore.client()

    def respond_to_safety_alert(self, safety_decision):

        print("\n===================================")
        print("     CAREGIVER RESPONSE AGENT")
        print("===================================")

        status = safety_decision.get("status")

        # Only respond to unusual activity conditions
        alert_statuses = [
            "INACTIVITY_WARNING",
            "UNUSUALLY_LOW_ACTIVITY",
            "UNUSUAL_ACTIVITY"
        ]

        if status not in alert_statuses:
            print("No caregiver alert required.")
            return {"notificationSent": False}

        # Find the band document
        band_query = (
            self.firestore.collection("bands")
            .where("deviceId", "==", self.band_id)
            .limit(1)
            .get()
        )

        if not band_query:
            print("Band document not found.")
            return {"notificationSent": False}

        band_data = band_query[0].to_dict()

        family_id = band_data.get("familyId")
        wearer_uid = band_data.get("wearerUid")

        if not family_id:
            print("No family linked to this band.")
            return {"notificationSent": False}

        # Prevent repeated notifications for the same alert
        state_ref = db.reference(
            f"ai_notification_state/{self.band_id}"
        )

        previous_state = state_ref.get() or {}

        now = int(datetime.now(timezone.utc).timestamp())

        previous_status = previous_state.get("status")
        previous_time = previous_state.get("lastNotification", 0)

        # Allow a repeat notification after 60 minutes
        if (
            previous_status == status
            and now - previous_time < 3600
        ):
            print("Duplicate alert suppressed.")
            return {"notificationSent": False}

        # Retrieve family members
        members = (
            self.firestore.collection("families")
            .document(family_id)
            .collection("members")
            .get()
        )

        sent_count = 0

        for member in members:

            member_data = member.to_dict()
            user_id = member_data.get("uid", member.id)

            # Do not notify the wearer
            if user_id == wearer_uid:
                continue

            # Respect notification preferences
            if member_data.get("notificationsEnabled") is False:
                continue

            user_doc = (
                self.firestore.collection("users")
                .document(user_id)
                .get()
            )

            if not user_doc.exists:
                continue

            token = user_doc.to_dict().get("fcmToken")

            if not token:
                print("No FCM token for:", user_id)
                continue

            # Send caregiver notification
            message = messaging.Message(
                notification=messaging.Notification(
                    title="SafeBand AI Safety Alert",
                    body=safety_decision.get("message", "Unusual activity detected.")
                ),
                data={
                    "type": "ai_safety_alert",
                    "bandId": self.band_id,
                    "status": status
                },
                token=token
            )

            try:
                messaging.send(message)
                sent_count += 1
                print("Notification sent to:", user_id)

            except Exception as error:
                print("Notification failed:", error)

        # Save notification state only if at least one was sent
        if sent_count > 0:
            state_ref.set({
                "status": status,
                "lastNotification": now
            })

        print("Caregiver response completed.")
        print("Notifications sent:", sent_count)

        return {
            "notificationSent": sent_count > 0,
            "recipientsNotified": sent_count,
            "status": status
        }