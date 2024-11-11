// src/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_connection_manager.dart';
import 'image_manager.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BLEConnectionManager>(
          create: (_) => BLEConnectionManager(),
        ),
        ChangeNotifierProxyProvider<BLEConnectionManager, ImageManager>(
          create: (_) => ImageManager(Stream.empty()),
          update: (_, bleManager, imageManager) =>
              imageManager!..updateStream(bleManager.dataStream),
        ),
      ],
      child: const MyApp(),
    ),
  );
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

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bleManager = Provider.of<BLEConnectionManager>(context);
    final imageManager = Provider.of<ImageManager>(context);

    Image? imageWidget;
    if (imageManager.imageData.isNotEmpty) {
      imageWidget = Image.memory(
        imageManager.imageData,
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
