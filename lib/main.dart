// src/main.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'ble_connection_manager.dart';
import 'image_manager.dart';
import 'prediction_provider.dart'; // プロバイダーをインポート

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
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

class HomePage extends HookConsumerWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleManager = ref.watch(bleConnectionManagerProvider);
    final imageDataAsyncValue = ref.watch(imageStreamProvider);
    final classificationAsyncValue = ref.watch(classificationProvider);

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
              child: imageDataAsyncValue.when(
                data: (imageData) {
                  if (imageData.isNotEmpty) {
                    return Image.memory(
                      imageData,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    );
                  } else {
                    return const Center(
                      child: Text('No image received yet'),
                    );
                  }
                },
                loading: () => const CircularProgressIndicator(),
                error: (err, stack) => Text('Error: $err'),
              ),
            ),
            const SizedBox(height: 20),
            classificationAsyncValue.when(
              data: (classification) => Text(
                'Prediction: $classification',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) {
                print('Prediction error: $err');
                return Text('Error: $err');
              },
            ),
          ],
        ),
      ),
    );
  }
}
