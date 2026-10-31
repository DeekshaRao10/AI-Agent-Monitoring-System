import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../services/bluetooth_service.dart';
import '../services/bluetooth_device_manager.dart';
import '../widgets/device_tile.dart';
import 'pair_setup_screen.dart';

class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key});

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  final SafeBandBluetoothService bluetoothService =
      SafeBandBluetoothService();

  List<ScanResult> devices = [];
  bool scanning = true;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  Future<void> requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> startScan() async {
    print("START SCAN CALLED");

    await requestBlePermissions();

    if (mounted) {
      setState(() {
        scanning = true;
        devices = [];
      });
    }

    await bluetoothService.startScan();

    bluetoothService.scanResults.listen((results) {
      print("Total Devices: ${results.length}");

      if (mounted) {
        setState(() {
          devices = results
              .where(
                (r) => r.device.platformName.isNotEmpty,
              )
              .toList();
        });
      }
    });

    await Future.delayed(const Duration(seconds: 5));

    await bluetoothService.stopScan();

    if (mounted) {
      setState(() {
        scanning = false;
      });
    }
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    try {
      await device.connect();

      BluetoothDeviceManager.connectedDevice = device;

      print("Connected Device ID: ${device.remoteId.str}");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${device.platformName} Connected Successfully",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PairSetupScreen(
            deviceId: device.remoteId.str,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Connection Failed"),
        ),
      );
    }
  }

  String signalText(int rssi) {
    if (rssi > -70) {
      return "Strong Signal";
    } else if (rssi > -85) {
      return "Medium Signal";
    }
    return "Weak Signal";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text("Add your SafeBand"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await startScan();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            const Text(
              "Make sure the band is charged and nearby.",
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 25),

            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.watch,
                size: 60,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 25),

            const SizedBox(height: 20),

            if (!scanning && devices.isNotEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "FOUND DEVICES",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            if (!scanning && devices.isNotEmpty)
              const SizedBox(height: 10),

            Expanded(
              child: scanning
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text("Searching..."),
                        ],
                      ),
                    )
                  : devices.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_disabled,
                                size: 70,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "No devices found",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Make sure your SafeBand is\npowered on and nearby.\nTap Refresh to scan again.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (context, index) {
                            final result = devices[index];

                            return DeviceTile(
                              deviceName:
                                  result.device.platformName,
                              signal: signalText(result.rssi),
                              onPair: () {
                                connectDevice(result.device);
                              },
                            );
                          },
                        ),
            ),

            
          ],
        ),
      ),
    );
  }
}