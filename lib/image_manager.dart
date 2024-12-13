// lib/image_manager.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ImageManager with ChangeNotifier {
  int _previousImageId = -1;
  int _previousPacketIndex = -1;
  List<int> _constructingData = [];

  Uint8List _imageData = Uint8List(0);
  Uint8List get imageData => _imageData;
  final StreamController<Uint8List> _imageDataController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get imageDataStream => _imageDataController.stream;

  List<DateTime> _receivedTimestamps = [];

  StreamSubscription<List<int>>? _subscription;
  Stream<List<int>> _dataStream;

  ImageManager(this._dataStream) {
    _subscription = _dataStream.listen(_onDataReceived);
  }

  // ストリームの更新（BLEConnectionManagerの接続が変更された場合に呼び出す）
  void updateStream(Stream<List<int>> newStream) {
    _subscription?.cancel();
    _dataStream = newStream;
    _subscription = _dataStream.listen(_onDataReceived);
  }

  void _onDataReceived(List<int> data) {
    if (data.length < 3) {
      print('Received data too short: ${data.length} bytes');
      return; // データ長の確認
    }

    int imageId = data[0];
    int packetIndex = data[1];
    List<int> payload = data.sublist(2);

    print(
        'Received packet - ImageID: $imageId, PacketIndex: $packetIndex, PayloadLength: ${payload.length}');

    if (packetIndex == 0) {
      if (imageId != _previousImageId) {
        // 新しい画像の開始
        if (_previousImageId != -1 && _constructingData.isNotEmpty) {
          _finalizeImage();
        }
        _previousImageId = imageId;
        _previousPacketIndex = 0;
        _constructingData = List.from(payload);
      } else {
        // 同じImageIDで再度PacketIndex=0を受信した場合は無視
        print('Duplicate PacketIndex=0 for ImageID=$imageId. Ignoring.');
      }
      return;
    }

    if (imageId == _previousImageId &&
        packetIndex == _previousPacketIndex + 1) {
      // 連続したパケット
      _previousPacketIndex = packetIndex;
      _constructingData.addAll(payload);
      return;
    }

    if (imageId == _previousImageId && packetIndex <= _previousPacketIndex) {
      // 重複または順序不整合のパケットを無視
      print('Duplicate or out-of-order packet received. Ignoring.');
      return;
    }

    // パケットロスとみなして画像を破棄
    print('Packet loss detected. Discarding image.');
    _previousImageId = -1;
    _previousPacketIndex = -1;
    _constructingData = [];
  }

  void _finalizeImage() {
    _imageData = Uint8List.fromList(_constructingData);
    print('Image data size = ${_imageData.length} bytes');

    // JPEG SOI (FFD8) と EOI (FFD9) の確認
    bool isValidJPEG = false;
    if (_imageData.length >= 4) {
      isValidJPEG = _imageData[0] == 0xFF &&
          _imageData[1] == 0xD8 &&
          _imageData[_imageData.length - 2] == 0xFF &&
          _imageData[_imageData.length - 1] == 0xD9;
      print('JPEG Validity: ${isValidJPEG ? "Valid" : "Invalid"}');
    }

    if (isValidJPEG) {
      if (!_imageDataController.isClosed) {
        _imageDataController.add(imageData);
        print('Image data added to stream.');
      } else {
        print('Attempted to add data to a closed StreamController.');
      }
    } else {
      print('Invalid JPEG data. Discarding image.');
    }

    DateTime now = DateTime.now();
    _receivedTimestamps.add(now);

    // 1秒以内のタイムスタンプをカウント
    _receivedTimestamps = _receivedTimestamps
        .where((timestamp) => now.difference(timestamp).inSeconds <= 1)
        .toList();

    // 画像データをクリア
    _constructingData.clear();
  }

  String _currentLabel = 'none';
  String get currentLabel => _currentLabel;

  void clearImageData() {
    _imageData = Uint8List(0);
    _currentLabel = 'none';
    _constructingData.clear();
    _previousImageId = -1;
    _previousPacketIndex = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _imageDataController.close();
    super.dispose();
  }
}
