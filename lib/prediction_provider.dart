// lib/PredictionProvider.dart
import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'ble_connection_manager.dart';
import 'image_manager.dart';
import 'predict.dart';

// BLEConnectionManagerプロバイダー
final bleConnectionManagerProvider =
    ChangeNotifierProvider<BLEConnectionManager>((ref) {
  return BLEConnectionManager();
});

// ImageManagerプロバイダー
final imageManagerProvider = Provider<ImageManager>((ref) {
  final bleManager = ref.watch(bleConnectionManagerProvider);

  final imageManager = ImageManager(bleManager.dataStream);

  // アプリ終了時にリソースを解放
  ref.onDispose(() {
    imageManager.dispose();
  });

  return imageManager;
});

// Predictプロバイダー
final predictProvider = Provider<Predict>((ref) {
  return Predict();
});

// 画像データのストリームプロバイダー
final imageStreamProvider = StreamProvider<Uint8List>((ref) {
  final imageManager = ref.watch(imageManagerProvider);
  return imageManager.imageDataStream;
});

// 画像ストリームと分類結果を管理するプロバイダー
final classificationProvider = StreamProvider.autoDispose<String>((ref) async* {
  final imageManager = ref.watch(imageManagerProvider);
  final predict = ref.watch(predictProvider);

  await for (final imageData in imageManager.imageDataStream) {
    try {
      final classificationResult = await predict.predictImage(imageData);
      print("Classification result: $classificationResult");
      yield classificationResult;
    } catch (e, stack) {
      // エラーをログに記録
      print("Error in predict.predictImage: $e");
      // 必要に応じて特別な値を返す
      yield 'error';
    }
  }
});
