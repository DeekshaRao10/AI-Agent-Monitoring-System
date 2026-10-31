import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../services/bluetooth_service.dart';
import '../services/bluetooth_device_manager.dart';
import '../services/wifi_scan_service.dart';
import '../widgets/device_tile.dart';


class ChangeWifiScreen extends StatefulWidget {
  final String deviceId;

  const ChangeWifiScreen({
    super.key,
    required this.deviceId,
  });

  @override
  State<ChangeWifiScreen> createState() => _ChangeWifiScreenState();
}

class _ChangeWifiScreenState extends State<ChangeWifiScreen> {
  final SafeBandBluetoothService bluetoothService =
      SafeBandBluetoothService();

  List<ScanResult> devices = [];
  bool scanning = true;

  // True once we've kicked off an auto-connect attempt, so the scan
  // listener doesn't try to connect a second time.
  bool autoConnectAttempted = false;
  bool connectFailed = false;

  BluetoothDevice? connectedDevice;
  bool loadingWifiList = false;
  List<String> wifiNetworks = [];
  List<String> savedNetworks = [];
  String? selectedWifi;
  bool sending = false;

  final wifiPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  void dispose() {
    wifiPasswordController.dispose();
    super.dispose();
  }

  Future<void> requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> startScan() async {
    await requestBlePermissions();

    if (mounted) {
      setState(() {
        scanning = true;
        devices = [];
        connectFailed = false;
        autoConnectAttempted = false;
      });
    }

    await bluetoothService.startScan();

    bluetoothService.scanResults.listen((results) {
      if (!mounted) return;

      final filtered =
          results.where((r) => r.device.platformName.isNotEmpty).toList();

      setState(() => devices = filtered);

      // Skip manual selection: as soon as the band shows up, connect to
      // it automatically and jump straight to the WiFi form. The list
      // below only appears as a fallback if this doesn't find a match.
      if (!autoConnectAttempted && connectedDevice == null) {
        final match = filtered.where(
          (r) => r.device.platformName.toLowerCase().startsWith('safeband'),
        );

        if (match.isNotEmpty) {
          autoConnectAttempted = true;
          bluetoothService.stopScan();
          connectDevice(match.first.device);
        }
      }
    });

    await Future.delayed(const Duration(seconds: 5));

    await bluetoothService.stopScan();

    if (mounted) {
      setState(() {
        scanning = false;
        // Auto-connect never found a matching band within the scan
        // window — fall back to letting the user pick manually.
        if (connectedDevice == null && !autoConnectAttempted) {
          connectFailed = true;
        }
      });
    }
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    try {
      await device.connect();

      BluetoothDeviceManager.connectedDevice = device;

      if (!mounted) return;

      setState(() {
        connectedDevice = device;
        loadingWifiList = true;
        connectFailed = false;
      });

      final wifiService = WifiScanService();
      final wifiList = await wifiService.getWifiList(device);
      final saved = await wifiService.getSavedNetworks(device);

      if (!mounted) return;

      setState(() {
        wifiNetworks = wifiList
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        savedNetworks = saved
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        loadingWifiList = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        autoConnectAttempted = false;
        connectFailed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Connection failed")),
      );
    }
  }

  Future<void> updateWifi() async {
    if (connectedDevice == null) return;

    if (selectedWifi == null || wifiPasswordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select a network and enter its password")),
      );
      return;
    }

    setState(() => sending = true);

    try {

      final sent = await WifiScanService().sendWifiCredentials(
        connectedDevice!,
        selectedWifi!,
        wifiPasswordController.text.trim(),
        '',
        '',
        widget.deviceId,
      );

      if (!mounted) return;

      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("WiFi updated. Band is restarting and reconnecting..."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to send new WiFi details")),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String signalText(int rssi) {
    if (rssi > -70) return "Strong Signal";
    if (rssi > -85) return "Medium Signal";
    return "Weak Signal";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text("Change WiFi"),
        actions: connectedDevice == null
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: startScan,
                ),
              ]
            : null,
      ),
      body: connectedDevice == null
          ? _buildScanBody()
          : _buildWifiSelectBody(),
    );
  }

  Widget _buildScanBody() {
    // Still searching, or found a match and connecting to it — show a
    // single "connecting" state instead of a device list.
    if (!connectFailed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                "Connecting to your band...",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                "Make sure it's charged and nearby.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Fallback: auto-connect couldn't find/connect to a band — let the
    // user pick manually instead of getting stuck.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const Text(
            "Couldn't connect automatically. Select your band below.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (scanning)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text("Searching..."),
              ],
            ),
          const SizedBox(height: 10),
          Expanded(
            child: scanning
                ? const SizedBox()
                : devices.isEmpty
                    ? const Center(
                        child: Text(
                          "No devices found.\nTap refresh to scan again.",
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final result = devices[index];

                          return DeviceTile(
                            deviceName: result.device.platformName,
                            signal: signalText(result.rssi),
                            onPair: () => connectDevice(result.device),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiSelectBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Connected. Select the new WiFi network:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),

          if (!loadingWifiList && savedNetworks.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        "Already saved on this band (${savedNetworks.length})",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    savedNetworks.join(", "),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
          ],

          if (loadingWifiList) const Center(child: CircularProgressIndicator()),

          if (!loadingWifiList)
            DropdownButtonFormField<String>(
              value: selectedWifi,
              hint: const Text("Select WiFi"),
              decoration: const InputDecoration(
                labelText: "Select WiFi",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              items: wifiNetworks
                  .map((wifi) => DropdownMenuItem(
                        value: wifi,
                        child: Text(wifi),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => selectedWifi = value),
            ),

          const SizedBox(height: 12),

          AppTextField(
            controller: wifiPasswordController,
            obscureText: true,
            labelText: "Password",
          ),

          const SizedBox(height: 30),

          PrimaryButton(
            text: sending ? "Updating..." : "Update WiFi",
            onPressed: sending ? null : updateWifi,
          ),
        ],
      ),
    );
  }
}