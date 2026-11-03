import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'page.dart';

const _gridColumns = 32, _gridRows = 18, _samples = 4;

/// Kareyi küçük bir parlaklık ızgarasına indirir; iki kareyi karşılaştırmak için.
Uint8List motionSignature(Uint8List y, int width, int height, int stride) {
  final out = Uint8List(_gridColumns * _gridRows);
  final cellW = width ~/ _gridColumns, cellH = height ~/ _gridRows;
  final stepX = cellW ~/ _samples, stepY = cellH ~/ _samples;
  if (stepX == 0 || stepY == 0) return out;
  for (var r = 0; r < _gridRows; r++) {
    for (var c = 0; c < _gridColumns; c++) {
      var sum = 0, n = 0;
      for (var dy = 0; dy < _samples; dy++) {
        for (var dx = 0; dx < _samples; dx++) {
          final i = (r * cellH + dy * stepY) * stride + c * cellW + dx * stepX;
          if (i < y.length) {
            sum += y[i];
            n++;
          }
        }
      }
      out[r * _gridColumns + c] = n == 0 ? 0 : sum ~/ n;
    }
  }
  return out;
}

/// İki ızgara arasındaki ortalama fark. Pozlama değişimi (tüm karenin kararıp
/// aydınlanması) hareket sayılmaz.
double motionBetween(Uint8List a, Uint8List b) {
  var signed = 0;
  for (var i = 0; i < a.length; i++) {
    signed += a[i] - b[i];
  }
  final shift = signed / a.length;
  var total = 0.0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i] - shift).abs();
  }
  return total / a.length;
}

/// Netlik ölçüsü: komşu pikseller arası keskin geçişlerin gücü.
double sharpnessOf(Uint8List y, int width, int height) {
  var sum = 0.0;
  var n = 0;
  for (var row = 4; row < height - 4; row += 4) {
    for (var col = 4; col < width - 4; col += 4) {
      final i = row * width + col;
      final d = 4 * y[i] - y[i - 1] - y[i + 1] - y[i - width] - y[i + width];
      sum += d * d;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Kameranın ne kadar süredir kıpırdamadığını izler.
class HoldTracker {
  HoldTracker({this.hold = const Duration(seconds: 2), this.threshold = 4});
  final Duration hold;
  final double threshold;
  Uint8List? _last;
  DateTime? _since;

  /// Yeni karenin izini işler; kamera kıpırdadıysa true döner ve süre baştan başlar.
  bool update(Uint8List signature, DateTime now) {
    final last = _last;
    _last = signature;
    final moved = last != null && motionBetween(last, signature) > threshold;
    if (moved || _since == null) _since = now;
    return moved;
  }

  void restart(DateTime now) => _since = now;

  double progress(DateTime now) {
    final since = _since;
    if (since == null) return 0;
    return (now.difference(since).inMilliseconds / hold.inMilliseconds).clamp(0, 1).toDouble();
  }

  bool done(DateTime now) => progress(now) >= 1;
}

/// Dondurulmuş kare: gri NV21 ve okunmaya hazır düzeltilmiş kelimeleri.
class Still {
  const Still(this.nv21, this.width, this.height, this.sensorRotation, this.words);
  final Uint8List nv21;
  final int width;
  final int height;
  final int sensorRotation;
  final List<OcrWord> words;

  bool get _sideways => sensorRotation % 180 != 0;
  ui.Size get size =>
      _sideways ? ui.Size(height.toDouble(), width.toDouble()) : ui.Size(width.toDouble(), height.toDouble());

  Future<ui.Image> toImage() async {
    final rgba = await compute(_rotatedRgba, (nv21, width, height, sensorRotation));
    final outW = _sideways ? height : width, outH = _sideways ? width : height;
    return decodeRgba(rgba, outW, outH);
  }
}

Future<ui.Image> decodeRgba(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return image;
}

Uint8List _rotatedRgba((Uint8List, int, int, int) input) {
  final (y, width, height, rotation) = input;
  return rotatedRgba(y, width, height, rotation);
}

/// Sensör karesini ekrandaki yönüne çevirip gri RGBA yazar.
@visibleForTesting
Uint8List rotatedRgba(Uint8List y, int width, int height, int rotation) {
  final sideways = rotation % 180 != 0;
  final outW = sideways ? height : width;
  final out = Uint8List(width * height * 4);
  for (var sy = 0; sy < height; sy++) {
    for (var sx = 0; sx < width; sx++) {
      final int dx, dy;
      switch (rotation) {
        case 90:
          dx = height - 1 - sy;
          dy = sx;
        case 180:
          dx = width - 1 - sx;
          dy = height - 1 - sy;
        case 270:
          dx = sy;
          dy = width - 1 - sx;
        default:
          dx = sx;
          dy = sy;
      }
      final v = y[sy * width + sx];
      final o = (dy * outW + dx) * 4;
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}
