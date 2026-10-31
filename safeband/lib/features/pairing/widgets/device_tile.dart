import 'package:flutter/material.dart';

class DeviceTile extends StatelessWidget {
  final String deviceName;
  final String signal;
  final VoidCallback onPair;

  const DeviceTile({
    super.key,
    required this.deviceName,
    required this.signal,
    required this.onPair,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.watch),
        ),
        title: Text(deviceName),
        subtitle: Text(signal),
        trailing: ElevatedButton(
          onPressed: onPair,
          child: const Text("Pair"),
        ),
      ),
    );
  }
}