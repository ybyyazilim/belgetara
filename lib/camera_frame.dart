import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr/page.dart';

/// Android kamerası üç düzlemli YUV verir, ML Kit ise NV21 ister. Metin okumaya
/// parlaklık yeterli: renk düzlemi nötr (gri) doldurulur, satır dolgusu atılır.
Uint8List yPlaneToNv21(Uint8List y, int width, int height, int rowStride) {
  final out = Uint8List(width * height * 3 ~/ 2);
  for (var row = 0; row < height; row++) {
    final start = row * rowStride;
    if (start >= y.length) break;
    final end = start + width > y.length ? y.length : start + width;
    out.setRange(row * width, row * width + (end - start), y, start);
  }
  out.fillRange(width * height, out.length, 128);
  return out;
}

InputImage? nv21Input(Uint8List nv21, int width, int height, int sensorOrientation) {
  final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  if (rotation == null) return null;
  return InputImage.fromBytes(
    bytes: nv21,
    metadata: InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    ),
  );
}

/// Okuyucu konumları kameranın ham (yan duran) karesine göre verir; ekran yönüne çevirir.
Offset sensorToDisplay(Offset p, int sensorWidth, int sensorHeight, int rotation) {
  switch (rotation) {
    case 90:
      return Offset(sensorHeight - 1 - p.dy, p.dx);
    case 180:
      return Offset(sensorWidth - 1 - p.dx, sensorHeight - 1 - p.dy);
    case 270:
      return Offset(p.dy, sensorWidth - 1 - p.dx);
    default:
      return p;
  }
}

/// ML Kit çıktısını eğikliği düzeltilmiş kelimelere çevirir. [sensorSize] ve
/// [rotation] kamera karesi içindir; fotoğrafta konumlar zaten doğrudur.
List<OcrWord> wordsFrom(RecognizedText text, Size frame, {Size? sensorSize, int rotation = 0}) {
  final raw = [
    for (final block in text.blocks)
      for (final line in block.lines)
        for (final element in line.elements)
          (
            text: element.text,
            corners: element.cornerPoints.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList(),
          ),
  ];
  final sensor = sensorSize;
  // Konum ham karenin dışına taşıyorsa cihaz zaten ekran yönünde vermiştir.
  final isRaw = sensor != null &&
      raw.every((w) => w.corners.every((c) => c.dx <= sensor.width + 8 && c.dy <= sensor.height + 8));
  if (!isRaw) return uprightWords(raw, frame);
  return uprightWords([
    for (final w in raw)
      (
        text: w.text,
        corners: [for (final c in w.corners) sensorToDisplay(c, sensor.width.toInt(), sensor.height.toInt(), rotation)],
      ),
  ], frame);
}
