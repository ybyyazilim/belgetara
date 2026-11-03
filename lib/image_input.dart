import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Fotoğrafı (galeri) gri NV21 kareye çevirir; dört yönde de okunabilsin diye
/// döndürme bilgisi çağıran tarafından verilir.
class DecodedPhoto {
  DecodedPhoto(this.nv21, this.width, this.height);
  final Uint8List nv21;
  final int width;
  final int height;

  static Future<DecodedPhoto> fromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    final width = image.width, height = image.height;
    image.dispose();
    // Piksel döngüsü arayüzü dondurmasın diye ayrı iş parçacığında çalışır.
    final nv21 = await compute(_toNv21, (rgba, width, height));
    return DecodedPhoto(nv21, width & ~1, height & ~1);
  }

  InputImage toInput(InputImageRotation rotation) => InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
}

Uint8List _toNv21((Uint8List, int, int) input) {
  final (rgba, sourceWidth, sourceHeight) = input;
  // NV21 çift boyut ister.
  final width = sourceWidth & ~1, height = sourceHeight & ~1, stride = sourceWidth * 4;
  final out = Uint8List(width * height * 3 ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * stride + x * 4;
      out[y * width + x] = (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
    }
  }
  out.fillRange(width * height, out.length, 128);
  return out;
}
