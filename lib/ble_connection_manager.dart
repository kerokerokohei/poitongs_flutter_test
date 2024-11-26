// src/ble_connection_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

class BLEConnectionManager with ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  bool _isConnected = false;

  // サービスUUIDとキャラクタリスティックUUIDをデバイスに合わせて設定
  final Guid uartServiceUUID =
      Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'); // UARTサービスUUID
  final Guid txCharacteristicUUID =
      Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // TXキャラクタリスティックUUID
  final Guid rxCharacteristicUUID =
      Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // RXキャラクタリスティックUUID

  // ターゲットMACアドレス
  final String targetMACAddress = '48:27:E2:E7:65:71';

  // 受信データ用のStreamController
  final StreamController<List<int>> _dataController =
      StreamController.broadcast();

  Future<void> requestPermissions() async {
    // Bluetooth スキャンと接続に必要なパーミッション
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isDenied ||
        statuses[Permission.bluetoothConnect]!.isDenied ||
        statuses[Permission.location]!.isDenied) {
      // パーミッションが拒否された場合の処理
      // 例: ユーザーに再度パーミッションを要求するダイアログを表示
    }
  }

  Stream<List<int>> get dataStream => _dataController.stream;

  // スキャン再試行用タイマー
  Timer? _scanRetryTimer;

  BLEConnectionManager() {
    // パーミッションのリクエスト
    requestPermissions().then((_) {
      FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.off) {
          _isConnected = false;
          notifyListeners();
          print('Bluetooth is powered off.');
          _disconnectDevice();
        } else if (state == BluetoothAdapterState.on) {
          print("Bluetooth is powered on. Starting scan...");
          connectToDevice();
        }
      });
    });
  }

  bool get isConnected => _isConnected;

  BluetoothDevice? get connectedDevice => _connectedDevice;

  void connectToDevice() {
    // スキャン開始
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)).then((_) {
      print('Scan timeout reached.');
      _retryScan();
    });

    // スキャン結果のリッスン
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        final device = result.device;
        final advertisementData = result.advertisementData;

        print('Discovered device: Name=${device.name}, ID=${device.id.id}');

        if (defaultTargetPlatform == TargetPlatform.android) {
          // Androidの場合、MACアドレスで特定
          if (device.id.id.toUpperCase() == targetMACAddress.toUpperCase()) {
            print('Target Android device found: ${device.id.id.toUpperCase()}');
            FlutterBluePlus.stopScan();
            _connectToDevice(device);
            _cancelScanRetry();
            break;
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          // iOSの場合、Manufacturer DataからMACアドレスを取得
          if (advertisementData.manufacturerData.isNotEmpty) {
            final manufacturerData =
                advertisementData.manufacturerData.values.first;
            if (manufacturerData.length >= 6) {
              final macBytes = manufacturerData.sublist(0, 17);
              final macaddress_utf8 = utf8.decode(macBytes);

              print(
                  'Extracted MAC Address from Manufacturer Data: ${macaddress_utf8}');

              if (macaddress_utf8.toUpperCase() ==
                  targetMACAddress.toUpperCase()) {
                print("Target iOS device found");
                FlutterBluePlus.stopScan();
                _connectToDevice(device);
                _cancelScanRetry();
                break;
              } else {
                print(
                    'Extracted MAC Address does not match target: $macaddress_utf8');
              }
            } else {
              print(
                  'Manufacturer Data does not contain enough bytes for MAC address.');
            }
          } else {
            print('No Manufacturer Data found in advertisement.');
          }
        } else {
          print('Unknown platform');
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _connectedDevice = device;
    try {
      await device.connect();
      _isConnected = true;
      notifyListeners();
      print('Connected to ${device.name}');

      // サービスの探索
      List<BluetoothService> services = await device.discoverServices();
      bool uartServiceFound = false;
      for (BluetoothService service in services) {
        print('Service UUID: ${service.uuid}');
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          print('  Characteristic UUID: ${characteristic.uuid}');
          print('    Properties: ${characteristic.properties}');
        }
        if (service.uuid.toString().toUpperCase() ==
            uartServiceUUID.toString().toUpperCase()) {
          uartServiceFound = true;
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                txCharacteristicUUID.toString().toUpperCase()) {
              _txCharacteristic = characteristic;
              await _setNotification(_txCharacteristic!);
            } else if (characteristic.uuid.toString().toUpperCase() ==
                rxCharacteristicUUID.toString().toUpperCase()) {
              _rxCharacteristic = characteristic;
              // RXキャラクタリスティックには通知を設定しない
              // 必要に応じて、データ送信用の処理を追加
            }
          }
        }
      }

      if (!uartServiceFound) {
        print('UART Service not found on device');
        // 必要に応じてエラーハンドリング
      }

      // 接続状態の監視
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (_isConnected) {
            _isConnected = false;
            notifyListeners();
            print('Disconnected from device');
            _disconnectDevice();
            _retryScan();
          }
        }
      });
    } catch (e) {
      print('Error connecting to device: $e');
      _isConnected = false;
      notifyListeners();
      _retryScan();
    }
  }

  Future<void> _setNotification(BluetoothCharacteristic characteristic) async {
    try {
      // プロパティの確認と通知設定
      if (!characteristic.properties.notify) {
        await characteristic.setNotifyValue(true);
        // 通知をリッスン
        characteristic.value.listen((value) {
          _dataController.add(value);
          print('Received data: $value');
        });
      } else {
        print("Characteristic does not support notify.");
      }
    } catch (e) {
      print('Error setting notification on ${characteristic.uuid}: $e');
    }
  }

  void _disconnectDevice() {
    if (_connectedDevice != null) {
      _connectedDevice!.disconnect();
      _connectedDevice = null;
      _txCharacteristic = null;
      _isConnected = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _disconnectDevice();
  }

  void _retryScan() {
    if (_scanRetryTimer != null && _scanRetryTimer!.isActive) return;

    print('Retrying scan in 5 seconds...');
    _scanRetryTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected) {
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

  @override
  void dispose() {
    _dataController.close();
    super.dispose();
  }
}
