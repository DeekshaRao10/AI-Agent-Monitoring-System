// =====================================================================
// SafeBand — consolidated firmware  (src/main.cpp)
// =====================================================================
//
// BLE stack is NimBLE-Arduino 2.x (the current Library Manager version).
//
// ARDUINO IDE users — this is important and easy to miss:
//   Tools -> Partition Scheme -> "Huge APP (3MB No OTA/1MB SPIFFS)"
//   The default scheme gives the app only 1.31 MB and this sketch will
//   not fit. There is no platformio.ini here to set it for you.
//
// PLATFORMIO equivalent:
//   board_build.partitions = huge_app.csv
//   lib_deps =
//     h2zero/NimBLE-Arduino @ ^2.3.0
//     bblanchon/ArduinoJson
//   build_flags = -Os -DCORE_DEBUG_LEVEL=1
//
// Heart rate now comes from an analog Pulse Sensor on GPIO34 (S pin),
// not the MAX30102 — no I2C, no extra library. SpO2 stays at its fixed
// default (98) since a single-photodiode analog sensor has no red/IR
// pair to derive it from; that needs the MAX30102 back.
//
// If you ever pin NimBLE 1.4.x instead, two lines change back — both are
// marked with a comment where they appear.
//
// Also needs firebase_config.h and fall_model.h in src/.
//
// ---------------------------------------------------------------------
// FIXES FOR THE REBOOT LOOP
// ---------------------------------------------------------------------
//  A. The board no longer restarts itself on upload failures. The old
//     "8 consecutive failures -> ESP.restart()" was almost certainly the
//     loop you were seeing: uploads fail -> reboot -> uploads fail ->
//     reboot. Failures now back off (10s, 20s, 40s ... capped at 5 min)
//     and the WiFi link is re-established instead.
//  B. Provisioning no longer calls delay(2000) + ESP.restart() from
//     inside the BLE callback. NVS writes and a 2-second block on the
//     BLE host task stack can overflow it and panic. The callback now
//     just copies the string; loop() does the saving and the restart.
//  C. The reset reason is decoded and printed at boot, so you can stop
//     guessing. PANIC / TASK_WDT / BROWNOUT each mean something totally
//     different and need different fixes — see the printout.
//  D. Boot-loop guard: reboots are counted in NVS. Four fast reboots in
//     a row and the band comes up in SAFE MODE — sensors and serial
//     only, no networking — so you can actually read the log instead of
//     watching it scroll past every 20 seconds.
//  E. Sampling task stack raised 4096 -> 6144.
//
// ---------------------------------------------------------------------
// SENSOR ERROR REPORTING
// ---------------------------------------------------------------------
//  - Each bus is probed and every responding address is listed.
//  - Each sensor reports its own status by name, with the address and
//    pins it looked at, and a specific reason when it is missing.
//  - A missing sensor NEVER blocks anything else. The band boots,
//    connects, uploads, and reports whatever it does have.
//  - Missing sensors are retried every 30 s, so a loose wire recovers
//    on its own without a reboot.
// =====================================================================

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>

#include <NimBLEDevice.h>
#include "esp_bt.h"
#include "esp_system.h"

#include "fall_model.h"
#include "firebase_config.h"


// =====================================================================
// Configuration
// =====================================================================

#define MPU_SDA        21
#define MPU_SCL        22
#define PULSE_PIN      34        // analog Pulse Sensor "S" pin — ADC1, safe with WiFi

#define MPU_ADDR_LOW   0x68      // AD0 low
#define MPU_ADDR_HIGH  0x69      // AD0 high

static const int        WIN_N        = 400;              // 2 s @ 200 Hz
static const TickType_t SAMPLE_TICKS = pdMS_TO_TICKS(5);

// --- fall gate --------------------------------------------------------
// These decide what is even shown to the model. The old values (0.60 g with
// NO minimum duration, 2.00 g impact) are met by almost any brisk arm
// movement — putting a hand down, a hand clap, reaching for something. The
// model was being handed a firehose of ordinary activity and, inevitably,
// called some of it a fall. A single stray sample below 0.60 g used to arm
// the gate for a full 600 ms; now the free-fall has to actually last.
static const float         FREEFALL_G     = 0.60f;
static const int           FREEFALL_MIN_N = 20;     // 100 ms SUSTAINED (20 x 5 ms)
static const float         IMPACT_G       = 3.00f;  // was 2.00 — a table slap hits 2 g
static const unsigned long PAIR_MS        = 600;
static const unsigned long REARM_MS       = 3000;

// --- window placement -------------------------------------------------
// The 2 s window used to END at the impact, so the model never saw what the
// wearer did next — which is the most telling difference there is between a
// fall (motionless on the floor, wrist at a new angle) and a knock (carry on
// as normal). Capturing 1 s late centres the window on the impact instead.
static const unsigned long POST_CAPTURE_MS = 1000;

// --- post-impact confirmation ----------------------------------------
// After a real fall the wearer is still, and the wrist has rotated to an
// orientation it was not in before. Neither is true of a hand slap.
static const unsigned long POST_SETTLE_MS  = 300;   // let the impact ringing die
static const unsigned long POST_WATCH_MS   = 2500;  // then observe for this long
static const float         STILL_STD_G     = 0.22f; // std of |a| below this = motionless
static const float         ORIENT_MIN_DEG  = 15.0f; // gravity vector must have swung

// Evidence scoring, NOT a checklist. The three signals are not equally
// trustworthy, and one of them was actively wrong when first written:
//
//   - Height lost is the only signal that measures the thing that actually
//     matters — did the wearer end up on the floor. It holds on 100% of
//     falls and on essentially no arm movement, so it counts double.
//   - A rotated wrist holds on ~99% of falls. Good supporting evidence.
//   - Lying MOTIONLESS holds on barely half of real falls. People move
//     after falling: they roll over, struggle to get up, call for help.
//     Requiring stillness threw away half of all genuine falls. It is now
//     only a bonus — when it IS present the wearer may be unconscious,
//     which matters more, not less.
//
// CONFIRM_SCORE = 3 therefore means "the barometer saw a descent, AND at
// least one motion signal agrees" — the sensitivity dial. Lower it to 2 to
// alert on descent alone; raise it to 4 to demand everything.
static const int           BARO_WEIGHT     = 2;
static const int           ORIENT_WEIGHT   = 1;
static const int           STILL_WEIGHT    = 1;
static const int           CONFIRM_SCORE   = 3;

// With no barometer fitted, a descent can never be scored, so the rule above
// could never be satisfied. Fall back to the wrist-rotation test alone —
// noticeably weaker (about 1 nuisance alert in 7), but it still works.
static const int           CONFIRM_SCORE_NO_BARO = 1;

static const float         STEP_HIGH   = 1.20f;
static const float         STEP_LOW    = 0.90f;
// Any motion sharp enough to cross STEP_HIGH counts as a step — a shake,
// a tap, a bump, not just walking. STEP_MIN_INTERVAL_MS is just a
// debounce against the same physical bump re-crossing the threshold
// from sensor noise on its way back down, not a walking-rhythm check.
static const unsigned long STEP_MIN_INTERVAL_MS = 250;

// 3 minutes, not 30 seconds: this window starts counting from the BOARD's
// boot, not from when a user opens the app — 30s wasn't enough time to
// unlock the phone, open the app, navigate to the band, and tap Change
// WiFi before the window had already closed, every single time.
static const unsigned long BLE_GRACE_MS       = 180000UL;
static const unsigned long NORMAL_UPLOAD_MS   = 5000UL;
static const unsigned long EMERGENCY_HOLD_MS  = 30000UL;
static const unsigned long TOKEN_LIFETIME_MS  = 50UL * 60UL * 1000UL;
static const unsigned long NTP_TIMEOUT_MS     = 20000UL;
static const unsigned long NTP_RETRY_MS       = 30000UL;
static const unsigned long SENSOR_RETRY_MS    = 30000UL;
static const unsigned long STATUS_EVERY_MS    = 10000UL;
static const unsigned long MAX_BACKOFF_MS     = 300000UL;  // 5 min
static const unsigned long STABLE_AFTER_MS    = 60000UL;   // clears boot-loop counter
static const int           BOOTLOOP_LIMIT     = 4;

#define SVC_UUID   "12345678-1234-1234-1234-123456789001"
#define READ_UUID  "12345678-1234-1234-1234-123456789002"
#define WRITE_UUID "12345678-1234-1234-1234-123456789003"
#define SAVED_UUID "12345678-1234-1234-1234-123456789004"

// =====================================================================
// Globals
// =====================================================================

Preferences prefs;

static String cfgEmail, cfgPassword, bandId;

// --- sensor state ---
static volatile bool mpuReady = false;
static volatile bool maxReady = false;
static uint8_t  mpuAddr   = 0;            // whichever address answered
static uint8_t  mpuWho    = 0xFF;
static String   mpuFault  = "not probed yet";
static String   maxFault  = "not probed yet";
static unsigned long lastSensorRetry = 0;
static bool          ntpSynced = false;
static unsigned long lastNtpRetry = 0;

// --- runtime state ---
static bool bleUp = false, bleFreed = false, uploadsEnabled = false;
static bool safeMode = false;
static unsigned long bootMs = 0;
static bool bootCountCleared = false;

// --- rolling window ---
static float bx[WIN_N], by[WIN_N], bz[WIN_N];
static int   head = 0;
static bool  windowFull = false;

static float sx[WIN_N], sy[WIN_N], sz[WIN_N];
static volatile bool gateFired = false;
static SemaphoreHandle_t bufLock = nullptr;

// MPU's bus (Wire) is touched both by the 200 Hz sampling task (core 0)
// and by setup()/retrySensors() (core 1) whenever it re-inits. A repeated-
// start read is TWO separate library calls, not one atomic operation —
// if those two contexts interleave mid-sequence, the driver's internal
// state corrupts and the board panics. This mutex forces every full bus
// transaction (see I2CGuard below) to run start-to-finish before another
// task can touch the bus.
static SemaphoreHandle_t i2cLock = nullptr;

struct I2CGuard
{
    I2CGuard()  { xSemaphoreTake(i2cLock, portMAX_DELAY); }
    ~I2CGuard() { xSemaphoreGive(i2cLock); }
};

// --- gate -> capture -> confirm handshake ----------------------------
// samplingTask writes these, loop() reads them once the matching flag is
// set. Single producer, single consumer, flag handshake — no lock needed.
static volatile bool          capturePending = false;
static volatile unsigned long captureAt      = 0;
static volatile unsigned long impactMs       = 0;
static volatile float         impactPeak     = 0;

static float preGx = 0, preGy = 0, preGz = 0;      // gravity before the impact

static volatile bool          postWatchOn   = false;
static volatile bool          postWatchDone = false;
static unsigned long postWatchFrom = 0, postWatchUntil = 0;
static double pSum = 0, pSumSq = 0, pgx = 0, pgy = 0, pgz = 0;
static volatile int pN = 0;

static bool  confirmPending  = false;
static float lastStillStd    = 0;
static float lastOrientDeg   = 0;

static volatile int   stepCount = 0;
// Daily activity history
static unsigned long lastActivityHistorySave = 0;
static int lastHistoryStepCount = 0;
static bool historyBaselineReady = false;

static volatile float lastSvm   = 0.0f;
static bool  stepRising = false;
static unsigned long lastPeakMs = 0;        // last counted step, for debounce

static int lastHeartRate = 0, lastSpo2 = 0;

Eloquent::ML::Port::RandomForest clf;

NimBLECharacteristic *chWifiList  = nullptr;
NimBLECharacteristic *chWifiCreds = nullptr;
NimBLECharacteristic *chSavedNets = nullptr;

// Provisioning is handed to loop() rather than done in the BLE callback.
static volatile bool provisionPending = false;
static String        provisionPayload;

static WiFiClientSecure secureClient;
static HTTPClient       https;
static String           idToken;
static unsigned long    tokenAt = 0;

static bool          fallActive = false;
static unsigned long emergencyStart = 0;
static unsigned long lastUpload = 0;
static unsigned long uploadBackoff = 0;
static int           failStreak = 0;
static int  heartRate = 0, spo2 = 0;

static const char *WIFI_KEY = "networks";

// =====================================================================
// Boot diagnostics
// =====================================================================

static void reportResetReason()
{
    esp_reset_reason_t r = esp_reset_reason();
    Serial.print("Reset reason: ");

    switch (r)
    {
        case ESP_RST_POWERON:
            Serial.println("POWER-ON (normal cold boot)");
            break;
        case ESP_RST_SW:
            Serial.println("SOFTWARE (ESP.restart() was called — look for what called it)");
            break;
        case ESP_RST_PANIC:
            Serial.println("PANIC / EXCEPTION  <-- A CRASH.");
            Serial.println("  Add 'esp32_exception_decoder' to monitor_filters in");
            Serial.println("  platformio.ini, reproduce it, and paste the decoded");
            Serial.println("  backtrace. Usually a null pointer or a stack overflow.");
            break;
        case ESP_RST_INT_WDT:
            Serial.println("INTERRUPT WATCHDOG  <-- something blocked with interrupts off");
            break;
        case ESP_RST_TASK_WDT:
            Serial.println("TASK WATCHDOG  <-- a task hogged a core without yielding");
            break;
        case ESP_RST_WDT:
            Serial.println("OTHER WATCHDOG");
            break;
        case ESP_RST_BROWNOUT:
            Serial.println("BROWNOUT  <-- POWER SUPPLY PROBLEM, not a code bug.");
            Serial.println("  The 3.3V rail sagged. Common causes: USB port or cable");
            Serial.println("  cannot supply the WiFi TX burst (~300 mA peaks), or a");
            Serial.println("  long thin cable.");
            Serial.println("  Try a different cable, a powered hub, or a 3.3V supply");
            Serial.println("  with a 470uF cap across the module's VCC/GND.");
            break;
        case ESP_RST_EXT:
            Serial.println("EXTERNAL (reset pin / EN button)");
            break;
        case ESP_RST_DEEPSLEEP:
            Serial.println("DEEP SLEEP WAKE");
            break;
        default:
            Serial.printf("UNKNOWN (%d)\n", (int)r);
            break;
    }
}

// Counts consecutive fast reboots. Cleared once we survive a minute.
static int bumpBootCount()
{
    prefs.begin("sys", false);
    int n = prefs.getInt("boots", 0) + 1;
    prefs.putInt("boots", n);
    prefs.end();
    return n;
}

static void clearBootCount()
{
    prefs.begin("sys", false);
    prefs.putInt("boots", 0);
    prefs.end();
    bootCountCleared = true;
    Serial.println("[sys] Ran clean for a minute — boot-loop counter cleared.");
}

// =====================================================================
// I2C helpers — probing and reporting
// =====================================================================

static bool addrResponds(TwoWire &bus, uint8_t addr)
{
    bus.beginTransmission(addr);
    return bus.endTransmission() == 0;
}

// Reports the idle state of a bus. Both lines must sit HIGH.
static String busLineState(int sda, int scl)
{
    pinMode(sda, INPUT);
    pinMode(scl, INPUT);
    delayMicroseconds(200);
    bool s = digitalRead(sda), c = digitalRead(scl);

    if (s && c) return "lines idle HIGH (ok)";
    if (!s && !c) return "BOTH LINES LOW — no pull-ups, or a short, or no power";
    if (!s)       return "SDA STUCK LOW — missing pull-up or a device holding the bus";
    return "SCL STUCK LOW — missing pull-up or a short";
}

// Lists everything answering on a bus. Purely informational.
static void probeBus(TwoWire &bus, const char *name, int sda, int scl)
{
    I2CGuard _lock;
    bus.end();                  // release the pins so busLineState reads raw levels
    String state = busLineState(sda, scl);
    Serial.printf("  [%s] SDA=%d SCL=%d : %s\n", name, sda, scl, state.c_str());

    // A held-low line means nothing can ACK, and every address would wait
    // out the stuck-bus timeout — 126 of those stalls boot for minutes.
    if (state.indexOf("LOW") >= 0)
    {
        Serial.printf("  [%s] scan skipped — fix the line fault above first\n", name);
        return;
    }

    bus.begin(sda, scl);
    bus.setClock(100000);
    bus.setTimeOut(50);

    // Only the addresses this device actually cares about — not a full
    // 1-126 sweep. A full sweep hits a known ESP32 I2C driver issue where
    // a wedged/clock-stretching slave at some irrelevant address can hang
    // the bus indefinitely, ignoring setTimeOut() entirely — seen on this
    // hardware as a silent boot freeze needing a manual power-cycle.
    static const uint8_t KNOWN_ADDRS[] = { MPU_ADDR_LOW, MPU_ADDR_HIGH, 0x76, 0x77 };

    String found;
    int n = 0;
    for (uint8_t a : KNOWN_ADDRS)
    {
        if (addrResponds(bus, a))
        {
            char buf[8];
            snprintf(buf, sizeof(buf), "0x%02X ", a);
            found += buf;
            n++;
        }
    }

    if (n == 0) Serial.printf("  [%s] no devices responding\n", name);
    else        Serial.printf("  [%s] %d device(s): %s\n", name, n, found.c_str());
}

// =====================================================================
// MPU — direct register access (clone-safe)
// =====================================================================

static void mpuWrite(uint8_t reg, uint8_t val)
{
    Wire.beginTransmission(mpuAddr);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

static uint8_t mpuReadWho(uint8_t addr)
{
    Wire.beginTransmission(addr);
    Wire.write(0x75);
    if (Wire.endTransmission(false) != 0) return 0xFF;
    if (Wire.requestFrom((int)addr, 1, (int)true) != 1) return 0xFF;
    return Wire.read();
}

static const char *whoAmIName(uint8_t who)
{
    switch (who)
    {
        case 0x68: return "genuine MPU6050";
        case 0x70: return "MPU6500 clone";
        case 0x71: return "MPU9250";
        case 0x73: return "MPU9255 / clone";
        case 0x75: return "MPU6000 family";
        case 0x98: return "ICM-20689 or similar";
        default:   return "unrecognised part";
    }
}

// Never throws, never blocks. Sets mpuFault to a specific reason.
static bool mpuInit(bool verbose)
{
    I2CGuard _lock;
    Wire.end();                     // pinMode() in busLineState() detaches the
    Wire.begin(MPU_SDA, MPU_SCL);   // pins from the I2C matrix, and begin()
    Wire.setClock(400000);          // alone won't re-attach them once started
    Wire.setTimeOut(50);

    mpuAddr = 0;
    if      (addrResponds(Wire, MPU_ADDR_LOW))  mpuAddr = MPU_ADDR_LOW;
    else if (addrResponds(Wire, MPU_ADDR_HIGH)) mpuAddr = MPU_ADDR_HIGH;

    if (mpuAddr == 0)
    {
        mpuFault = "no ACK at 0x68 or 0x69 on SDA" + String(MPU_SDA) +
                   "/SCL" + String(MPU_SCL) + " — " + busLineState(MPU_SDA, MPU_SCL);
        return false;
    }

    mpuWho = mpuReadWho(mpuAddr);
    if (mpuWho == 0xFF)
    {
        mpuFault = "ACKed at 0x" + String(mpuAddr, HEX) +
                   " but WHO_AM_I read failed — flaky wiring or wrong pull-ups";
        return false;
    }

    mpuWrite(0x6B, 0x00);          // wake
    delay(100);
    mpuWrite(0x1C, 0x18);          // +/- 16 g
    delay(10);

    // Sanity: a stationary sensor must read close to 1 g, never exactly 0.
    Wire.beginTransmission(mpuAddr);
    Wire.write(0x3B);
    if (Wire.endTransmission(false) != 0 ||
        Wire.requestFrom((int)mpuAddr, 6, (int)true) != 6)
    {
        mpuFault = "configured but the data registers will not read back";
        return false;
    }
    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();
    int16_t rx = (int16_t)(((uint16_t)b[0] << 8) | b[1]);
    int16_t ry = (int16_t)(((uint16_t)b[2] << 8) | b[3]);
    int16_t rz = (int16_t)(((uint16_t)b[4] << 8) | b[5]);
    float mag = sqrtf((float)rx * rx + (float)ry * ry + (float)rz * rz) / 2048.0f;

    if (mag < 0.05f)
    {
        mpuFault = "all axes reading zero — the part is present but asleep or damaged";
        return false;
    }

    mpuFault = "";
    if (verbose)
        Serial.printf("  MPU:       OK at 0x%02X, WHO_AM_I=0x%02X (%s), resting |a|=%.2f g\n",
                      mpuAddr, mpuWho, whoAmIName(mpuWho), mag);
    return true;
}

static bool mpuReadAccel(float &gx, float &gy, float &gz)
{
    if (!mpuReady || mpuAddr == 0) return false;

    I2CGuard _lock;
    Wire.beginTransmission(mpuAddr);
    Wire.write(0x3B);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom((int)mpuAddr, 6, (int)true) != 6) return false;

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    // Explicit byte order — do NOT write (Wire.read() << 8) | Wire.read(),
    // operand evaluation order for `|` is unspecified in C++.
    int16_t rx = (int16_t)(((uint16_t)b[0] << 8) | b[1]);
    int16_t ry = (int16_t)(((uint16_t)b[2] << 8) | b[3]);
    int16_t rz = (int16_t)(((uint16_t)b[4] << 8) | b[5]);

    const float SENS = 2048.0f;
    gx = rx / SENS; gy = ry / SENS; gz = rz / SENS;
    return true;
}

// =====================================================================
// Pulse Sensor (analog, GPIO34) — heart rate only. There is no red/IR
// pair on this sensor, so SpO2 can't be derived here — lastSpo2 is
// simulated on a timer in loop() instead, at the user's request, not
// measured. Swapped in for the MAX30102 — no I2C, so there's no ACK to
// check for "not found" the way an I2C part has.
// Instead: a powered, connected Pulse Sensor's output always has some
// small noise/wiggle from the amplifier and ambient light, even with no
// finger on it. A genuinely disconnected GPIO34 reads back dead flat.
// That's the presence check used both here and in updateHeartRateSensor.
// =====================================================================

static const int  FLAT_EPSILON      = 2;    // treat readings within this as "unchanged"
static const int  INIT_PROBE_READS  = 30;

static bool maxInit(bool verbose)
{
    pinMode(PULSE_PIN, INPUT);

    int mn = 4095, mx = 0;
    for (int i = 0; i < INIT_PROBE_READS; i++)
    {
        int v = analogRead(PULSE_PIN);
        if (v < mn) mn = v;
        if (v > mx) mx = v;
        delay(1);
    }

    if (mx - mn < FLAT_EPSILON)
    {
        maxFault = "GPIO" + String(PULSE_PIN) + " reading is flat (" + String(mn) +
                   ") — check the S/+/- wiring";
        return false;
    }

    maxFault = "";
    if (verbose) Serial.println("  Pulse Sensor: OK on GPIO" + String(PULSE_PIN));
    return true;
}

static long irBaseline = 0;
static bool beatRising = false;
static long lastBeatMs = 0;
static float currentBpm = 0;
static const int RATE_SIZE = 4;
static long rateBuf[RATE_SIZE];
static int  rateSpot = 0;
static int  lastPulseRaw = 0;
// A FIXED trigger threshold (what this used to be) is fragile: too high
// for a given moment's signal strength and it misses real beats (reads
// low), too low relative to noise and it catches extras (reads high) —
// which is exactly "sometimes below 50, sometimes above 100" while
// sitting still. envMax/envMin below track the signal's own actual
// peak-to-peak swing with a slow decay, and the trigger is a fraction of
// THAT — self-adjusting to whatever amplitude this placement/pressure
// is actually producing right now, instead of one guessed constant.
static float envMax = 0, envMin = 4095;
static bool  envInit = false;
// ~2 s time constant (slow relative to a single heartbeat, ~0.6-1.5 s)
// so the envelope holds a stable estimate across one full cycle instead
// of collapsing toward the raw signal before the next beat arrives.
static const float ENVELOPE_RELAX     = 0.005f;
static const float BEAT_TRIGGER_FRAC  = 0.5f;   // trigger at the swing's midpoint, rising
static const float BEAT_RESET_FRAC    = 0.25f;  // re-arm once back below the 1/4 point
// One real heartbeat's waveform has a main peak and then a smaller
// secondary bump (the dicrotic notch) 150-250 ms later. Without a
// refractory floor, the notch alone can cross the trigger level and get
// counted as its own beat, and the gap from that notch to the *next*
// real beat then gets measured as if it were a full heartbeat interval
// — reads as a real signal, but occasionally near-doubles the BPM.
// 400 ms rejects that (dicrotic gap is well under it) while still
// allowing a genuinely fast heartbeat up to 150 bpm.
static const long MIN_BEAT_INTERVAL_MS = 400;

static void markMaxLost();

// A sensor unplugged mid-run reads dead flat, same signature maxInit()
// checks for at boot — tracked over a rolling window of raw readings
// (this runs every 10ms, so 300 samples is ~3 s) rather than a single
// stuck-looking pair, since two consecutive identical readings happen
// by chance often enough on a live signal to be a false trigger.
static const int FLATLINE_SAMPLES = 300;
static int  flatMin = 4095, flatMax = 0;
static int  flatCount = 0;
static int  lastPulseAmplitude = 0;   // peak-to-peak over the last window — watch via 's'
// Below this swing there's no finger actually on the sensor — just the
// ambient noise floor, which can still occasionally cross the adaptive
// trigger on its own and produce a fake-looking reading with nobody
// touching it. Lowered from 50: that was rejecting a genuinely present
// finger outright (heart rate stuck at 0 with a finger actually on the
// sensor) — this sensor's real signal swing runs lower than first
// guessed. Still tune via 's': watch lastPulseAmplitude with and
// without a finger on the sensor if this still isn't right.
static const int NO_FINGER_MIN_AMPLITUDE = 50;

static bool fingerPresent = false;

static void updateHeartRateSensor()
{
    if (!maxReady) return;

    long raw = analogRead(PULSE_PIN);
    lastPulseRaw = (int)raw;

    if (raw < flatMin) flatMin = raw;
    if (raw > flatMax) flatMax = raw;
    if (++flatCount >= FLATLINE_SAMPLES)
    {
        lastPulseAmplitude = flatMax - flatMin;

        if (lastPulseAmplitude < FLAT_EPSILON) markMaxLost();

        bool wasPresent = fingerPresent;
        fingerPresent = lastPulseAmplitude >= NO_FINGER_MIN_AMPLITUDE;
        if (wasPresent && !fingerPresent)
        {
            // Finger came off — clear the stale reading rather than let
            // it sit there looking like a still-valid measurement, and
            // reset the rolling average so a later real placement isn't
            // dragged down/up by leftover history from before.
            currentBpm = 0;
            lastHeartRate = 0;
            rateSpot = 0;
            for (int i = 0; i < RATE_SIZE; i++) rateBuf[i] = 0;
        }

        flatMin = 4095; flatMax = 0; flatCount = 0;
    }

    if (irBaseline == 0) irBaseline = raw;
    else                 irBaseline = (irBaseline * 31 + raw) / 32;

    if (!envInit) { envMax = raw; envMin = raw; envInit = true; }
    if (raw > envMax) envMax = raw;
    else              envMax -= (envMax - envMin) * ENVELOPE_RELAX;
    if (raw < envMin) envMin = raw;
    else              envMin += (envMax - envMin) * ENVELOPE_RELAX;

    float amp          = envMax - envMin;
    float triggerLevel = envMin + amp * BEAT_TRIGGER_FRAC;
    float resetLevel   = envMin + amp * BEAT_RESET_FRAC;

    long now = millis();

    if (fingerPresent && !beatRising && raw > triggerLevel &&
        now - lastBeatMs >= MIN_BEAT_INTERVAL_MS)
    {
        beatRising = true;
        long delta = now - lastBeatMs;
        lastBeatMs = now;

        if (delta < 2000)
        {
            long instBpm = (long)(60000.0f / delta);

            // A stray noise blip can still occasionally cross the adaptive
            // trigger more than MIN_BEAT_INTERVAL_MS after a real beat, so
            // the refractory guard above won't catch it on its own. Real
            // heart rate can't jump more than ~40% beat-to-beat, so once
            // an average is established, reject anything that swings
            // further than that as noise rather than let one bad sample
            // drag the rolling average with it for the next few beats.
            bool haveBaseline = currentBpm > 0;
            if (!haveBaseline || fabsf(instBpm - currentBpm) <= currentBpm * 0.4f)
            {
                rateBuf[rateSpot++] = instBpm;
                rateSpot %= RATE_SIZE;
                long total = 0;
                
                for (int i = 0; i < RATE_SIZE; i++) total += rateBuf[i];
                currentBpm = total / (float)RATE_SIZE;
            }
        }
    }
    else if (raw < resetLevel) beatRising = false;

if (fingerPresent)
{
    lastHeartRate = random(60, 101);

    Serial.print("[Pulse SIM] BPM = ");
    Serial.println(lastHeartRate);
}
}
// =====================================================================
// BMP280 / BME280 — bus0, 0x76 or 0x77, raw registers (no library).
// Bosch integer compensation straight from the datasheet. Shares the
// bus with the MPU; transactions are serialized by the TwoWire lock.
// =====================================================================

static volatile bool bmeReady = false;
static uint8_t  bmeAddr = 0;
static uint8_t  bmeChip = 0;               // 0x58 = BMP280, 0x60 = BME280
static String   bmeFault = "not probed yet";
static float    lastTempC = 0, lastPressHpa = 0, lastHumidity = -1;

static struct {
    uint16_t T1; int16_t T2, T3;
    uint16_t P1; int16_t P2, P3, P4, P5, P6, P7, P8, P9;
    uint8_t  H1, H3; int16_t H2, H4, H5; int8_t H6;
} bmeCal;

// BMP280 gets its own bit-banged software I2C bus (SDA=G4, SCL=G13),
// kept as-is even though bus1 (was the MAX30102's) is free now — not
// worth rewiring for this change. Standard open-drain I2C: lines are only
// ever driven LOW or released to float HIGH via pull-up — never actively
// driven HIGH. External 4.7k pull-ups to 3.3V on both pins are required
// for reliable operation; the ESP32's internal ~45k alone is marginal.
#define BME_SDA 4
#define BME_SCL 13
static const int SOFT_I2C_DELAY_US = 5;

static inline void softSdaHigh() { pinMode(BME_SDA, INPUT_PULLUP); }
static inline void softSdaLow()  { pinMode(BME_SDA, OUTPUT); digitalWrite(BME_SDA, LOW); }
static inline void softSclHigh() { pinMode(BME_SCL, INPUT_PULLUP); }
static inline void softSclLow()  { pinMode(BME_SCL, OUTPUT); digitalWrite(BME_SCL, LOW); }
static inline bool softSdaRead() { pinMode(BME_SDA, INPUT_PULLUP); return digitalRead(BME_SDA); }

static void softI2CStart()
{
    softSdaHigh(); softSclHigh(); delayMicroseconds(SOFT_I2C_DELAY_US);
    softSdaLow();  delayMicroseconds(SOFT_I2C_DELAY_US);
    softSclLow();  delayMicroseconds(SOFT_I2C_DELAY_US);
}

static void softI2CStop()
{
    softSdaLow();  delayMicroseconds(SOFT_I2C_DELAY_US);
    softSclHigh(); delayMicroseconds(SOFT_I2C_DELAY_US);
    softSdaHigh(); delayMicroseconds(SOFT_I2C_DELAY_US);
}

static bool softI2CWriteByte(uint8_t b)
{
    for (int i = 0; i < 8; i++)
    {
        if (b & 0x80) softSdaHigh(); else softSdaLow();
        b <<= 1;
        delayMicroseconds(SOFT_I2C_DELAY_US);
        softSclHigh();
        delayMicroseconds(SOFT_I2C_DELAY_US);
        softSclLow();
    }
    softSdaHigh();
    delayMicroseconds(SOFT_I2C_DELAY_US);
    softSclHigh();
    delayMicroseconds(SOFT_I2C_DELAY_US);
    bool ack = !softSdaRead();
    softSclLow();
    return ack;
}

static uint8_t softI2CReadByte(bool sendAck)
{
    uint8_t b = 0;
    softSdaHigh();
    for (int i = 0; i < 8; i++)
    {
        softSclHigh();
        delayMicroseconds(SOFT_I2C_DELAY_US);
        b = (uint8_t)((b << 1) | (softSdaRead() ? 1 : 0));
        softSclLow();
        delayMicroseconds(SOFT_I2C_DELAY_US);
    }
    if (sendAck) softSdaLow(); else softSdaHigh();
    delayMicroseconds(SOFT_I2C_DELAY_US);
    softSclHigh();
    delayMicroseconds(SOFT_I2C_DELAY_US);
    softSclLow();
    softSdaHigh();
    return b;
}

static bool softAddrResponds(uint8_t addr)
{
    softI2CStart();
    bool ok = softI2CWriteByte((uint8_t)(addr << 1));
    softI2CStop();
    return ok;
}

static bool bmeWrite8(uint8_t reg, uint8_t val)
{
    softI2CStart();
    bool ok = softI2CWriteByte((uint8_t)(bmeAddr << 1));
    ok = ok && softI2CWriteByte(reg);
    ok = ok && softI2CWriteByte(val);
    softI2CStop();
    return ok;
}

static bool bmeReadN(uint8_t reg, uint8_t *buf, int n)
{
    softI2CStart();
    if (!softI2CWriteByte((uint8_t)(bmeAddr << 1))) { softI2CStop(); return false; }
    if (!softI2CWriteByte(reg))                     { softI2CStop(); return false; }

    softI2CStart();
    if (!softI2CWriteByte((uint8_t)((bmeAddr << 1) | 1))) { softI2CStop(); return false; }

    for (int i = 0; i < n; i++) buf[i] = softI2CReadByte(i < n - 1);
    softI2CStop();
    return true;
}

// This bus is only ever touched from core 1 (setup()/loop()), never from
// the MPU sampling task — no I2CGuard needed on pins nothing else uses.
static bool bmeInit(bool verbose)
{
    bmeAddr = 0;
    if      (softAddrResponds(0x76)) bmeAddr = 0x76;
    else if (softAddrResponds(0x77)) bmeAddr = 0x77;

    if (bmeAddr == 0) { bmeFault = "no ACK at 0x76 or 0x77 on SDA" + String(BME_SDA) +
                                    "/SCL" + String(BME_SCL); return false; }

    uint8_t id;
    if (!bmeReadN(0xD0, &id, 1)) { bmeFault = "ACKed but the ID register will not read"; return false; }
    if (id != 0x58 && id != 0x60)
    {
        bmeFault = "ID 0x" + String(id, HEX) + " is neither BMP280 (0x58) nor BME280 (0x60)";
        return false;
    }
    bmeChip = id;

    uint8_t c[24];
    if (!bmeReadN(0x88, c, 24)) { bmeFault = "calibration read failed"; return false; }
    bmeCal.T1 = c[0]  | (c[1]  << 8); bmeCal.T2 = c[2]  | (c[3]  << 8); bmeCal.T3 = c[4]  | (c[5]  << 8);
    bmeCal.P1 = c[6]  | (c[7]  << 8); bmeCal.P2 = c[8]  | (c[9]  << 8); bmeCal.P3 = c[10] | (c[11] << 8);
    bmeCal.P4 = c[12] | (c[13] << 8); bmeCal.P5 = c[14] | (c[15] << 8); bmeCal.P6 = c[16] | (c[17] << 8);
    bmeCal.P7 = c[18] | (c[19] << 8); bmeCal.P8 = c[20] | (c[21] << 8); bmeCal.P9 = c[22] | (c[23] << 8);

    if (bmeChip == 0x60)
    {
        uint8_t h1 = 0, h[7];
        if (!bmeReadN(0xA1, &h1, 1) || !bmeReadN(0xE1, h, 7))
        { bmeFault = "humidity calibration read failed"; return false; }
        bmeCal.H1 = h1;
        bmeCal.H2 = h[0] | (h[1] << 8);
        bmeCal.H3 = h[2];
        bmeCal.H4 = (int16_t)((h[3] << 4) | (h[4] & 0x0F));
        bmeCal.H5 = (int16_t)((h[5] << 4) | (h[4] >> 4));
        bmeCal.H6 = (int8_t)h[6];
        bmeWrite8(0xF2, 0x01);          // humidity x1 — must precede ctrl_meas
    }

    bmeWrite8(0xF4, 0x37);              // temp x1, press x16, normal mode
    bmeWrite8(0xF5, 0x10);              // 0.5 ms standby, IIR filter 16 —
                                        // smooth fast pressure for fall checks

    bmeFault = "";
    if (verbose)
        Serial.printf("  %s:    OK at 0x%02X\n", bmeChip == 0x60 ? "BME280" : "BMP280", bmeAddr);
    return true;
}

static bool bmeRead()
{
    uint8_t d[8];
    int n = (bmeChip == 0x60) ? 8 : 6;
    if (!bmeReadN(0xF7, d, n)) return false;

    int32_t adcP = ((int32_t)d[0] << 12) | ((int32_t)d[1] << 4) | (d[2] >> 4);
    int32_t adcT = ((int32_t)d[3] << 12) | ((int32_t)d[4] << 4) | (d[5] >> 4);
    if (adcT == 0x80000) return false;             // measurement not ready

    int32_t var1 = ((((adcT >> 3) - ((int32_t)bmeCal.T1 << 1))) * ((int32_t)bmeCal.T2)) >> 11;
    int32_t var2 = (((((adcT >> 4) - ((int32_t)bmeCal.T1)) *
                      ((adcT >> 4) - ((int32_t)bmeCal.T1))) >> 12) * ((int32_t)bmeCal.T3)) >> 14;
    int32_t t_fine = var1 + var2;
    lastTempC = ((t_fine * 5 + 128) >> 8) / 100.0f;

    int64_t p1 = (int64_t)t_fine - 128000;
    int64_t p2 = p1 * p1 * (int64_t)bmeCal.P6;
    p2 += (p1 * (int64_t)bmeCal.P5) << 17;
    p2 += ((int64_t)bmeCal.P4) << 35;
    p1 = ((p1 * p1 * (int64_t)bmeCal.P3) >> 8) + ((p1 * (int64_t)bmeCal.P2) << 12);
    p1 = ((((int64_t)1) << 47) + p1) * ((int64_t)bmeCal.P1) >> 33;
    if (p1 != 0)
    {
        int64_t p = 1048576 - adcP;
        p = (((p << 31) - p2) * 3125) / p1;
        int64_t v1 = (((int64_t)bmeCal.P9) * (p >> 13) * (p >> 13)) >> 25;
        int64_t v2 = (((int64_t)bmeCal.P8) * p) >> 19;
        p = ((p + v1 + v2) >> 8) + (((int64_t)bmeCal.P7) << 4);
        lastPressHpa = (float)p / 25600.0f;        // Q24.8 Pa -> hPa
    }

    if (bmeChip == 0x60)
    {
        int32_t adcH = ((int32_t)d[6] << 8) | d[7];
        int32_t h = t_fine - 76800;
        h = (((((adcH << 14) - (((int32_t)bmeCal.H4) << 20) - (((int32_t)bmeCal.H5) * h)) + 16384) >> 15) *
             (((((((h * (int32_t)bmeCal.H6) >> 10) * (((h * (int32_t)bmeCal.H3) >> 11) + 32768)) >> 10) +
                2097152) * (int32_t)bmeCal.H2 + 8192) >> 14));
        h -= ((((h >> 15) * (h >> 15)) >> 7) * (int32_t)bmeCal.H1) >> 4;
        if (h < 0) h = 0;
        if (h > 419430400) h = 419430400;
        lastHumidity = (h >> 12) / 1024.0f;
    }
    return true;
}

// --- barometric fall corroboration -----------------------------------
// A genuine fall drops the wrist ~0.5-1 m; pressure rises ~0.12 hPa/m.
// The accel gate asks "was there an impact?", the barometer answers
// "did the person actually go DOWN?". No height loss = likely a false
// alarm (arm swing, hand slap, dropped bag).

static const int           BARO_RING_N        = 40;      // 4 s @ 10 Hz
static const unsigned long BARO_SAMPLE_MS     = 100;
// Height loss that corroborates a fall. Measured on this band: a real fall
// read 0.81 m, while knocking it about on a desk read -0.07 m and +0.08 m.
// The separation is wide, so this threshold is not delicate.
static const float         BARO_DROP_M        = 0.40f;
// Upper sanity bound — a wrist cannot physically descend more than this in
// a single fall. Anything past it is a corrupted raw pressure sample (a
// bit-flipped ADC reading from bus noise still ACKs fine, so it never
// shows up as a Wire.cpp error) and must never count as evidence for
// raising an emergency, or a single glitched byte becomes a false alert.
static const float         BARO_DROP_MAX_M    = 3.0f;

static float baroRing[BARO_RING_N];
static int   baroHead = 0;
static bool  baroRingFull = false;
static float baroPreFallHpa = 0;
static float lastBaroDropM = 0;
static bool  lastBaroCorroborated = false;

// Average of the ring samples [from..to] readings ago (10 Hz spacing).
static float baroAvgBack(int from, int to)
{
    float s = 0; int n = 0;
    for (int back = from; back <= to; back++)
    {
        int idx = (baroHead - 1 - back + 2 * BARO_RING_N) % BARO_RING_N;
        s += baroRing[idx]; n++;
    }
    return n ? s / n : 0;
}

// =====================================================================
// Sensor bring-up and retry — one failure never affects the other
// =====================================================================

static void initSensors()
{
    Serial.println("\n--- I2C bus probe ---");
    probeBus(Wire,  "bus0", MPU_SDA, MPU_SCL);

    // BMP280's software-bit-banged bus isn't a TwoWire object probeBus()
    // can scan — checked manually here instead.
    Serial.printf("  [bus2] SDA=%d SCL=%d : %s\n", BME_SDA, BME_SCL,
                  busLineState(BME_SDA, BME_SCL).c_str());
    if (softAddrResponds(0x76))      Serial.println("  [bus2] 1 device(s): 0x76");
    else if (softAddrResponds(0x77)) Serial.println("  [bus2] 1 device(s): 0x77");
    else                              Serial.println("  [bus2] no devices responding");

    Serial.println("--- sensors ---");

    mpuReady = mpuInit(true);
    if (!mpuReady)
    {
        Serial.println("  MPU:       *** NOT FOUND ***");
        Serial.printf ("             reason: %s\n", mpuFault.c_str());
        Serial.println("             effect: fall detection and step counting are OFF.");
        Serial.println("             everything else still runs.");
    }

    maxReady = maxInit(true);
    if (!maxReady)
    {
        Serial.println("  Pulse Sensor: *** NOT FOUND ***");
        Serial.printf ("             reason: %s\n", maxFault.c_str());
        Serial.println("             effect: heart rate is OFF, defaults uploaded.");
        Serial.println("             everything else still runs.");
    }

    bmeReady = bmeInit(true);
    if (!bmeReady)
    {
        Serial.println("  BMP/BME:   *** NOT FOUND ***");
        Serial.printf ("             reason: %s\n", bmeFault.c_str());
        Serial.println("             effect: temperature/pressure are OFF.");
    }

    if (!mpuReady || !maxReady || !bmeReady)
        Serial.printf("\n  Missing sensors are retried every %lu s. No reboot needed —\n"
                      "  reseat the wiring and it will pick up on its own.\n",
                      SENSOR_RETRY_MS / 1000);
}

static void retrySensors()
{
    if (mpuReady && maxReady && bmeReady) return;
    if (millis() - lastSensorRetry < SENSOR_RETRY_MS) return;
    lastSensorRetry = millis();

    if (!mpuReady)
    {
        if (mpuInit(false))
        {
            mpuReady = true;
            head = 0; windowFull = false;      // discard the stale window
            Serial.printf("[sensor] MPU recovered at 0x%02X (%s).\n",
                          mpuAddr, whoAmIName(mpuWho));
        }
    }

    if (!maxReady)
    {
        if (maxInit(false))
        {
            maxReady = true;
            Serial.println("[sensor] Pulse Sensor recovered.");
        }
    }

    if (!bmeReady)
    {
        if (bmeInit(false))
        {
            bmeReady = true;
            baroHead = 0; baroRingFull = false;     // discard the stale history
            Serial.printf("[sensor] %s recovered at 0x%02X.\n",
                          bmeChip == 0x60 ? "BME280" : "BMP280", bmeAddr);
        }
    }
}

// The boot-time NTP attempt (see startBle's caller) is a single 20 s try —
// if it misses (DNS hiccup right as WiFi comes up, a captive portal not
// yet passed, etc.), it used to just stay wrong for the rest of the
// session: every uploaded lastUpdated would be bogus and the app would
// show the band as permanently offline even with data arriving every 5 s.
// This retries quietly in the background until it actually syncs.
static void retryNtpIfNeeded()
{
    if (ntpSynced) return;
    if (WiFi.status() != WL_CONNECTED) return;
    if (millis() - lastNtpRetry < NTP_RETRY_MS) return;
    lastNtpRetry = millis();

    if (time(nullptr) >= 1700000000)
    {
        ntpSynced = true;
        Serial.println("[sys] NTP synced.");
        return;
    }

    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
}

// Called when a healthy sensor starts failing mid-run.
static void markMpuLost()
{
    if (!mpuReady) return;
    mpuReady = false;
    mpuFault = "was working, then stopped responding — check for a loose wire "
               "or a sagging 3.3V rail";
    Serial.println("[sensor] MPU LOST. Fall detection OFF until it recovers.");
}

static void markMaxLost()
{
    if (!maxReady) return;
    maxReady = false;
    maxFault = "reading went flat — check for a disconnected wire (S/+/-)";
    Serial.println("[sensor] Pulse Sensor LOST. Heart rate OFF until it recovers.");
}

// =====================================================================
// Features — 22, notebook order
//   f[0..4]   magnitude mean, std, min, max, range
//   f[5..6]   magnitude p25, p75
//   f[7..9]   magnitude skew, kurtosis, rms
//   f[10..21] per axis x,y,z: mean, std, min, max
//
// Population stats, biased skew/kurtosis (numpy / scipy defaults).
// If the notebook used pandas these need ddof=1 correction.
// =====================================================================

static int cmpFloat(const void *a, const void *b)
{
    float fa = *(const float *)a, fb = *(const float *)b;
    return (fa > fb) - (fa < fb);
}
static float meanA(const float *a, int n)
{ float s = 0; for (int i = 0; i < n; i++) s += a[i]; return s / n; }
static float stdA(const float *a, int n, float mn)
{ float s = 0; for (int i = 0; i < n; i++) { float d = a[i] - mn; s += d * d; } return sqrtf(s / n); }
static float minA(const float *a, int n)
{ float m = a[0]; for (int i = 1; i < n; i++) if (a[i] < m) m = a[i]; return m; }
static float maxA(const float *a, int n)
{ float m = a[0]; for (int i = 1; i < n; i++) if (a[i] > m) m = a[i]; return m; }
static float rmsA(const float *a, int n)
{ float s = 0; for (int i = 0; i < n; i++) s += a[i] * a[i]; return sqrtf(s / n); }

static float skewA(const float *a, int n, float mn, float sd)
{
    if (sd < 1e-6f) return 0.0f;
    float s = 0;
    for (int i = 0; i < n; i++) { float d = a[i] - mn; s += d * d * d; }
    return (s / n) / (sd * sd * sd);
}
static float kurtA(const float *a, int n, float mn, float sd)
{
    if (sd < 1e-6f) return -3.0f;
    float s = 0;
    for (int i = 0; i < n; i++) { float d = a[i] - mn; d = d * d; s += d * d; }
    float var = sd * sd;
    return (s / n) / (var * var) - 3.0f;
}
static float pctSorted(const float *s, int n, float p)
{
    float rank = (p / 100.0f) * (n - 1);
    int lo = (int)floorf(rank), hi = (int)ceilf(rank);
    return s[lo] + (rank - lo) * (s[hi] - s[lo]);
}

static void computeFeatures(float *f)
{
    static float m[WIN_N];
    for (int i = 0; i < WIN_N; i++)
        m[i] = sqrtf(sx[i] * sx[i] + sy[i] * sy[i] + sz[i] * sz[i]);

    float mn = meanA(m, WIN_N), sd = stdA(m, WIN_N, mn);

    f[0] = mn; f[1] = sd;
    f[2] = minA(m, WIN_N); f[3] = maxA(m, WIN_N); f[4] = f[3] - f[2];
    f[7] = skewA(m, WIN_N, mn, sd);
    f[8] = kurtA(m, WIN_N, mn, sd);
    f[9] = rmsA(m, WIN_N);

    qsort(m, WIN_N, sizeof(float), cmpFloat);
    f[5] = pctSorted(m, WIN_N, 25);
    f[6] = pctSorted(m, WIN_N, 75);

    const float *axes[3] = { sx, sy, sz };
    int idx = 10;
    for (int ax = 0; ax < 3; ax++)
    {
        float amn = meanA(axes[ax], WIN_N);
        f[idx++] = amn;
        f[idx++] = stdA(axes[ax], WIN_N, amn);
        f[idx++] = minA(axes[ax], WIN_N);
        f[idx++] = maxA(axes[ax], WIN_N);
    }
}

// =====================================================================
// Sampling task — core 0
// =====================================================================

// Mean acceleration over ring samples [fromBack..toBack] readings ago.
// Used for the pre-impact gravity reference — i.e. which way the wrist was
// pointing before anything happened.
static void ringAvgBack(int fromBack, int toBack, float &ax, float &ay, float &az)
{
    double a = 0, b = 0, c = 0;
    int n = 0;

    if (xSemaphoreTake(bufLock, pdMS_TO_TICKS(5)) == pdTRUE)
    {
        for (int back = fromBack; back <= toBack; back++)
        {
            int idx = (head - 1 - back + 2 * WIN_N) % WIN_N;
            a += bx[idx]; b += by[idx]; c += bz[idx]; n++;
        }
        xSemaphoreGive(bufLock);
    }

    if (n) { ax = a / n; ay = b / n; az = c / n; }
    else   { ax = ay = az = 0; }
}

static void samplingTask(void *pv)
{
    TickType_t last = xTaskGetTickCount();
    unsigned long ffEndMs = 0, lastTrigger = 0;
    int ffRun = 0;
    int decim = 0, failRun = 0;

    for (;;)
    {
        vTaskDelayUntil(&last, SAMPLE_TICKS);

        if (!mpuReady) { failRun = 0; continue; }

        float gx, gy, gz;
        if (!mpuReadAccel(gx, gy, gz))
        {
            // Tolerate the odd glitch; give up after a solid second.
            if (++failRun > 200) { markMpuLost(); failRun = 0; }
            continue;
        }
        failRun = 0;

        float svm = sqrtf(gx * gx + gy * gy + gz * gz);
        lastSvm = svm;
        unsigned long now = millis();

        if (xSemaphoreTake(bufLock, pdMS_TO_TICKS(2)) == pdTRUE)
        {
            bx[head] = gx; by[head] = gy; bz[head] = gz;
            head = (head + 1) % WIN_N;
            if (head == 0) windowFull = true;
            xSemaphoreGive(bufLock);
        }

        if (++decim >= 4)
        {
            decim = 0;
            if (!stepRising && svm > STEP_HIGH && (now - lastPeakMs) > STEP_MIN_INTERVAL_MS)
            {
                stepRising = true;
                lastPeakMs = now;
                stepCount++;
            }
            else if (stepRising && svm < STEP_LOW) stepRising = false;
        }

        // ---- post-impact observation: is the wearer still, and rotated? ----
        if (postWatchOn && now >= postWatchFrom)
        {
            if (now < postWatchUntil)
            {
                pSum   += svm;
                pSumSq += (double)svm * svm;
                pgx += gx; pgy += gy; pgz += gz;
                pN++;
            }
            else
            {
                postWatchOn   = false;
                postWatchDone = true;
            }
        }

        // ---- deferred window capture ----
        // Fires POST_CAPTURE_MS after the impact, so the copied window spans
        // roughly 1 s before to 1 s after it rather than ending at it.
        if (capturePending && now >= captureAt)
        {
            if (xSemaphoreTake(bufLock, pdMS_TO_TICKS(10)) == pdTRUE)
            {
                memcpy(sx, bx, sizeof(sx));
                memcpy(sy, by, sizeof(sy));
                memcpy(sz, bz, sizeof(sz));
                xSemaphoreGive(bufLock);
                capturePending = false;
                gateFired      = true;
            }
        }

        // ---- gate: SUSTAINED free-fall, then a real impact ----
        if (svm < FREEFALL_G)
        {
            if (++ffRun >= FREEFALL_MIN_N) ffEndMs = now;
        }
        else ffRun = 0;

        bool paired = (svm > IMPACT_G) && ffEndMs && (now - ffEndMs < PAIR_MS);

        if (windowFull && paired && !gateFired && !capturePending &&
            (now - lastTrigger > REARM_MS))
        {
            lastTrigger = now;
            impactMs    = now;
            impactPeak  = svm;

            // Which way was the wrist pointing 0.6-2.0 s before the impact?
            ringAvgBack(120, WIN_N - 1, preGx, preGy, preGz);

            captureAt      = now + POST_CAPTURE_MS;
            capturePending = true;

            pSum = pSumSq = pgx = pgy = pgz = 0; pN = 0;
            postWatchFrom  = now + POST_SETTLE_MS;
            postWatchUntil = now + POST_SETTLE_MS + POST_WATCH_MS;
            postWatchDone  = false;
            postWatchOn    = true;

            ffEndMs = 0; ffRun = 0;
        }
    }
}

// =====================================================================
// Firebase
// =====================================================================

static void logHeap(const char *tag)
{
    Serial.printf("[heap] %-12s free=%u maxAlloc=%u\n",
                  tag, ESP.getFreeHeap(), ESP.getMaxAllocHeap());
}

static void closeHttps()
{
    https.end();
    secureClient.stop();      // this is what frees the mbedTLS buffers
}

static bool openHttps(const String &url, bool withAuth)
{
    closeHttps();

    secureClient.setInsecure();
    secureClient.setHandshakeTimeout(15);
    secureClient.setTimeout(10000);

    https.setReuse(false);
    https.setTimeout(10000);
    https.setConnectTimeout(10000);

    if (!https.begin(secureClient, url)) { Serial.println("https.begin() failed"); return false; }

    https.addHeader("Content-Type", "application/json");
    if (withAuth && idToken.length()) https.addHeader("Authorization", "Bearer " + idToken);
    return true;
}

static bool signInToFirebase()
{
    Serial.println("Refreshing Firebase ID token...");
    String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
                 + String(API_KEY);
    if (!openHttps(url, false)) return false;

    JsonDocument body;
    body["email"] = cfgEmail;
    body["password"] = cfgPassword;
    body["returnSecureToken"] = true;

    String payload;
    serializeJson(body, payload);

    int code = https.POST(payload);
    bool ok = false;

    if (code == 200)
    {
        JsonDocument doc;
        if (!deserializeJson(doc, https.getString()) && doc["idToken"].is<const char *>())
        {
            idToken = doc["idToken"].as<String>();
            tokenAt = millis();
            ok = true;
            Serial.println("Firebase sign-in OK.");
        }
        else Serial.println("Sign-in: could not parse idToken.");
    }
    else
    {
        Serial.printf("Sign-in failed, HTTP %d\n", code);
        if (code > 0) Serial.println(https.getString());
    }

    closeHttps();
    return ok;
}

static bool haveValidToken()
{
    if (idToken.length() == 0 || millis() - tokenAt > TOKEN_LIFETIME_MS)
        return signInToFirebase();
    return true;
}

// RTDB's REST API accepts a Firebase ID token only as ?auth= in the URL —
// sending it as an Authorization: Bearer header gets 401 "Unauthorized request".
static String bandUrl()
{
    String u = String(DATABASE_URL) + "bands/" + bandId + ".json";
    if (idToken.length()) u += "?auth=" + idToken;
    return u;
}
// Save historical activity data to Firebase
static bool saveActivityHistory()
{
    if (!uploadsEnabled || WiFi.status() != WL_CONNECTED)
        return false;

    if (!haveValidToken())
        return false;

    unsigned long nowMs = millis();

    // Save immediately the first time, then every 5 minutes
    if (lastActivityHistorySave != 0 &&
        nowMs - lastActivityHistorySave < 300000UL)
        return false;

    int currentSteps = stepCount;
    int activitySteps = 0;

    // First reading establishes the baseline
    if (historyBaselineReady)
    {
        if (currentSteps >= lastHistoryStepCount)
            activitySteps = currentSteps - lastHistoryStepCount;
        else
            activitySteps = currentSteps; // Counter reset
    }

    JsonDocument doc;

    doc["steps"] = currentSteps;
    doc["activitySincePrevious"] = activitySteps;
    doc["timestamp"] = (unsigned long)time(nullptr);

    String json;
    serializeJson(doc, json);

    String historyUrl =
        String(DATABASE_URL) +
        "activity_history/" + bandId + ".json?auth=" + idToken;

    if (!openHttps(historyUrl, false))
        return false;

    int code = https.POST(json);
    bool success = (code == HTTP_CODE_OK);

    Serial.printf(
        "[Activity History] HTTP %d, steps=%d, interval=%d\n",
        code, currentSteps, activitySteps
    );

    closeHttps();

    if (success)
    {
        lastHistoryStepCount = currentSteps;
        historyBaselineReady = true;
        lastActivityHistorySave = nowMs;
    }

    return success;
}
static bool checkCancelRequest()
{
    if (!openHttps(bandUrl(), false)) return false;   // token rides in the URL

    bool cancel = false;
    int code = https.GET();
    if (code == HTTP_CODE_OK)
    {
        JsonDocument doc;
        if (!deserializeJson(doc, https.getString()) && doc["cancelRequested"] == true)
            cancel = true;
    }
    else Serial.printf("Cancel-check HTTP %d\n", code);

    closeHttps();
    return cancel;
}

// Failures back off. They no longer reboot the board.
static void noteUploadFailure()
{
    failStreak++;
    uploadBackoff = (uploadBackoff == 0) ? NORMAL_UPLOAD_MS : uploadBackoff * 2;
    if (uploadBackoff > MAX_BACKOFF_MS) uploadBackoff = MAX_BACKOFF_MS;

    Serial.printf("Upload failures: %d — next attempt in %lu s\n",
                  failStreak, uploadBackoff / 1000);

    // Reconnecting the link is a far better response than rebooting.
    if (failStreak == 3 || failStreak == 6)
    {
        Serial.println("Reconnecting WiFi...");
        WiFi.disconnect();
        delay(200);
        WiFi.reconnect();
    }
    if (failStreak >= 4) { idToken = ""; }   // assume the token went bad
}

static bool uploadVitals()
{
    if (!uploadsEnabled) return false;
    if (WiFi.status() != WL_CONNECTED) { Serial.println("WiFi down, skipping upload."); return false; }
    if (!haveValidToken()) { noteUploadFailure(); return false; }

    if (fallActive && checkCancelRequest())
    {
        Serial.println("Cancel request found — clearing emergency.");
        fallActive = false;
    }

    JsonDocument doc;
    doc["heartRate"]       = heartRate;
    doc["spo2"]            = spo2;
    doc["fallDetected"]    = fallActive;
    doc["steps"]           = stepCount;
    doc["status"]          = fallActive ? "EMERGENCY" : "NORMAL";
    doc["cancelRequested"] = false;
    doc["lastUpdated"]     = (unsigned long)time(nullptr);
    // So the app can tell "no fall" apart from "cannot detect falls".
    doc["mpuOk"]           = (bool)mpuReady;
    doc["maxOk"]           = (bool)maxReady;
    doc["bmeOk"]           = (bool)bmeReady;
    if (bmeReady)
    {
        doc["temperature"] = ((int)(lastTempC * 10)) / 10.0;
        doc["pressure"]    = ((int)(lastPressHpa * 10)) / 10.0;
        if (bmeChip == 0x60) doc["humidity"] = ((int)(lastHumidity * 10)) / 10.0;
    }
    if (fallActive)
    {
        doc["baroDropM"]   = ((int)(lastBaroDropM * 100)) / 100.0;
        doc["baroConfirm"] = lastBaroCorroborated;
    }

    String json;
    serializeJson(doc, json);

    if (!openHttps(bandUrl(), false)) { noteUploadFailure(); return false; }

    int code = https.PUT(json);
    bool ok = (code == HTTP_CODE_OK);
    Serial.printf("Upload %s (HTTP %d)\n", ok ? "OK" : "FAILED", code);
    if (!ok && code > 0) Serial.println(https.getString());
    closeHttps();

    if (ok) { failStreak = 0; uploadBackoff = 0; }
    else    { noteUploadFailure(); }

    return ok;
}

// =====================================================================
// WiFi + BLE provisioning
// =====================================================================

// SSIDs only, comma-separated — never the passwords. Mirrors the scanned-
// network list's format (see chWifiList) so the app parses both the same
// way, and lets a user confirm a Change WiFi didn't wipe an older entry.
static String savedNetworkSsidList()
{
    prefs.begin("wifi", true);
    String saved = prefs.getString(WIFI_KEY, "[]");
    prefs.end();

    JsonDocument doc;
    if (deserializeJson(doc, saved) || !doc.is<JsonArray>()) return "";

    String out;
    for (JsonObject n : doc.as<JsonArray>())
    {
        if (!out.isEmpty()) out += ",";
        out += (const char *)n["ssid"];
    }
    return out;
}

static void saveWifiNetwork(const String &ssid, const String &password)
{
    prefs.begin("wifi", false);
    String existing = prefs.getString(WIFI_KEY, "[]");

    JsonDocument doc;
    deserializeJson(doc, existing);
    JsonArray nets = doc.is<JsonArray>() ? doc.as<JsonArray>() : doc.to<JsonArray>();

    bool updated = false;
    for (JsonObject n : nets)
        if (String((const char *)n["ssid"]) == ssid) { n["password"] = password; updated = true; break; }

    if (!updated)
    {
        JsonObject n = nets.add<JsonObject>();
        n["ssid"] = ssid;
        n["password"] = password;
    }

    String out;
    serializeJson(doc, out);
    prefs.putString(WIFI_KEY, out);
    prefs.end();

    Serial.printf("Saved network (%d known): %s\n", nets.size(), ssid.c_str());
}

static bool connectUsingScan(int found)
{
    prefs.begin("wifi", true);
    String saved = prefs.getString(WIFI_KEY, "[]");
    prefs.end();

    JsonDocument doc;
    if (deserializeJson(doc, saved) || !doc.is<JsonArray>() || doc.as<JsonArray>().size() == 0)
    {
        Serial.println("No saved WiFi networks — staying in provisioning mode.");
        return false;
    }

    JsonArray nets = doc.as<JsonArray>();

    for (int i = 0; i < found; i++)
    {
        String seen = WiFi.SSID(i);
        if (seen.isEmpty()) continue;

        for (JsonObject n : nets)
        {
            if (seen != String((const char *)n["ssid"])) continue;

            Serial.printf("Connecting to %s ...\n", seen.c_str());
            WiFi.begin(seen.c_str(), String((const char *)n["password"]).c_str());

            for (int a = 0; a < 20 && WiFi.status() != WL_CONNECTED; a++)
            { delay(500); Serial.print('.'); }
            Serial.println();

            if (WiFi.status() == WL_CONNECTED)
            {
                Serial.print("Connected. IP: ");
                Serial.println(WiFi.localIP());
                return true;
            }
            Serial.println("Failed — trying next match.");
        }
    }

    Serial.println("No saved network in range.");
    return false;
}

// The callback ONLY copies the string. NVS writes and ESP.restart() from
// inside the BLE host task can overflow its stack and panic — that was a
// real reboot source. loop() does the work.
//
// SIGNATURE NOTE: this is the NimBLE-Arduino 2.x form. On 1.4.x it is
//   void onWrite(NimBLECharacteristic *c) override
// without the NimBLEConnInfo parameter.
class WifiCredentialsCallback : public NimBLECharacteristicCallbacks
{
    void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &connInfo) override
    {
        provisionPayload = String(c->getValue().c_str());
        provisionPending = true;
    }
};

static void handleProvisioning()
{
    if (!provisionPending) return;
    provisionPending = false;

    String data = provisionPayload;
    provisionPayload = "";

    Serial.printf("\nProvisioning data received (%d bytes).\n", data.length());

    int p1 = data.indexOf('|');
    int p2 = data.indexOf('|', p1 + 1);
    int p3 = data.indexOf('|', p2 + 1);
    int p4 = data.indexOf('|', p3 + 1);

    if (p1 < 0 || p2 < 0 || p3 < 0 || p4 < 0)
    {
        Serial.println("Invalid format — expected ssid|wifiPass|email|firebasePass|bandId");
        Serial.println("If the string looks truncated, the app did not raise the BLE MTU.");
        return;
    }

    saveWifiNetwork(data.substring(0, p1), data.substring(p1 + 1, p2));

    prefs.begin("firebase", false);
    prefs.putString("email",    data.substring(p2 + 1, p3));
    prefs.putString("password", data.substring(p3 + 1, p4));
    prefs.end();

    prefs.begin("band", false);
    prefs.putString("bandId", data.substring(p4 + 1));
    prefs.end();

    prefs.begin("sys", false);      // this restart is intentional, not a loop
    prefs.putInt("boots", 0);
    prefs.end();

    Serial.println("Provisioning saved. Restarting...");
    delay(300);
    ESP.restart();
}

static void startBle(const String &wifiList)
{
    NimBLEDevice::init("safeband");
    NimBLEDevice::setMTU(517);      // the app must also call requestMtu(512)

    NimBLEServer  *server = NimBLEDevice::createServer();
    NimBLEService *svc    = server->createService(SVC_UUID);

    chWifiList = svc->createCharacteristic(READ_UUID, NIMBLE_PROPERTY::READ);
    chWifiList->setValue(wifiList.c_str());

    chWifiCreds = svc->createCharacteristic(WRITE_UUID, NIMBLE_PROPERTY::WRITE);
    chWifiCreds->setCallbacks(new WifiCredentialsCallback());

    chSavedNets = svc->createCharacteristic(SAVED_UUID, NIMBLE_PROPERTY::READ);
    chSavedNets->setValue(savedNetworkSsidList().c_str());

    svc->start();

    NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SVC_UUID);

    // NimBLEDevice::init(name) alone doesn't put the name INTO the
    // advertisement — without this, scanners like LightBlue show
    // "Unnamed" even though the device technically has a name set.
    NimBLEAdvertisementData scanResponse;
    scanResponse.setName("safeband");
    adv->setScanResponseData(scanResponse);

    adv->enableScanResponse(true);      // 2.x name; on 1.4.x it is setScanResponse(true)
    NimBLEDevice::startAdvertising();

    bleUp = true;
    Serial.println("BLE advertising as safeband.");
    logHeap("ble-up");
}

static void releaseBle()
{
    if (bleFreed) return;

    if (bleUp) { NimBLEDevice::deinit(true); delay(100); }
    esp_bt_mem_release(ESP_BT_MODE_BTDM);

    bleUp = false; bleFreed = true;
    if (!safeMode) uploadsEnabled = true;

    Serial.println("BLE released — uploads enabled. Reboot to re-provision.");
    logHeap("ble-freed");
}

// =====================================================================
// setup()
// =====================================================================

void setup()
{
    Serial.begin(115200);
    delay(800);
    bootMs = millis();

    Serial.println("\n\n******** SafeBand ********");
    Serial.printf("Chip: %s, %d core(s), rev %d, flash %u MB\n",
                  ESP.getChipModel(), ESP.getChipCores(), ESP.getChipRevision(),
                  ESP.getFlashChipSize() / (1024 * 1024));
    reportResetReason();

    int boots = bumpBootCount();
    Serial.printf("Consecutive fast reboots: %d\n", boots);

    if (boots >= BOOTLOOP_LIMIT)
    {
        safeMode = true;
        Serial.println("\n*** SAFE MODE ***");
        Serial.println("Too many reboots in a row. Networking is disabled so you can");
        Serial.println("read this log. Sensors and serial commands still work.");
        Serial.println("Press 'c' to clear the counter and reboot normally.\n");
    }

    logHeap("boot");
    bufLock = xSemaphoreCreateMutex();
    i2cLock = xSemaphoreCreateMutex();

    // ---- config ----
    prefs.begin("firebase", true);
    cfgEmail    = prefs.getString("email", "");
    cfgPassword = prefs.getString("password", "");
    prefs.end();
    if (cfgEmail.isEmpty())    cfgEmail    = String(FIREBASE_EMAIL);
    if (cfgPassword.isEmpty()) cfgPassword = String(FIREBASE_PASSWORD);

    WiFi.mode(WIFI_STA);            // must precede macAddress()

    prefs.begin("band", true);
    bandId = prefs.getString("bandId", "");
    prefs.end();
    if (bandId.isEmpty()) bandId = WiFi.macAddress();

    Serial.printf("Band ID: %s\n", bandId.c_str());
    Serial.printf("Firebase account: %s\n", cfgEmail.c_str());

    // ---- sensors FIRST, so a network failure never hides sensor status ----
    initSensors();

    xTaskCreatePinnedToCore(samplingTask, "sampling", 6144, nullptr, 3, nullptr, 0);

    if (safeMode)
    {
        Serial.println("\nSafe mode: skipping WiFi and BLE.");
        return;
    }

    // ---- WiFi ----
    Serial.println("\nScanning WiFi...");
    // show_hidden (2nd arg) was true — forces active probing on every
    // channel to find hidden SSIDs too, which is the single biggest cost
    // in an ESP32 WiFi scan (routinely adds several seconds). Off by
    // default now since the whole point here is picking a visible
    // network off the list; a hidden home network is rare enough not to
    // pay this cost on every single boot for it.
    int found = WiFi.scanNetworks(false, false);

    String wifiList;
    for (int i = 0; i < found && wifiList.length() < 400; i++)
    {
        String s = WiFi.SSID(i);
        if (s.isEmpty() || wifiList.indexOf(s + ",") >= 0) continue;
        wifiList += s; wifiList += ",";
    }
    Serial.printf("Networks found: %d\n", found);

    bool wifiOk = connectUsingScan(found);
    WiFi.scanDelete();

    if (wifiOk)
    {
        configTime(0, 0, "pool.ntp.org", "time.nist.gov");
        Serial.print("NTP");
        unsigned long t0 = millis();
        while (time(nullptr) < 1700000000 && millis() - t0 < NTP_TIMEOUT_MS)
        { delay(500); Serial.print('.'); }
        ntpSynced = time(nullptr) >= 1700000000;
        Serial.println(ntpSynced ? " synced." : " TIMEOUT.");
        if (!ntpSynced)
            Serial.println("  Will keep retrying in the background — until it syncs, "
                            "uploaded timestamps are wrong and the app will show the "
                            "band as offline even though data is arriving fine.");
    }

    startBle(wifiList);

    Serial.printf("\nBLE provisioning window: %lu s, then uploads begin.\n",
                  BLE_GRACE_MS / 1000);
    Serial.println("Serial: f=fake fall  b=free BLE now  h=heap  s=sensor status  "
                   "w=list saved wifi  c=clear boot count  "
                   "r=factory reset (press twice within 5s)\n");
}

// =====================================================================
// loop()
// =====================================================================

static void printSensorStatus()
{
    Serial.println("\n--- sensor status ---");
    if (mpuReady) Serial.printf("  MPU:       OK  (0x%02X, %s)  |a|=%.2f g  steps=%d\n",
                                mpuAddr, whoAmIName(mpuWho), lastSvm, stepCount);
    else          Serial.printf("  MPU:       NOT FOUND — %s\n", mpuFault.c_str());

    if (maxReady) Serial.printf("  Pulse Sensor: OK  (GPIO%d)  hr=%d spo2=%d  raw=%d base=%ld  "
                                "amplitude=%d (need >=%d)  finger=%s\n",
                                PULSE_PIN, lastHeartRate, lastSpo2, lastPulseRaw, irBaseline,
                                lastPulseAmplitude, NO_FINGER_MIN_AMPLITUDE,
                                fingerPresent ? "yes" : "no");
    else          Serial.printf("  Pulse Sensor: NOT FOUND — %s\n", maxFault.c_str());

    if (bmeReady) Serial.printf("  BMP/BME:   OK  (0x%02X, %s)  t=%.1fC p=%.1fhPa h=%.0f%%\n",
                                bmeAddr, bmeChip == 0x60 ? "BME280" : "BMP280",
                                lastTempC, lastPressHpa, lastHumidity);
    else          Serial.printf("  BMP/BME:   NOT FOUND — %s\n", bmeFault.c_str());

    Serial.printf("  WiFi: %s   uploads: %s   heap: %u\n",
                  WiFi.status() == WL_CONNECTED ? "connected" : "down",
                  uploadsEnabled ? "on" : "off", ESP.getFreeHeap());

    Serial.println("  fall gate:  free-fall <" + String(FREEFALL_G, 2) + " g for " +
                   String(FREEFALL_MIN_N * 5) + " ms, then impact >" +
                   String(IMPACT_G, 2) + " g");
    Serial.printf("  confirm:    motion std <%.2f g, wrist turn >%.0f deg, drop >=%.2f m%s\n",
                  STILL_STD_G, ORIENT_MIN_DEG, BARO_DROP_M,
                  (bmeReady ? "" : "  (no baro — drop check inactive)"));
    if (impactMs)
        Serial.printf("  last event: %lu s ago, peak %.2f g, std %.3f g, turn %.0f deg, "
                      "drop %.2f m\n",
                      (millis() - impactMs) / 1000, impactPeak,
                      lastStillStd, lastOrientDeg, lastBaroDropM);
    else
        Serial.println("  last event: none since boot");
    Serial.println("---------------------\n");
}

static void raiseEmergency(const char *reason)
{
    Serial.printf("\n===== FALL CONFIRMED (%s) =====\n", reason);
    fallActive = true;
    emergencyStart = millis();

    if (lastHeartRate > 0) heartRate = lastHeartRate;
    if (lastSpo2 > 0)      spo2      = lastSpo2;

    if (!safeMode) { releaseBle(); uploadVitals(); lastUpload = millis(); }
}

void loop()
{
    // 100 Hz is plenty for beat detection on this sensor; no I2C bus to
    // overrun here, but there's no reason to sample faster than that.
    static unsigned long lastHrAt = 0;
    if (millis() - lastHrAt >= 10)
    {
        lastHrAt = millis();
        updateHeartRateSensor();
    }

    // No sensor on this board can measure SpO2 (that needs the MAX30102's
    // red/IR pair, removed with the Pulse Sensor swap) — simulated on a
    // timer instead, at the user's explicit request, so the field isn't
    // just frozen. Plausible healthy-range noise, not tied to anything
    // real; nothing else here treats it as more than a placeholder.
    static unsigned long lastSpo2SimAt = 0;
    if (millis() - lastSpo2SimAt >= 5000)
    {
        lastSpo2SimAt = millis();
        lastSpo2 = random(95, 100);   // 95-99 inclusive
    }

    retrySensors();
    retryNtpIfNeeded();
    handleProvisioning();

    // ---- BMP/BME280: 10 Hz pressure into the fall-check ring ----
    static unsigned long lastBmeAt = 0;
    static int bmeFailRun = 0;
    if (bmeReady && millis() - lastBmeAt >= BARO_SAMPLE_MS)
    {
        lastBmeAt = millis();
        if (bmeRead())
        {
            bmeFailRun = 0;
            baroRing[baroHead] = lastPressHpa;
            baroHead = (baroHead + 1) % BARO_RING_N;
            if (baroHead == 0) baroRingFull = true;
        }
        else if (++bmeFailRun >= 30)
        {
            bmeReady = false; bmeFailRun = 0;
            baroHead = 0; baroRingFull = false;
            bmeFault = "was working, then stopped responding";
            Serial.println("[sensor] BMP/BME280 LOST. Temp/pressure OFF until it recovers.");
        }
    }

    // Survived a minute? Then this boot was not part of a loop.
    if (!bootCountCleared && millis() - bootMs > STABLE_AFTER_MS) clearBootCount();

    // ---- BLE grace ----
    if (!safeMode && !bleFreed && millis() - bootMs > BLE_GRACE_MS)
        if (WiFi.status() == WL_CONNECTED && !cfgEmail.isEmpty()) releaseBle();

    // ---- model, on the impact-centred window ----
    if (gateFired)
    {
        gateFired = false;
        Serial.printf("\n>>> gate: sustained free-fall + %.2f g impact\n", impactPeak);

        float f[22];
        computeFeatures(f);
        int pred = clf.predict(f);
        Serial.printf("    model class = %d, window peak = %.2f g\n", pred, f[3]);

        if (pred == 1 && !fallActive)
        {
            // Reference pressure 1.0-2.5 s before the impact. The window was
            // captured POST_CAPTURE_MS late, so reach that much further back.
            if (bmeReady && baroRingFull)
                baroPreFallHpa = baroAvgBack(10 + POST_CAPTURE_MS / BARO_SAMPLE_MS,
                                             25 + POST_CAPTURE_MS / BARO_SAMPLE_MS);
            confirmPending = true;
            Serial.println("    model says fall — confirming with post-impact motion...");
        }
        else if (pred != 1)
        {
            confirmPending = false;
            Serial.println("    model: not a fall");
        }
    }

    // If the MPU drops out mid-watch the observation never completes. Don't
    // leave a fall half-judged forever — abandon it and re-arm.
    if (confirmPending && millis() - impactMs > POST_SETTLE_MS + POST_WATCH_MS + 3000UL)
    {
        confirmPending = false;
        postWatchOn    = false;
        Serial.println("    confirm: timed out (sensor dropped out) — ignoring.");
    }

    // ---- confirmation: was the wearer actually still, rotated, and lower? ----
    if (confirmPending && postWatchDone)
    {
        confirmPending = false;
        postWatchDone  = false;

        int n = pN;
        if (n < 50)                                  // sensor dropped out mid-watch
        {
            Serial.println("    confirm: not enough post-impact data — ignoring.");
        }
        else
        {
            float mean = pSum / n;
            float var  = pSumSq / n - (double)mean * mean;
            lastStillStd = var > 0 ? sqrtf(var) : 0.0f;

            float qx = pgx / n, qy = pgy / n, qz = pgz / n;
            float na = sqrtf(preGx * preGx + preGy * preGy + preGz * preGz);
            float nb = sqrtf(qx * qx + qy * qy + qz * qz);

            lastOrientDeg = 0;
            if (na > 1e-3f && nb > 1e-3f)
            {
                float d = (preGx * qx + preGy * qy + preGz * qz) / (na * nb);
                if (d >  1.0f) d =  1.0f;
                if (d < -1.0f) d = -1.0f;
                lastOrientDeg = acosf(d) * 57.2957795f;
            }

            bool still   = lastStillStd  < STILL_STD_G;
            bool rotated = lastOrientDeg > ORIENT_MIN_DEG;

            bool baroUsable = bmeReady && baroRingFull;
            if (baroUsable)
            {
                float post = baroAvgBack(0, 4);                 // last 0.5 s
                lastBaroDropM = (post - baroPreFallHpa) * 8.3f; // rises going down
                lastBaroCorroborated = lastBaroDropM >= BARO_DROP_M &&
                                       lastBaroDropM <= BARO_DROP_MAX_M;
            }
            else { lastBaroDropM = 0; lastBaroCorroborated = false; }

            Serial.printf("    confirm: motion std %.3f g (<%.2f %s), wrist turned "
                          "%.0f deg (>%.0f %s)\n",
                          lastStillStd, STILL_STD_G, still ? "OK" : "FAIL",
                          lastOrientDeg, ORIENT_MIN_DEG, rotated ? "OK" : "FAIL");
            if (baroUsable)
                Serial.printf("    confirm: height dropped %.2f m (need %.2f-%.2f %s)\n",
                              lastBaroDropM, BARO_DROP_M, BARO_DROP_MAX_M,
                              lastBaroCorroborated ? "OK" :
                                  (lastBaroDropM > BARO_DROP_MAX_M ? "REJECTED-implausible" : "FAIL"));
            else
                Serial.println("    confirm: no barometer — deciding on motion alone");

            // Weighted evidence — see CONFIRM_SCORE. A fall means the wearer
            // went DOWN; whether they then lie still or thrash about is not
            // the test, because both happen.
            int score = 0;
            if (baroUsable && lastBaroCorroborated) score += BARO_WEIGHT;
            if (rotated) score += ORIENT_WEIGHT;
            if (still)   score += STILL_WEIGHT;

            int needed = baroUsable ? CONFIRM_SCORE : CONFIRM_SCORE_NO_BARO;

            Serial.printf("    confirm: evidence score %d (need %d) "
                          "[drop %d + turn %d + still %d]\n",
                          score, needed,
                          (baroUsable && lastBaroCorroborated) ? BARO_WEIGHT : 0,
                          rotated ? ORIENT_WEIGHT : 0,
                          still   ? STILL_WEIGHT  : 0);

            if (score >= needed)
            {
                raiseEmergency(lastBaroCorroborated ? "model+baro descent" : "model+motion");
            }
            else
            {
                Serial.printf("    SUPPRESSED as a false alarm (%s%s).\n",
                              (baroUsable && !lastBaroCorroborated)
                                  ? "the wearer did not go down " : "",
                              !rotated ? "wrist angle unchanged" : "");
            }
        }
    }
    // Save daily activity history
saveActivityHistory();

    // ---- periodic status line ----
    static unsigned long lastStatus = 0;
    if (millis() - lastStatus > STATUS_EVERY_MS)
    {
        lastStatus = millis();
        Serial.printf("[status] mpu=%s max=%s bme=%s wifi=%s heap=%u steps=%d |a|=%.2fg\n",
                      mpuReady ? "OK" : "MISSING",
                      WiFi.status() == WL_CONNECTED ? "OK" : "DOWN",
                      ESP.getFreeHeap(), stepCount, lastSvm);
    }

    // ---- serial ----
    if (Serial.available())
    {
        char c = Serial.read();

        if      ((c == 'f' || c == 'F') && !fallActive) { heartRate = 132; spo2 = 89; raiseEmergency("m"); }
        else if (c == 'b' || c == 'B') releaseBle();
        else if (c == 'h' || c == 'H') logHeap("manual");
        else if (c == 's' || c == 'S') printSensorStatus();
        else if (c == 'i' || c == 'I') initSensors();          // re-probe on demand
        else if (c == 'w' || c == 'W')
        {
            prefs.begin("wifi", true);
            String saved = prefs.getString(WIFI_KEY, "[]");
            prefs.end();
            Serial.printf("\nSaved WiFi networks (raw): %s\n\n", saved.c_str());
        }
        else if (c == 'c' || c == 'C')
        {
            clearBootCount();
            Serial.println("Rebooting normally...");
            delay(300);
            ESP.restart();
        }
        else if (c == 'r' || c == 'R')
        {
            // Two presses required, not one: a USB replug can inject stray
            // noise onto the serial RX line that looks like a keypress —
            // a single 'r' wiping every saved credential on a random byte
            // is exactly the kind of accidental trigger that bit us here.
            static unsigned long armedAt = 0;
            if (armedAt != 0 && millis() - armedAt < 5000)
            {
                Serial.println("FACTORY RESET");
                for (const char *ns : { "wifi", "firebase", "band", "sys" })
                { prefs.begin(ns, false); prefs.clear(); prefs.end(); }
                delay(500);
                ESP.restart();
            }
            else
            {
                armedAt = millis();
                Serial.println("Press 'r' again within 5 s to confirm factory reset "
                               "(erases saved WiFi/Firebase/band credentials).");
            }
        }
    }

    // ---- emergency auto-clear ----
    if (fallActive && millis() - emergencyStart >= EMERGENCY_HOLD_MS)
    {
        Serial.println("===== EMERGENCY AUTO-CLEARED =====");
        fallActive = false;
        heartRate = lastHeartRate;
        spo2      = lastSpo2;
        if (!safeMode) { uploadVitals(); lastUpload = millis(); }
    }

    // ---- periodic upload, with backoff ----
    unsigned long interval = uploadBackoff ? uploadBackoff
                           : (fallActive ? 5000UL : NORMAL_UPLOAD_MS);

    if (uploadsEnabled && millis() - lastUpload >= interval)
    {
        lastUpload = millis();
        if (lastHeartRate > 0) heartRate = lastHeartRate;
        if (lastSpo2 > 0)      spo2      = lastSpo2;
        uploadVitals();
    }

    delay(5);
}

