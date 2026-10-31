import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SafeBandBluetoothService { 
   Future<void> startScan() async {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Stream<List<ScanResult>> get scanResults =>
      FlutterBluePlus.scanResults;
}