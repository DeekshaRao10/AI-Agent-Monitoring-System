🛡️ SafeBand

💚 Smart Wearable for Safety and Health Monitoring

SafeBand is an IoT-based smart wearable system designed to monitor a person's movement and basic health information, detect possible falls using Machine Learning, and help family members respond quickly through a Flutter mobile application.


✨ Project Overview

SafeBand combines wearable sensors, an ESP32 microcontroller, Machine Learning, Wi-Fi, Firebase Realtime Database, Bluetooth Low Energy (BLE), and a Flutter mobile application into one safety-monitoring system.

The wearable collects movement and health-related information. The ESP32 processes the sensor readings locally and performs fall detection using a Random Forest model. When a possible fall is detected, the system performs additional confirmation checks such as impact, wrist rotation, stillness, and barometric change to reduce false alarms. Confirmed emergency information is then uploaded to Firebase through Wi-Fi, where it can be accessed by the Flutter application.

🔗 Overall System

👤 Wearer
   │
   ▼
⌚ SafeBand Sensors
   │
   ▼
🧠 ESP32
   │
   ├── 🧠 ML Fall Detection
   ├── ❤️ Heart-Rate Monitoring
   ├── 🌡️ Environmental Monitoring
   └── 🔵 BLE Provisioning
   │
   ▼
📶 Wi-Fi
   │
   ▼
☁️ Firebase Realtime Database
   │
   ▼
📱 Flutter Mobile Application
   │
   ▼
👨‍👩‍👧 Family Member

🎯 Objectives

🛡️ Improve wearable-based personal safety.

🧠 Detect possible falls using Machine Learning.

❤️ Monitor basic health-related information.

📊 Collect and store sensor information.

☁️ Synchronize wearable data with Firebase.

📱 Provide family members with a mobile monitoring interface.

🚨 Provide an emergency status when a fall is confirmed.

🔵 Simplify initial wearable configuration using BLE.

⭐ Key Features

🧠 Machine Learning Fall Detection

Uses a Random Forest classifier running on the ESP32 to classify motion data.

📈 Motion Monitoring

The MPU6050 accelerometer and gyroscope continuously monitor movement.

❤️ Heart-Rate Monitoring

The current firmware uses an analog Pulse Sensor for heart-rate monitoring.

🌡️ Environmental Monitoring

The BMP280/BME280 sensor provides pressure and temperature information and, where supported, humidity information.

🚨 Emergency Detection

A possible fall is further checked using multiple motion and environmental signals before an emergency state is raised.

☁️ Cloud Synchronization

Sensor and emergency information can be uploaded to Firebase Realtime Database through Wi-Fi.

📱 Flutter Application

The mobile application provides the family-side interface for monitoring the wearable.

🔵 BLE Provisioning

Bluetooth Low Energy is used for initial configuration of Wi-Fi, Firebase information, and the Band ID.

🏗️ System Architecture

┌───────────────────────────────────────────────┐
│              ⌚ SafeBand Wearable             │
│                                               │
│  MPU6050  │  Pulse Sensor  │  BMP280/BME280  │
└──────────────────────┬────────────────────────┘
                       │
                       ▼
┌───────────────────────────────────────────────┐
│                  🧠 ESP32                     │
│                                               │
│  • Sensor Data Acquisition                    │
│  • Feature Extraction                         │
│  • Random Forest Fall Detection               │
│  • Fall Confirmation                          │
│  • Health Monitoring                          │
│  • BLE Provisioning                            │
└──────────────────────┬────────────────────────┘
                       │
                       │ 📶 Wi-Fi
                       ▼
┌───────────────────────────────────────────────┐
│              ☁️ Firebase                      │
│                                               │
│  • Realtime Database                          │
│  • Sensor Data                                │
│  • Band Status                                │
│  • Fall / Emergency Status                   │
└──────────────────────┬────────────────────────┘
                       │
                       ▼
┌───────────────────────────────────────────────┐
│              📱 Flutter App                   │
│                                               │
│  • Health Information                         │
│  • Fall Status                                │
│  • Family Monitoring                          │
└──────────────────────┬────────────────────────┘
                       │
                       ▼
                 👨‍👩‍👧 Family Member

🔄 Working Flow

1️⃣ Sensors collect data
          ↓
2️⃣ ESP32 receives sensor readings
          ↓
3️⃣ Motion data is processed
          ↓
4️⃣ Features are extracted
          ↓
5️⃣ Random Forest predicts possible fall
          ↓
6️⃣ Additional fall confirmation is performed
          ↓
7️⃣ Emergency state is raised if confirmed
          ↓
8️⃣ ESP32 connects to Firebase through Wi-Fi
          ↓
9️⃣ Data is stored in Realtime Database
          ↓
🔟 Flutter application displays the information
          ↓
🚨 Family member can respond to the emergency

🧠 Fall Detection

SafeBand uses the MPU6050 to obtain acceleration and gyroscope information. The ESP32 maintains a rolling motion window and calculates a 22-feature vector from the motion data.

📊 Extracted Features

The feature set includes:

Mean

Standard deviation

Minimum value

Maximum value

Range

25th percentile

75th percentile

Skewness

Kurtosis

RMS

Axis-specific statistics for X, Y and Z

These features are passed to the Random Forest model deployed in:

fall_model.h

🚨 Fall Confirmation

The system does not rely only on the ML prediction. It also checks additional evidence such as:

🟢 Sustained Free-Fall
        +
🔴 Impact
        +
🔄 Wrist Rotation
        +
🧍 Post-Impact Stillness
        +
📉 Barometric Height Change
        ↓
🚨 Confirmed Fall

This multi-stage approach is intended to reduce false fall detections.

🔧 Hardware Components

🔩 Component

🎯 Purpose

🧠 ESP32

Main controller, processing and communication

📐 MPU6050

Accelerometer + gyroscope for motion/fall detection

❤️ Pulse Sensor

Analog heart-rate monitoring

🌡️ BMP280/BME280

Temperature, pressure and environmental monitoring

🔋 Battery/Power Supply

Portable power for the wearable

💻 Software & Technologies

💻 Technology

🔧 Usage

C/C++

ESP32 firmware

Arduino Framework

Embedded development

PlatformIO

Firmware development/build environment

ESP32

Edge processing

Random Forest

Fall classification

Flutter

Mobile application

Dart

Flutter application development

Firebase Realtime Database

Cloud data storage

Wi-Fi

Cloud communication

BLE

Initial device provisioning

I²C

Sensor communication

GPIO

Pulse Sensor and hardware connections

📡 Communication

SafeBand uses two main wireless communication methods:

📶 Wi-Fi

Wi-Fi is used by the ESP32 to:

Connect to the configured network.

Authenticate with Firebase.

Upload sensor data.

Upload fall and emergency status.

🔵 Bluetooth Low Energy (BLE)

BLE is used primarily for initial device provisioning.

📱 Mobile Device
      │
      │ 🔵 BLE
      ▼
🧠 ESP32
      │
      ▼
💾 Store Configuration
      │
      ▼
📶 Connect to Wi-Fi

☁️ Firebase Integration

Firebase Realtime Database acts as the cloud backend for SafeBand.

The ESP32 authenticates with Firebase and uploads information associated with the configured Band ID.

📊 Typical Data

❤️ heartRate
🫁 spo2
🚨 fallDetected
👣 steps
📌 status
🌡️ temperature
💨 pressure
💧 humidity
📉 baroDropM
🔍 baroConfirm
⏱️ lastUpdated
🔧 sensor status

⚠️ Current SpO₂ Implementation

The current firmware contains an SpO₂ field, but the value is a simulated placeholder. The current hardware uses an analog Pulse Sensor rather than a dedicated red/infrared optical SpO₂ sensor.

📱 Flutter Application

The Flutter application provides the mobile interface for the family member.

The application can be used to:

👤 Manage/view user information.

📊 View wearable health/activity information.

🚨 Display fall/emergency status.

👨‍👩‍👧 Support family monitoring.

🔄 Receive updated information from the backend.

The Flutter application communicates with the backend/data layer rather than directly performing the fall-detection computation.

🔵 BLE Provisioning

During initial setup, the ESP32 can receive configuration information through BLE.

The provisioning data follows the format:

SSID | Wi-Fi Password | Firebase Email | Firebase Password | Band ID

The ESP32 stores the configuration using non-volatile storage and uses it to connect to the configured network and Firebase.

📌 Pin Configuration

📐 MPU6050

SDA → GPIO 21
SCL → GPIO 22

❤️ Pulse Sensor

Signal → GPIO 34

🌡️ BMP280/BME280

SDA → GPIO 4
SCL → GPIO 13

💡 Note: Use the appropriate supply voltage for the sensor modules and connect the grounds correctly.

📂 Project Structure

SafeBand/
│
├── 📁 firmware/
│   ├── 📁 src/
│   │   └── main.cpp
│   │
│   ├── 📁 include/
│   │   ├── fall_model.h
│   │   └── firebase_config.h
│   │
│   └── platformio.ini
│
├── 📁 flutter_app/
│   ├── 📁 lib/
│   │   ├── 📁 screens/
│   │   ├── 📁 services/
│   │   ├── 📁 widgets/
│   │   └── main.dart
│   │
│   └── pubspec.yaml
│
└── README.md

⚙️ Installation & Setup

1️⃣ Clone / Open the Project

Open the SafeBand project in VS Code with PlatformIO or the appropriate Arduino development environment.

2️⃣ Configure ESP32

Connect the ESP32 and select the correct board and serial port.

3️⃣ Configure Firebase

Create/configure the Firebase project and Realtime Database, then provide the required Firebase configuration used by the firmware.

4️⃣ Add ML Model

Place the generated Random Forest model header file in the firmware include directory:

fall_model.h

5️⃣ Connect Sensors

Connect the MPU6050, Pulse Sensor, and BMP280/BME280 according to the pin configuration.

6️⃣ Upload Firmware

Build and upload the firmware to the ESP32.

7️⃣ Configure the Wearable

Use BLE provisioning to provide:

Wi-Fi
Firebase credentials
Band ID

8️⃣ Run Flutter Application

Install Flutter dependencies and run the application on an Android device or emulator.

📊 Data Flow

       📐 MPU6050
           │
       ❤️ Pulse Sensor
           │
       🌡️ BMP/BME280
           │
           ▼
      ┌───────────┐
      │  🧠 ESP32  │
      └─────┬─────┘
            │
            ├── 📊 Data Processing
            │
            ├── 🧠 Random Forest
            │
            ├── 🚨 Fall Confirmation
            │
            └── ❤️ Health Monitoring
            │
            ▼
        📶 Wi-Fi
            │
            ▼
    ☁️ Firebase RTDB
            │
            ▼
      📱 Flutter App
            │
            ▼
    👨‍👩‍👧 Family Member

🚨 Emergency Flow

⌚ Wearable detects abnormal motion
              ↓
🧠 ESP32 processes motion data
              ↓
🤖 ML model predicts possible fall
              ↓
🔍 Additional evidence is checked
              ↓
       ┌──────┴──────┐
       │             │
    ❌ Not Fall    🚨 Fall
       │             │
       ▼             ▼
   Continue       Emergency
   Monitoring       State
                     │
                     ▼
                  📶 Wi-Fi
                     │
                     ▼
                ☁️ Firebase
                     │
                     ▼
                📱 Flutter
                     │
                     ▼
              👨‍👩‍👧 Family

⚠️ Limitations

📶 Cloud synchronization depends on Wi-Fi connectivity.

🧠 ML predictions can contain errors.

📡 Sensor readings can be affected by hardware/environmental conditions.

🫁 The current SpO₂ value is simulated and is not a measured SpO₂ reading.

🏥 SafeBand is a prototype/project system and should not be considered a medical device or a replacement for professional medical or emergency services.

🚀 Future Enhancements

📍 Add GPS/location tracking.

📡 Add GSM/LTE communication for operation outside Wi-Fi coverage.

❤️ Add a dedicated optical heart-rate and SpO₂ sensor.

🔔 Add cloud push notifications.

💾 Add offline data buffering and synchronization.

🧠 Improve the fall-detection dataset and model evaluation.

🔋 Add battery-level monitoring.

⚡ Improve power optimization.

📊 Add detailed health and activity analytics.

🆘 Add more emergency response options.

🛡️ Safety Concept

SafeBand follows a simple concept:

Sense → Process → Detect → Confirm → Communicate → Protect

The wearable senses the user's condition, processes the information locally, detects possible falls, confirms the event using multiple signals, communicates the result through Firebase, and provides information to the family through the mobile application.

📜 License

This project is developed as an academic/prototype project for learning, research, IoT development, Machine Learning, and wearable safety monitoring.

💚 SafeBand

“Wear it for the ones who care.”

Sensors → ESP32 → ML Fall Detection → Wi-Fi → Firebase → Flutter App → Family Member

📌 Version

Version 1.0