import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WifiScanService {
  static const String serviceUuid =
      "12345678-1234-1234-1234-123456789001";

  static const String wifiListUuid =
      "12345678-1234-1234-1234-123456789002";

  static const String wifiWriteUuid =
      "12345678-1234-1234-1234-123456789003";

  static const String savedNetworksUuid =
      "12345678-1234-1234-1234-123456789004";

  /// SSIDs the band already has saved (not just what it's connected to
  /// right now) — lets the UI confirm an older network wasn't dropped
  /// when a new one gets added via Change WiFi.
  Future<List<String>> getSavedNetworks(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();

    for (BluetoothService service in services) {
      if (service.uuid.toString() != serviceUuid) continue;

      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.uuid.toString() != savedNetworksUuid) continue;

        List<int> value = await characteristic.read();
        String raw = String.fromCharCodes(value).trim();

        if (raw.isEmpty) return [];
        return raw.split(",");
      }
    }

    return [];
  }

Future<List<String>> getWifiList(
    BluetoothDevice device) async {

  List<BluetoothService> services =
      await device.discoverServices();

  print("Services Found: ${services.length}");

  for (BluetoothService service in services) {

    print("Service: ${service.uuid}");

    if (service.uuid.toString() == serviceUuid) {

      for (BluetoothCharacteristic characteristic
          in service.characteristics) {

        print("Characteristic: ${characteristic.uuid}");

        if (characteristic.uuid.toString() ==
            wifiListUuid) {

          List<int> value =
              await characteristic.read();

          print("Raw Bytes: $value");

          String wifiString =
              String.fromCharCodes(value);

          print("WiFi String:");
          print(wifiString);

          if (wifiString.trim().isEmpty) {
            return [];
          }

          return wifiString.split(",");
        }
      }
    }
  }

  return [];
}
 Future<bool> sendWifiCredentials(
  BluetoothDevice device,
  String ssid,
  String password,
  String firebaseEmail,
  String firebasePassword,
  String bandId,
) async {

  print("===== sendWifiCredentials() CALLED =====");

  List<BluetoothService> services =
      await device.discoverServices();

  print("Services found: ${services.length}");

  for (BluetoothService service in services) {

    print("Service: ${service.uuid}");

    if (service.uuid.toString() == serviceUuid) {

      for (BluetoothCharacteristic characteristic
          in service.characteristics) {

        print("Characteristic: ${characteristic.uuid}");

        if (characteristic.uuid.toString() == wifiWriteUuid) {

          String data =
              "$ssid|$password|$firebaseEmail|$firebasePassword|$bandId";

          print("Writing:");
          print(data);

          try {
  await characteristic.write(
    data.codeUnits,
    withoutResponse: false,
  );

  print("Write completed!");
} catch (e) {
  print("BLE disconnected after write (expected): $e");
}

// Give ESP32 time to reboot
await Future.delayed(const Duration(seconds: 2));

return true;
        }
      }
    }
  }

  print("Write characteristic not found");

  return false;
}
}