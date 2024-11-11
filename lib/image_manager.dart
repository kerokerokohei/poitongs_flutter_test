// src/image_manager.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ImageManager with ChangeNotifier {
  int _previousImageId = -1;
  int _previousPacketIndex = -1;
  List<int> _constructingData = [];

  Uint8List _imageData = Uint8List(0);
  Uint8List get imageData => _imageData;

  List<DateTime> _receivedTimestamps = [];

  StreamSubscription<List<int>>? _subscription;

  ImageManager(Stream<List<int>> dataStream) {
    _subscription = dataStream.listen(_onDataReceived);
  }

  // ストリームの更新（BLEConnectionManagerの接続が変更された場合に呼び出す）
  void updateStream(Stream<List<int>> newStream) {
    _subscription?.cancel();
    _subscription = newStream.listen(_onDataReceived);
  }

  void _onDataReceived(List<int> data) {
    if (data.length < 3) return; // データ長の確認

    int imageId = data[0];
    int packetIndex = data[1];
    List<int> payload = data.sublist(2);

    if (_previousImageId == imageId &&
        _previousPacketIndex + 1 == packetIndex) {
      _previousPacketIndex = packetIndex;
      _constructingData.addAll(payload);
      return;
    }

    if (_previousImageId != imageId && packetIndex == 0) {
      if (_previousImageId != -1) {
        _imageData = Uint8List.fromList(_constructingData);
        print('Image data size = ${_imageData.length} bytes');
        notifyListeners();

        DateTime now = DateTime.now();
        _receivedTimestamps.add(now);

        // 1秒以内のタイムスタンプをカウント
        _receivedTimestamps = _receivedTimestamps
            .where((timestamp) => now.difference(timestamp).inSeconds <= 1)
            .toList();
      }
      _previousImageId = imageId;
      _previousPacketIndex = packetIndex;
      _constructingData = List.from(payload);
      return;
    }

    print('Packet loss detected. Discarding image.');
    _previousImageId = -1;
    _previousPacketIndex = -1;
    _constructingData = [];
  }

  void clearImageData() {
    _imageData = Uint8List(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
