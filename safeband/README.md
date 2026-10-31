
# SafeBand — Smart Wearable for Safety and Health Monitoring

SafeBand is an IoT-based wearable prototype designed to monitor movement and selected health-related information, detect possible falls using machine learning, and help family members respond through a Flutter mobile application.

## Project Overview

SafeBand combines wearable sensors, an ESP32 microcontroller, on-device fall detection, Wi-Fi, Bluetooth Low Energy (BLE), Firebase Realtime Database, and a Flutter application.

The wearable collects sensor readings. The ESP32 processes motion data locally using a Random Forest model and applies additional checks, such as impact, wrist rotation, post-impact stillness, and barometric change, to help reduce false alarms. Emergency and sensor information can then be uploaded to Firebase over Wi-Fi and viewed in the mobile application.

> **Prototype note:** SafeBand is an academic/project prototype, not a certified medical device or a replacement for professional medical or emergency services. The current SpO₂ field is simulated; the analog Pulse Sensor does not measure SpO₂.

## System Overview

```text
Wearer
  |
  v
SafeBand Sensors
  |
  v
ESP32
  |-- Motion Processing and Random Forest Fall Detection
  |-- Fall Confirmation Checks
  |-- Heart-Rate Monitoring
  |-- Environmental Monitoring
  `-- BLE Provisioning
  |
  v
Wi-Fi
  |
  v
Firebase Realtime Database
  |
  v
Flutter Mobile Application
  |
  v
Family Member
```

## Objectives

- Improve wearable-based personal safety.
- Detect possible falls using machine learning.
- Monitor basic health-related and environmental information.
- Collect and store sensor information.
- Synchronize wearable data with Firebase.
- Provide a mobile interface for family monitoring.
- Surface an emergency status when a fall is confirmed.
- Simplify initial wearable configuration using BLE.

## Key Features

1. ### Machine Learning Fall Detection

   A Random Forest classifier is deployed on the ESP32 to classify motion data. The model is included in the firmware as `fall_model.h`.

2. ### Motion Monitoring

   The MPU6050 accelerometer and gyroscope provide motion readings used for fall detection.

3. ### Heart-Rate Monitoring

   The current firmware uses an analog Pulse Sensor for heart-rate monitoring.

4. ### Environmental Monitoring

   The BMP280/BME280 sensor provides pressure and temperature readings. Humidity is available only when supported by the installed sensor.

5. ### Emergency Detection

   The system checks additional motion and environmental signals before raising a confirmed-fall state.

6. ### Cloud Synchronization

   The ESP32 can upload sensor and emergency information to Firebase Realtime Database over Wi-Fi.

7. ### Flutter Mobile Application

   The application provides the family-side interface for viewing wearable information and fall/emergency status.

8. ### BLE Provisioning

   Bluetooth Low Energy is used to send initial configuration information, including Wi-Fi settings, Firebase credentials, and the Band ID.

## System Architecture

```text
+--------------------------------------------------+
|                 SafeBand Wearable                |
|                                                  |
|    MPU6050    |   Pulse Sensor   |   BMP/BME280  |
+-------------------------+------------------------+
                          |
                          v
+--------------------------------------------------+
|                      ESP32                       |
|                                                  |
|  - Sensor Data Acquisition                       |
|  - Feature Extraction                            |
|  - Random Forest Fall Detection                  |
|  - Fall Confirmation                             |
|  - Health and Environmental Monitoring            |
|  - BLE Provisioning                              |
+-------------------------+------------------------+
                          |
                        Wi-Fi
                          |
                          v
+--------------------------------------------------+
|            Firebase Realtime Database            |
|                                                  |
|  - Sensor Data                                   |
|  - Band Status                                   |
|  - Fall/Emergency Status                         |
+-------------------------+------------------------+
                          |
                          v
+--------------------------------------------------+
|               Flutter Application                |
|                                                  |
|  - Wearable Information                          |
|  - Fall Status                                   |
|  - Family Monitoring                             |
+-------------------------+------------------------+
                          |
                          v
                    Family Member
```

## Fall Detection

The MPU6050 supplies accelerometer and gyroscope data. The ESP32 maintains a rolling motion window and calculates a 22-feature vector from the motion data.

### Extracted Features

The feature set includes:

- Mean
- Standard deviation
- Minimum and maximum
- Range
- 25th and 75th percentiles
- Skewness
- Kurtosis
- Root Mean Square (RMS)
- Axis-specific statistics for the X, Y, and Z axes

The features are passed to the Random Forest model deployed in:

```text
firmware/include/fall_model.h
```

### Fall Confirmation Flow

```text
Motion Data
    |
    v
Random Forest Predicts a Possible Fall
    |
    v
Additional Evidence Is Checked
    |
    +-- Sustained Free-Fall
    +-- Impact
    +-- Wrist Rotation
    +-- Post-Impact Stillness
    `-- Barometric Height Change
    |
    v
Confirmed-Fall / Emergency State
```

These checks are intended to reduce false detections. They do not guarantee that every fall will be detected correctly.

## Hardware Components

| Component | Purpose |
|---|---|
| ESP32 | Main controller, local processing, and communication |
| MPU6050 | Accelerometer and gyroscope for motion monitoring and fall detection |
| Analog Pulse Sensor | Heart-rate signal monitoring |
| BMP280/BME280 | Temperature and pressure; humidity where supported |
| Battery/Power Supply | Portable power for the wearable |

## Software and Technologies

| Technology | Usage |
|---|---|
| C/C++ | ESP32 firmware |
| Arduino Framework | Embedded development |
| PlatformIO | Firmware development and build environment |
| ESP32 | Edge processing and device communication |
| Random Forest | Fall classification |
| Flutter | Mobile application |
| Dart | Flutter application development |
| Firebase Realtime Database | Cloud data storage and synchronization |
| Wi-Fi | Cloud communication |
| Bluetooth Low Energy (BLE) | Initial device provisioning |
| I²C | Sensor communication |
| GPIO | Pulse Sensor and hardware connections |

## Communication

### Wi-Fi

Wi-Fi is used by the ESP32 to:

- Connect to the configured network.
- Connect to Firebase using the configured authentication details.
- Upload sensor data.
- Upload fall and emergency status.

Cloud synchronization depends on network availability.

### Bluetooth Low Energy (BLE)

BLE is used primarily during initial device provisioning.

```text
Mobile Device
     |
    BLE
     |
     v
    ESP32
     |
     v
Store Configuration
     |
     v
Connect to Configured Wi-Fi
```

## Firebase Integration

Firebase Realtime Database acts as the cloud data layer. The ESP32 uploads information associated with the configured Band ID.

The firmware/data structure may include fields such as:

| Field | Meaning |
|---|---|
| `heartRate` | Heart-rate value |
| `spo2` | Simulated placeholder in the current firmware; not a measured SpO₂ reading |
| `fallDetected` | Fall/emergency detection status |
| `steps` | Activity/step value, where implemented |
| `status` | Device or monitoring status |
| `temperature` | Temperature reading |
| `pressure` | Pressure reading |
| `humidity` | Humidity reading, where supported |
| `baroDropM` | Barometric height-change estimate |
| `baroConfirm` | Barometric confirmation status |
| `lastUpdated` | Last update timestamp |
| Sensor status | Sensor availability/status information |

The exact fields and update behavior depend on the current firmware implementation.

## Flutter Application

The Flutter application provides the mobile interface for family members. It is intended to support:

- Viewing user or wearable information.
- Viewing health-related and activity information.
- Displaying fall/emergency status.
- Supporting family monitoring.
- Displaying updated information from the backend/data layer.

Fall-detection computation is performed by the ESP32 firmware rather than by the Flutter application.

## BLE Provisioning

During initial setup, the ESP32 can receive configuration information over BLE.

The provisioning payload uses this field order:

```text
SSID | Wi-Fi Password | Firebase Email | Firebase Password | Band ID
```

The ESP32 stores the configuration in non-volatile storage and uses it to connect to the configured Wi-Fi network and Firebase.

**Security note:** Do not commit real Wi-Fi passwords, Firebase passwords, private keys, or other secrets to source control. Use secure configuration practices and appropriate Firebase database rules.

## Pin Configuration

| Sensor | Signal | ESP32 GPIO |
|---|---|---:|
| MPU6050 | SDA | 21 |
| MPU6050 | SCL | 22 |
| Pulse Sensor | Signal | 34 |
| BMP280/BME280 | SDA | 4 |
| BMP280/BME280 | SCL | 13 |

Check the actual board and sensor-module wiring before powering the device. Use the correct supply voltage and connect grounds appropriately.

## Project Structure

```text
SafeBand/
├── firmware/
│   ├── src/
│   │   └── main.cpp
│   ├── include/
│   │   ├── fall_model.h
│   │   └── firebase_config.h
│   └── platformio.ini
├── flutter_app/
│   ├── lib/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── widgets/
│   │   └── main.dart
│   └── pubspec.yaml
└── README.md
```

This tree reflects the project structure described here. Check file and directory names against the actual repository.

## Installation and Setup

### 1. Open the Project

Open the SafeBand repository in VS Code. Use PlatformIO for the firmware project and a Flutter-compatible development setup for the mobile application.

### 2. Configure the ESP32

- Connect the ESP32 to your computer.
- Select the correct board and serial port.
- Confirm that the PlatformIO environment matches your board.

### 3. Configure Firebase

- Create or configure a Firebase project.
- Enable Realtime Database.
- Configure appropriate database security rules and authentication.
- Supply the configuration required by the firmware without committing secrets to the repository.

### 4. Add the ML Model

Ensure the generated Random Forest model header is present at:

```text
firmware/include/fall_model.h
```

### 5. Connect the Sensors

Connect the MPU6050, Pulse Sensor, and BMP280/BME280 according to the pin table and the requirements of your specific modules.

### 6. Build and Upload the Firmware

Use PlatformIO to build the firmware and upload it to the ESP32. Check the serial output and resolve any build, sensor, or connection errors.

### 7. Configure the Wearable

Use the BLE provisioning flow to provide the Wi-Fi details, Firebase configuration/credentials, and Band ID.

### 8. Run the Flutter Application

Open the `flutter_app` directory, install its dependencies, and run the app on a supported Android device or emulator.

```bash
cd flutter_app
flutter pub get
flutter run
```

These commands assume the Flutter SDK is installed and the project is configured for the selected device.

## Data Flow

```text
MPU6050 ─────────────┐
Pulse Sensor ────────┼──> ESP32
BMP280/BME280 ───────┘      |
                            +--> Data Processing
                            +--> Random Forest Prediction
                            +--> Fall Confirmation
                            `--> Health/Environmental Monitoring
                                      |
                                      v
                                     Wi-Fi
                                      |
                                      v
                              Firebase Realtime DB
                                      |
                                      v
                                Flutter App
                                      |
                                      v
                                Family Member
```

## Emergency Flow

```text
Abnormal Motion Detected
          |
          v
ESP32 Processes Motion Data
          |
          v
ML Model Predicts Possible Fall
          |
          v
Additional Confirmation Checks
          |
          v
    +-----+------+
    |            |
    v            v
Not Confirmed  Confirmed Fall
    |            |
    v            v
Continue      Raise Emergency
Monitoring       Status
                   |
                   v
             Upload to Firebase
                   |
                   v
             Display in App
                   |
                   v
             Family Can Respond
```

## Limitations

- Cloud synchronization depends on Wi-Fi connectivity.
- Machine-learning predictions and confirmation checks can produce false positives or miss real falls.
- Sensor readings may be affected by hardware quality, placement, movement, calibration, and environmental conditions.
- The current SpO₂ field is simulated and is not a measured SpO₂ reading.
- Heart-rate readings depend on the analog Pulse Sensor and its signal quality.
- The system should not be relied upon as the sole means of emergency detection or communication.
- SafeBand is a prototype, not a certified medical device or a replacement for professional medical advice or emergency services.

## Future Enhancements

- Add GPS/location tracking.
- Add GSM/LTE communication for operation outside Wi-Fi coverage.
- Add a dedicated optical heart-rate and SpO₂ sensor.
- Add cloud push notifications.
- Add offline data buffering and synchronization.
- Improve the fall-detection dataset and model evaluation.
- Add battery-level monitoring.
- Improve power consumption.
- Add more detailed health and activity analytics.
- Add further emergency-response options.

## Safety Concept

**Sense → Process → Detect → Confirm → Communicate → Protect**

The wearable senses movement and related information, processes it locally, identifies possible falls, checks additional signals, communicates the result through Firebase, and presents the status in the mobile application.

## License

This project is described as an academic/prototype project for learning and research in IoT, machine learning, and wearable safety monitoring. Add a specific open-source license file if you intend to distribute the code under a formal license.

---

**SafeBand**  
*Wear it for the ones who care.*


**Version:** 1.0
