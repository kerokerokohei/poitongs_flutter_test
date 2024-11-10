// src/ble_manager.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BLEManager with ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;

  final Guid uartServiceUUID = Guid('B2D9943D-4D14-C967-F2BF-2F145CA909FD');
  final Guid txCharacteristicUUID =
      Guid('B2D9943D-4D14-C967-F2BF-2F145CA909FD');
  final Guid rxCharacteristicUUID =
      Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');

  int previousImageId = -1;
  int previousPacketIndex = -1;
  List<int> constructingData = [];

  Uint8List imageData = Uint8List(0);
  bool isConnected = false;

  List<DateTime> receivedTimestamps = [];

  // ターゲットとなるBLE MACアドレス（大文字に統一）
  final String targetMACAddress = '3A:32:37:3A:65:32';
// 48:27:E2:E7:65:71
  // スキャンの再試行に使用するタイマー
  Timer? _scanRetryTimer;

  // コンストラクタ
  BLEManager() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        isConnected = false;
        notifyListeners();
        print('Bluetooth is not powered on.');
        _disconnectDevice();
      } else if (state == BluetoothAdapterState.on) {
        // Bluetoothが有効になったら接続を開始
        print("start connectToDevice");
        connectToDevice();
      }
    });
  }

  void connectToDevice() {
    // スキャンを開始
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)).then((_) {
      print('Scan timeout reached.');
      _retryScan();
    });

    // スキャン結果をリッスン
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        final device = result.device;
        final advertisementData = result.advertisementData;

        print('Discovered name：${device.name} Id：(${device.id.id})');

        if (defaultTargetPlatform == TargetPlatform.android) {
          // Androidの場合、MACアドレスでデバイスを特定
          if (device.id.id.toUpperCase() == targetMACAddress.toUpperCase()) {
            FlutterBluePlus.stopScan();
            _connectToDevice(device);
            _cancelScanRetry();
            break;
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          // iOSの場合、Manufacturer DataからMACアドレスを取得
          // Manufacturer Dataが存在するか確認
          if (advertisementData.manufacturerData.isNotEmpty) {
            // Manufacturer Dataの最初のエントリを取得（通常は1つ）
            final manufacturerData =
                advertisementData.manufacturerData.values.first;

            // MACアドレスが含まれていると仮定（6バイト）
            if (manufacturerData.length >= 6) {
              // 最初の6バイトをMACアドレスとして取得
              final macBytes = manufacturerData.sublist(0, 6);
              final macAddress = _bytesToMacAddress(macBytes);

              print(
                  'Extracted MAC Address from Manufacturer Data: $macAddress');

              if (macAddress == targetMACAddress.toUpperCase()) {
                print("catch target device");
                FlutterBluePlus.stopScan();
                _connectToDevice(device);
                _cancelScanRetry();
                break;
              }
            } else {
              print(
                  'Manufacturer Data does not contain enough bytes for MAC address.');
            }
          } else {
            print('No Manufacturer Data found in advertisement.');
          }
        }
      }
    });
  }

  String _bytesToMacAddress(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  void _connectToDevice(BluetoothDevice device) async {
    _connectedDevice = device;

    try {
      // 接続を開始
      await device.connect();
      isConnected = true;
      notifyListeners();
      print('Connected to ${device.name}');

      // サービスを探索
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid == uartServiceUUID) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid == txCharacteristicUUID) {
              _txCharacteristic = characteristic;
              await _setNotification(_txCharacteristic!);
            } else if (characteristic.uuid == rxCharacteristicUUID) {
              _rxCharacteristic = characteristic;
            }
          }
        }
      }

      // 接続状態の監視
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          isConnected = false;
          notifyListeners();
          print('Disconnected from device');
          _disconnectDevice();
          _retryScan();
        }
      });
    } catch (e) {
      print('Error connecting to device: $e');
      isConnected = false;
      notifyListeners();
      _retryScan();
    }
  }

  Future<void> _setNotification(BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);
    characteristic.value.listen((value) {
      _onDataReceived(value);
    });
  }

  void _onDataReceived(List<int> data) {
    if (data.length < 3) return; // データ長の確認

    int imageId = data[0];
    int packetIndex = data[1];
    List<int> payload = data.sublist(2);

    print(
        'Image ID: $imageId, Packet Index: $packetIndex, Payload: ${payload.length} bytes');
    print(
        'Previous Image ID: $previousImageId, Previous Packet Index: $previousPacketIndex');
    print('Data: ${data.length} bytes');
    print('');

    if (previousImageId == imageId && previousPacketIndex + 1 == packetIndex) {
      previousPacketIndex = packetIndex;
      constructingData.addAll(payload);
      return;
    }

    if (previousImageId != imageId && packetIndex == 0) {
      if (previousImageId != -1) {
        imageData = Uint8List.fromList(constructingData);
        print('Image data size = ${imageData.length} bytes');
        notifyListeners();

        DateTime now = DateTime.now();
        receivedTimestamps.add(now);

        // 1秒以内のタイムスタンプをカウント
        receivedTimestamps = receivedTimestamps
            .where((timestamp) => now.difference(timestamp).inSeconds <= 1)
            .toList();
        print(
            'Images received in the last second: ${receivedTimestamps.length}');
      }
      previousImageId = imageId;
      previousPacketIndex = packetIndex;
      constructingData = List.from(payload);
      return;
    }

    print('Packet loss detected. Discarding image.');
    previousImageId = -1;
    previousPacketIndex = -1;
    constructingData = [];
  }

  void disconnect() {
    if (_connectedDevice != null) {
      _connectedDevice!.disconnect();
      _connectedDevice = null;
      isConnected = false;
      notifyListeners();
    }
  }

  void _disconnectDevice() {
    if (_connectedDevice != null) {
      disconnect();
    }
  }

  void _retryScan() {
    if (_scanRetryTimer != null && _scanRetryTimer!.isActive) return;

    print('Retrying scan in 5 seconds...');
    _scanRetryTimer = Timer(const Duration(seconds: 5), () {
      if (!isConnected) {
        connectToDevice();
      }
    });
  }

  void _cancelScanRetry() {
    if (_scanRetryTimer != null) {
      _scanRetryTimer!.cancel();
      _scanRetryTimer = null;
    }
  }
}
