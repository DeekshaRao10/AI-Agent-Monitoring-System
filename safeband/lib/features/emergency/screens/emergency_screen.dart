import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/local_avatar.dart';
import '../../../core/services/wearer_resolver.dart';
import '../../../services/notification_service.dart';

const String _rtdbUrl =
    'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app';

/// Full-screen emergency alert, shown when AlertListener detects
/// fallDetected == true while the app is open.
///
/// [bandId] is the ESP32's deviceId (matches both the Realtime Database
/// path and the "deviceId" field on the Firestore "bands" doc).
/// [alertData] is the live Realtime Database snapshot (heartRate, spo2,
/// fallDetected, status) at the moment the alert fired.
class EmergencyScreen extends StatefulWidget {
  final String bandId;
  final Map<String, dynamic> alertData;

  const EmergencyScreen({
    super.key,
    required this.bandId,
    required this.alertData,
  });

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;

  // Static profile info — lives in Firestore's "bands" collection, not in
  // the Realtime Database, so it has to be fetched separately from the
  // live vitals.
  String _wearerName = "Unknown";
  String _bandName = "SafeBand";
  String _address = "Address not set";
  String _bloodGroup = "--";
  String _medicalConditions = "--";
  String _doctorPhone = "";

  // Profile photos are stored entirely on-device (LocalPhotoStore), not
  // in Firestore — there never was a real "photoUrl" field to read, so
  // the old NetworkImage(_photoUrl) here could never actually show
  // anything. This is the wearer's uid, used as the LocalAvatar lookup
  // key instead.
  String _wearerUid = "";

  // The "I'm OK" / "ALERT NOW" actions only make sense on the wearer's
  // own phone — a family member viewing this screen remotely shouldn't
  // be able to dismiss someone else's fall alert or blast an SMS "from"
  // them. Read-only for everyone else; compared once _wearerUid resolves.
  bool _isWearer = false;

  int _caregiverCount = 0;
  bool _cancelling = false;

  // Real phone numbers of caregivers (families/{familyId}/members.phone),
  // collected alongside the caregiver count below — used by "ALERT NOW"
  // to open a real SMS pre-filled to everyone, instead of a fake button.
  final List<String> _caregiverPhones = [];

  // Real, live vitals — seeded from the RTDB snapshot that triggered this
  // screen (widget.alertData), then kept up to date by the same RTDB
  // listener that already watches this band for recovery below. Replaces
  // the old "Band buzzer is sounding" pill, which was static text with no
  // hardware behind it.
  int? _heartRate;
  int? _spo2;

  final String _detectedAt = DateFormat('h:mm a').format(DateTime.now());

  // Guards against navigating away twice — both the manual "I'm OK"
  // button and the automatic RTDB listener below can each try to send
  // us back to Home Dashboard, so whichever happens first wins and the
  // other becomes a no-op.
  bool _hasNavigatedAway = false;

  StreamSubscription<DatabaseEvent>? _statusSub;

  final AudioPlayer _sirenPlayer = AudioPlayer();
  Timer? _vibrationTimer;

  // Volume buttons never reach Flutter on Android by default — MainActivity
  // intercepts them natively (only while this channel has told it to) and
  // relays a "pressed" call back over this same channel, so a volume press
  // can silence the alert without closing the screen — the same gesture
  // phones already use to silence an incoming call or alarm.
  static const MethodChannel _volumeChannel =
      MethodChannel('com.example.safeband/volume_silence');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKeyPressed') {
        _stopAlarm();
        _stopVibration();
      }
    });
    _volumeChannel.invokeMethod('setVolumeInterceptionEnabled', true);

    // Seed with whatever vitals came in on the snapshot that triggered
    // this screen, so something real shows immediately before the RTDB
    // listener below has ticked even once.
    _heartRate = (widget.alertData['heartRate'] as num?)?.toInt();
    _spo2 = (widget.alertData['spo2'] as num?)?.toInt();

    // The notification that (probably) got us here is still posted and
    // still insistently repeating its own siren/vibration — cancel it now
    // rather than at _goHome() time, or its native sound and this
    // screen's own _playAlarm() loop below overlap audibly for a moment
    // (heard as "some other sound also coming" alongside the real siren).
    cancelFallAlertNotification(widget.bandId);

    _loadBandAndFamilyInfo();
    _listenForRecovery();
    _playAlarm();
    _startVibration();
  }

  // Popping this screen (the wearer's "I'm OK", or the RTDB recovery
  // listener below) already stops the siren/vibration via _goHome(). This
  // covers the other way someone leaves it: a family member — who has no
  // "I'm OK" button, since they didn't fall — pressing Home to background
  // the whole app instead. That doesn't pop the route or call dispose(),
  // so without this the siren/vibration would keep running invisibly,
  // felt but with nothing on screen to explain or stop it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAlarm();
      _stopVibration();
      // Otherwise MainActivity keeps hijacking volume keys system-wide
      // (for every other app too) even after this screen is no longer
      // the thing actually visible.
      _volumeChannel.invokeMethod('setVolumeInterceptionEnabled', false);
    }
  }

  // Loops the bundled siren (assets/audio/emergency_siren.mp3, CC0-licensed
  // from freesound.org) through Android's ALARM usage/audio stream — the
  // same category a real alarm clock uses, so it's heard even with media
  // volume down, in silent mode, or under Do Not Disturb. gainTransient
  // focus means it takes over from anything else playing (music, a call
  // prompt) for as long as this screen is up, then hands focus back.
  Future<void> _playAlarm() async {
    try {
      await _sirenPlayer.setReleaseMode(ReleaseMode.loop);
      // isSpeakerphoneOn is deliberately left out — that flag is for apps
      // replacing the platform's own call-audio routing (VoIP/telephony),
      // not a plain alarm loop, and setting it here was silencing playback
      // entirely rather than just controlling volume/routing as intended.
      await _sirenPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));
      await _sirenPlayer.setVolume(1.0);
      await _sirenPlayer.play(AssetSource('audio/emergency_siren.mp3'));
    } catch (e) {
      debugPrint("EmergencyScreen: failed to play alarm sound: $e");
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await _sirenPlayer.stop();
    } catch (e) {
      debugPrint("EmergencyScreen: failed to stop alarm sound: $e");
    }
  }

  // Pulses continuously (1s on, 0.5s off) for as long as the screen is up
  // — the same urgency cue as the siren, for a phone that's face-down,
  // in a pocket, or belongs to someone hard of hearing. Skipped entirely
  // on hardware with no vibration motor rather than throwing.
  //
  // Deliberately NOT using Vibration.vibrate(pattern:, repeat:) for the
  // looping itself — native pattern-repeat support is inconsistent across
  // OEM Android skins, and on this project's own test hardware (a Vivo
  // phone) it only fired once instead of continuing. Driving the repeat
  // from a plain Dart Timer, the same way the siren's own loop is done
  // explicitly rather than trusted to a native flag, works everywhere.
  void _startVibration() async {
    if (!await Vibration.hasVibrator()) return;
    if (_vibrationTimer != null) return; // already running

    Future<void> pulse() async {
      try {
        await Vibration.vibrate(duration: 1000);
      } catch (e) {
        debugPrint("EmergencyScreen: vibration pulse failed: $e");
      }
    }

    pulse();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => pulse());
  }

  void _stopVibration() {
    print("EmergencyScreen: _stopVibration called, timer was "
        "${_vibrationTimer != null ? 'running' : 'already null'}");
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    Vibration.cancel().then((_) {
      print("EmergencyScreen: Vibration.cancel() completed");
    }).catchError((e) {
      print("EmergencyScreen: Vibration.cancel() failed: $e");
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _volumeChannel.invokeMethod('setVolumeInterceptionEnabled', false);
    _volumeChannel.setMethodCallHandler(null);
    _statusSub?.cancel();
    _stopAlarm();
    _sirenPlayer.dispose();
    _stopVibration();
    super.dispose();
  }

  /// Watches bands/{bandId} in RTDB the whole time this screen is open.
  /// If fallDetected flips back to false for ANY reason — the band's
  /// own auto-clear timeout (see main.cpp's 30s emergencyStartTime
  /// check), another caregiver cancelling it from their phone, or this
  /// device's own "I'm OK" button — this screen automatically closes
  /// itself and returns to Home Dashboard, instead of sitting there
  /// showing a stale alert.
  void _listenForRecovery() {
    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _rtdbUrl,
    ).ref('bands/${widget.bandId}');

    _statusSub = ref.onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is! Map) return;

      final data = Map<String, dynamic>.from(value);
      final fallDetected = data['fallDetected'] == true;

      if (mounted) {
        setState(() {
          _heartRate = (data['heartRate'] as num?)?.toInt() ?? _heartRate;
          _spo2 = (data['spo2'] as num?)?.toInt() ?? _spo2;
        });
      }

      if (!fallDetected) {
        _goHome();
      }
    });
  }

  /// Opens the phone's native SMS app with every caregiver's real phone
  /// number pre-filled as recipients and an emergency message drafted —
  /// this device's OWNER still has to hit send (Android/iOS don't allow
  /// apps to silently send SMS without the user confirming), but it's a
  /// real, one-tap-to-nearly-done action, not a fake button.
  Future<void> _sendEmergencySms() async {
    if (_caregiverPhones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No caregiver phone numbers on file"),
          ),
        );
      }
      return;
    }

    final message = "EMERGENCY: $_wearerName has fallen and needs help. "
        "Location: $_address. Detected at $_detectedAt.";

    final uri = Uri(
      scheme: 'sms',
      path: _caregiverPhones.join(','),
      queryParameters: {'body': message},
    );

    try {
      final launched = await launchUrl(uri);

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open messages app")),
        );
      }
    } catch (e) {
      debugPrint("EmergencyScreen: failed to launch SMS: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open messages app")),
        );
      }
    }
  }

  /// Opens the phone's dialer with the doctor's number pre-filled via a
  /// real tel: intent — tapping the pill actually starts a call instead
  /// of just displaying the number.
  Future<void> _callDoctor() async {
    if (_doctorPhone.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: _doctorPhone);

    try {
      final launched = await launchUrl(uri);

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the dialer")),
        );
      }
    } catch (e) {
      debugPrint("EmergencyScreen: failed to launch dialer: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the dialer")),
        );
      }
    }
  }

  /// Writes a cancel signal to bands/{bandId}/cancelRequested in RTDB.
  /// The ESP32 polls this path every ~5s while an emergency is active
  /// (see checkAndClearCancelRequest() in firebase_manager.cpp) and, on
  /// seeing it true, clears its OWN fallDetected/status and resets the
  /// flag back to false. Once the band clears it in RTDB, Dashboard,
  /// Family Management and Band Detail all update automatically since
  /// they already read fallDetected/status live from this same node.
  Future<void> _cancelAlert() async {
    setState(() => _cancelling = true);

    try {
      final bandRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _rtdbUrl,
      ).ref('bands/${widget.bandId}');

      // Two writes:
      // 1. cancelRequested: true — the band itself polls this and, once
      //    it notices, clears its OWN fallDetected/status and resets its
      //    vitals to a resting baseline (see checkAndClearCancelRequest()
      //    in firebase_manager.cpp). This is the real, durable fix — the
      //    band won't re-assert EMERGENCY on its next upload.
      // 2. fallDetected/status optimistically set to false/NORMAL right
      //    now, on the same node every screen already reads live from —
      //    so Dashboard/Family/Band Detail all flip to normal instantly
      //    instead of waiting up to ~5s for the band's own next poll
      //    cycle to catch up. The band's own write moments later just
      //    confirms the same state, so there's no lasting conflict.
      await bandRef.update({
        'cancelRequested': true,
        'fallDetected': false,
        'status': 'NORMAL',
      });
    } catch (e) {
      debugPrint("EmergencyScreen: failed to write cancel/normal state: $e");
    }

    // The RTDB write above will also make _listenForRecovery's listener
    // fire almost immediately — _goHome()'s _hasNavigatedAway guard
    // means whichever of these two fires first is the one that actually
    // navigates, the other is a harmless no-op.
    _goHome();
  }

  /// Shared "return to Home Dashboard" used by both the manual cancel
  /// button and the automatic recovery listener.
  void _goHome() {
    if (_hasNavigatedAway) return;
    _hasNavigatedAway = true;

    // Stop immediately rather than waiting for dispose() — that only
    // fires once the pop animation finishes, which would leave the siren
    // (and the vibration) running for a moment after the screen visually
    // starts closing.
    _stopAlarm();
    _stopVibration();

    // The notification itself is FLAG_INSISTENT (see
    // showFallAlertNotification) — it keeps repeating the siren and
    // vibration on its own until explicitly cancelled, independent of
    // this screen. Without this, closing the alert here wouldn't stop
    // that.
    cancelFallAlertNotification(widget.bandId);

    if (!mounted) return;

    // Back to Home Dashboard (the root screen), not just one screen back.
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _loadBandAndFamilyInfo() async {
    try {
      final bandsSnap = await _firestore
          .collection('bands')
          .where('deviceId', isEqualTo: widget.bandId)
          .limit(1)
          .get();

      if (bandsSnap.docs.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final bandDoc = bandsSnap.docs.first;
      final band = bandDoc.data();

      _wearerName = band['wearerName']?.toString() ?? "Unknown";
      _bandName = band['bandName']?.toString() ?? "SafeBand";
      _address = band['address']?.toString() ?? "Address not set";
      _bloodGroup = band['bloodGroup']?.toString() ?? "--";
      _medicalConditions = band['medicalConditions']?.toString() ?? "--";
      _doctorPhone = band['doctorPhone']?.toString() ?? "";

      // Same self-healing lookup used on Dashboard/Family/Band Detail —
      // resolves the real wearer uid even for bands created before the
      // wearerUid field existed.
      _wearerUid = await resolveWearerUid(
        bandId: bandDoc.id,
        rawWearerUid: (band['wearerUid'] ?? '').toString(),
      );

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      _isWearer = currentUid != null &&
          _wearerUid.isNotEmpty &&
          currentUid == _wearerUid;

      final familyId = band['familyId']?.toString();

      if (familyId != null && familyId.isNotEmpty) {
        final membersSnap = await _firestore
            .collection('families')
            .doc(familyId)
            .collection('members')
            .get();

        // Real count of people who'd actually get notified, not just
        // "everyone in the family": excludes the wearer themselves
        // (they don't need to be alerted about their own fall), skips
        // anyone who's turned notifications off for this family (same
        // toggle Settings and Family Management control), and only
        // counts members who actually have a saved FCM push token —
        // i.e. someone notification_service.dart could really reach.
        int realCaregiverCount = 0;

        for (final memberDoc in membersSnap.docs) {
          final memberData = memberDoc.data();

          final isWearer = memberData['role'] == 'Wearer';
          final notificationsEnabled =
              memberData['notificationsEnabled'] ?? true;

          if (isWearer || notificationsEnabled != true) continue;

          final userDoc =
              await _firestore.collection('users').doc(memberDoc.id).get();

          final fcmToken = userDoc.data()?['fcmToken']?.toString() ?? '';

          if (fcmToken.isNotEmpty) {
            realCaregiverCount++;
          }

          final phone = memberData['phone']?.toString() ?? '';
          if (phone.isNotEmpty) {
            _caregiverPhones.add(phone);
          }
        }

        _caregiverCount = realCaregiverCount;
      }
    } catch (e) {
      debugPrint("EmergencyScreen: failed to load band/family info: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here on purpose — a Material AppBar renders as its own
    // separate surface/bar segment even when its color matches the body,
    // which is exactly the "not truly full screen" gap being reported.
    // Everything (status bar area included) is one single red Container
    // now, with the "Fall Alert" title just as a plain Row inside it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // systemNavigationBarColor covers the black strip Android draws
      // for the on-screen nav bar (home/back/recents) — that's the OS's
      // own overlay, not part of this screen's canvas, so it stays
      // black by default unless explicitly told to match here.
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: AppColors.alertCard,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.alertCard,
      ),
      child: Scaffold(
        backgroundColor: AppColors.alertCard,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          // Subtle top-to-bottom gradient instead of one flat red —
          // adds a bit of depth without changing the full-edge-to-edge
          // red look you asked for earlier.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(AppColors.alertCard, Colors.black, 0.12)!,
                AppColors.alertCard,
              ],
            ),
          ),
          child: _loading
              ? const SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.textOnColor),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 26,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.watch, size: 20, color: AppColors.textOnColor),
                            SizedBox(width: 8),
                            Text(
                              "Fall Alert",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.textOnColor,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        _PulsingGlowAvatar(photoKey: _wearerUid),

                    const SizedBox(height: 22),

                    Text(
                      _wearerName.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textOnColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "FALL DETECTED",
                      style: TextStyle(
                        color: AppColors.textOnColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.alertOverlay,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _detectedAt,
                        style: const TextStyle(
                          color: AppColors.textOnColor,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 26),

                    // Real live vitals from the band at this exact
                    // moment — pulled straight from RTDB (see _heartRate/
                    // _spo2, kept live by _listenForRecovery above) —
                    // replacing the old "Band buzzer is sounding" text,
                    // which was static and not backed by any real
                    // hardware.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.alertOverlay,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.favorite,
                              color: AppColors.textOnColor, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _heartRate != null ? "$_heartRate BPM" : "-- BPM",
                            style: const TextStyle(
                              color: AppColors.textOnColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 18),
                          const Icon(Icons.water_drop,
                              color: AppColors.textOnColor, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _spo2 != null ? "$_spo2% SpO2" : "--% SpO2",
                            style: const TextStyle(
                              color: AppColors.textOnColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.textOnColor, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            // "SMS +" dropped — SMS was never actually
                            // implemented (same reason it was removed
                            // from Family Management earlier). This
                            // count is now real: it only includes
                            // caregivers who have notifications turned
                            // on AND an actual push token on file, so
                            // it's genuinely "how many phones this
                            // reached," not just the family's size.
                            _caregiverCount > 0
                                ? "Notifications sent to $_caregiverCount caregiver${_caregiverCount == 1 ? '' : 's'}"
                                : "Notifying caregivers...",
                            style: const TextStyle(
                              color: AppColors.textOnColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: AppColors.alertMutedText, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Location: $_address",
                            style: const TextStyle(
                              color: AppColors.alertMutedText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Emergency info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "EMERGENCY INFO",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
                              color: AppColors.mutedText,
                            ),
                          ),

                          const SizedBox(height: 18),

                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Blood Group",
                                style:
                                    TextStyle(color: AppColors.mutedText),
                              ),
                              Text(
                                _bloodGroup,
                                style: const TextStyle(
                                  color: AppColors.alertCard,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Conditions",
                                style:
                                    TextStyle(color: AppColors.mutedText),
                              ),
                              // While this screen is up, always read
                              // "Emergency" here regardless of the
                              // wearer's actual on-file medical
                              // conditions (e.g. "normal") — a fall is
                              // in progress, so this field should reflect
                              // that urgency, not their baseline health
                              // notes.
                              const Text(
                                "Emergency",
                                style: TextStyle(
                                  color: AppColors.alertCard,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          if (_doctorPhone.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Doctor",
                                  style: TextStyle(
                                      color: AppColors.mutedText),
                                ),
                                // Tap to actually call — real
                                // tel: intent, not just decorative text
                                // + icon like before.
                                Material(
                                  color: AppColors.success.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _callDoctor,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _doctorPhone,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.success,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.phone,
                                              size: 16,
                                              color: AppColors.success),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Wearer-only actions — a family member viewing this
                    // remotely gets the read-only info above and nothing
                    // else; they're not the one who fell, so cancelling
                    // the alert or sending an "I've fallen" SMS as the
                    // wearer wouldn't make sense coming from their phone.
                    if (_isWearer) ...[
                      const SizedBox(height: 30),

                      PrimaryButton(
                        text: _cancelling ? "Cancelling..." : "I'm OK — Cancel",
                        icon: Icons.close,
                        outlined: true,
                        foregroundColor: AppColors.textOnColor,
                        onPressed: _cancelling ? null : _cancelAlert,
                      ),

                      const SizedBox(height: 14),

                      PrimaryButton(
                        text: "ALERT NOW",
                        icon: Icons.campaign,
                        backgroundColor: AppColors.alertButton,
                        // Opens a real SMS pre-filled to every caregiver's
                        // actual phone number on file, with an emergency
                        // message already drafted (wearer name, location,
                        // time) — just needs the user to hit send.
                        onPressed: _sendEmergencySms,
                      ),
                    ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Matches the reference design's soft glowing ring behind the profile
/// photo — a pulsing white halo that expands and fades out on a loop,
/// rather than the plain flat circle avatar sat directly on the red
/// background. Purely decorative (no data dependency), so it's a small
/// self-contained StatefulWidget just for the animation.
class _PulsingGlowAvatar extends StatefulWidget {
  final String photoKey;

  const _PulsingGlowAvatar({required this.photoKey});

  @override
  State<_PulsingGlowAvatar> createState() => _PulsingGlowAvatarState();
}

class _PulsingGlowAvatarState extends State<_PulsingGlowAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const avatarRadius = 42.0;

    return SizedBox(
      width: avatarRadius * 2.8,
      height: avatarRadius * 2.8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Two rings staggered half a cycle apart so a new pulse starts
          // before the previous one has fully faded — a continuous
          // "radar ping" look instead of one ring blinking on and off.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _glowRing(_controller.value, avatarRadius),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _glowRing(
              (_controller.value + 0.5) % 1.0,
              avatarRadius,
            ),
          ),
          LocalAvatar(
            photoKey: widget.photoKey,
            radius: avatarRadius,
            backgroundColor: AppColors.white,
            fallbackIcon: Icons.person,
            iconColor: AppColors.alertCard,
          ),
        ],
      ),
    );
  }

  Widget _glowRing(double t, double avatarRadius) {
    final scale = 1.0 + t * 0.5;
    final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.45;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: avatarRadius * 2,
        height: avatarRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.textOnColor.withOpacity(opacity),
        ),
      ),
    );
  }
}