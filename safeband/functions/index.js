
Functions index · JS
const { onValueWritten } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");
 
admin.initializeApp();
 
// Fires on every write to /bands/{deviceId}/fallDetected in the Realtime
// Database. The ESP32 re-uploads the whole band object (heartRate, spo2,
// fallDetected, status) every 5 seconds, including for the entire 5-minute
// emergency window, so this WILL fire repeatedly while fallDetected stays
// true. We only want to actually send a push once, on the false/missing ->
// true transition, not on every one of those repeat writes.
exports.onFallDetected = onValueWritten(
  {
    ref: "/bands/{deviceId}/fallDetected",
    instance: "safeband-a3b89-default-rtdb",
    region: "asia-southeast1",
  },
  async (event) => {
    const before = event.data.before.exists()
      ? event.data.before.val()
      : false;
    const after = event.data.after.exists() ? event.data.after.val() : false;
 
    if (before === true || after !== true) {
      // Either this isn't a transition into an emergency (already was true,
      // or the new value isn't true at all) — nothing to send.
      return;
    }
 
    const deviceId = event.params.deviceId;
    console.log(`Fall detected for band ${deviceId}`);
 
    const firestore = admin.firestore();
 
    // 1. Find the Firestore "bands" doc for this physical device.
    const bandsSnap = await firestore
      .collection("bands")
      .where("deviceId", "==", deviceId)
      .limit(1)
      .get();
 
    if (bandsSnap.empty) {
      console.log(`No Firestore band found for deviceId ${deviceId}`);
      return;
    }
 
    const band = bandsSnap.docs[0].data();
    const familyId = band.familyId;
    const bandName = band.bandName || "SafeBand";
    const wearerName = band.wearerName || "A family member";
 
    if (!familyId) {
      console.log(`Band ${deviceId} has no familyId set`);
      return;
    }
 
    // 2. Get every member of that family.
    const membersSnap = await firestore
      .collection("families")
      .doc(familyId)
      .collection("members")
      .get();
 
    if (membersSnap.empty) {
      console.log(`No members found for family ${familyId}`);
      return;
    }
 
    const memberUids = membersSnap.docs.map((doc) => doc.id);
 
    // 3. Look up each member's saved FCM token from users/{uid}.
    const tokens = [];
 
    await Promise.all(
      memberUids.map(async (uid) => {
        const userSnap = await firestore.collection("users").doc(uid).get();
        const token = userSnap.data()?.fcmToken;
        if (token) tokens.push(token);
      })
    );
 
    if (tokens.length === 0) {
      console.log("No FCM tokens found for this family's members");
      return;
    }
 
    // 4. Send the push notification to every family member's device.
    const message = {
      notification: {
        title: "🚨 Fall Detected!",
        body: `${wearerName} (${bandName}) may have fallen. Tap to check on them.`,
      },
      data: {
        type: "FALL_DETECTED",
        deviceId: deviceId,
        bandName: bandName,
      },
      tokens: tokens,
    };
 
    const response = await admin.messaging().sendEachForMulticast(message);
 
    console.log(
      `Fall alert sent: ${response.successCount}/${tokens.length} succeeded`
    );
 
    response.responses.forEach((res, i) => {
      if (!res.success) {
        console.log(`Failed for token ${tokens[i]}: ${res.error}`);
      }
    });
  }
);
 


