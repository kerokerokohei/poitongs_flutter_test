// src/main.dart
import 'package:flutter/material.dart';
import 'ble_manager.dart';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Image Receiver',
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BLEManager bleManager = BLEManager();

  @override
  void initState() {
    super.initState();
    bleManager.addListener(_updateUI);
    bleManager.connectToDevice();
  }

  @override
  void dispose() {
    bleManager.removeListener(_updateUI);
    bleManager.disconnect();
    super.dispose();
  }

  void _updateUI() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Image? imageWidget;
    if (bleManager.imageData.isNotEmpty) {
      imageWidget = Image.memory(
        bleManager.imageData,
        gaplessPlayback: true,
        fit: BoxFit.contain,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Image Receiver'),
      ),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              'Connection Status: ${bleManager.isConnected ? 'Connected' : 'Disconnected'}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: imageWidget ??
                  const Center(
                    child: Text('No image received yet'),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
