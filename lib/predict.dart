// lib/Predict.dart
import 'dart:typed_data';
import 'package:image/image.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class Predict {
  Interpreter? _interpreter;
  bool _isInterpreterInitialized = false;

  Predict() {
    _initializeInterpreter();
  }

  // TensorFlow Liteインタープリターの初期化
  Future<void> _initializeInterpreter() async {
    try {
      _interpreter = await Interpreter.fromAsset(
          "assets/poistongs_model_quantized.tflite");
      _isInterpreterInitialized = true;
      print('Interpreter initialized successfully.');
    } catch (e) {
      print('Error initializing interpreter: $e');
    }
  }

  bool get isInterpreterInitialized => _isInterpreterInitialized;

  // 画像を分類し、結果を返すメソッド
  Future<String> predictImage(Uint8List imageBytes) async {
    print("predictImage() called");
    if (!_isInterpreterInitialized || _interpreter == null) {
      return 'Interpreter not initialized';
    }

    // 画像のデコード
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      return 'Failed to decode image';
    }

    // 画像のリサイズ（モデルの入力サイズに合わせる）
    img.Image resizedImage = img.copyResize(image, width: 224, height: 224);
    print("画像のリサイズ完了");

    // 画像データの正規化（-128にオフセット）
    ByteBuffer inputBuffer = convertImageToByteBuffer(resizedImage);
    print("画像データの正規化完了");

    // 出力バッファの準備（2クラスの場合）
    var output = List.filled(1 * 1, 0.0).reshape([1, 1]);
    print("出力バッファの準備完了");

    // モデルの実行
    _interpreter!.run(inputBuffer, output);
    print("モデルの実行完了");

    // 予測結果の取得
    int prediction = output[0][0];
    print("予測結果の取得完了");

    // ラベルの決定（閾値を0.5と仮定）
    String label = prediction > 0.5 ? 'pick' : 'none';

    return label;
  }

  // BitmapをByteBufferに変換するメソッド
  ByteBuffer convertImageToByteBuffer(Image image) {
    // 画像の幅と高さを設定します（ここでは224x224を想定しています）
    int width = 224;
    int height = 224;

    // 画像が指定のサイズでない場合、リサイズします
    if (image.width != width || image.height != height) {
      image = copyResize(image, width: width, height: height);
    }

    // 各ピクセルあたり3バイト（RGB）なので、全体のサイズはwidth * height * 3です。
    int numBytes = width * height * 3;

    // Int8Listを作成します。負の値も扱えるようにInt8Listを使用します。
    Int8List byteData = Int8List(numBytes);

    int index = 0;

    // ピクセルデータを取得します
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // ピクセルのARGB値を取得します
        var pixel = image.getPixel(x, y);

        // 各色から128を引いて正規化します
        int r = pixel.r - 128 as int;
        int g = pixel.g - 128 as int;
        int b = pixel.b - 128 as int;
        byteData[index++] = r;
        byteData[index++] = g;
        byteData[index++] = b;
      }
    }

    // ByteBufferを返します
    return byteData.buffer;
  }
}
