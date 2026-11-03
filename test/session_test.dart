import 'dart:typed_data';
import 'dart:ui';

import 'package:belgetara/camera_frame.dart';
import 'package:belgetara/models.dart';
import 'package:belgetara/ocr/doc_session.dart';
import 'package:belgetara/ocr/page.dart';
import 'package:belgetara/ocr/templates.dart';
import 'package:belgetara/store.dart';
import 'package:flutter_test/flutter_test.dart';

OcrWord w(String text, double x, double y, {double width = 60}) => OcrWord(text, Rect.fromLTWH(x, y, width, 20));

List<OcrWord> title(String t) {
  final parts = t.split(' ');
  return [for (var i = 0; i < parts.length; i++) w(parts[i], 300 + i * 70.0, 0)];
}

void main() {
  test('belge türü art arda iki karede kesinleşir, başka belgeye geçilebilir', () {
    final s = DocSession();
    final frame = [...title('Kesim Takip Formu'), w('SIRA', 0, 40), w('NO', 65, 40), w('000123', 130, 40)];
    expect(s.detect(frame), isFalse);
    expect(s.template, isNull);
    expect(s.detect(frame), isTrue);
    expect(s.template?.id, kesimTakip.id);
    expect(s.detect(frame), isFalse, reason: 'aynı belge yeniden başlatmaz');
    expect(s.requiredDone, isFalse);
    s.read(frame);
    expect(s.requiredDone, isTrue);
    expect(s.values['evrak'], '000123');
    final other = title('Kumaş Çeki Listesi');
    expect(s.detect(other), isFalse);
    expect(s.detect(other), isTrue);
    expect(s.template?.id, kumasCeki.id);
    expect(s.values, isEmpty);
  });

  test('taslak: satırlar ve sayı biçimi', () {
    final o = WorkOrder.fromScan(kumasCeki, {
      'firma': 'A', 'stok': 'B',
      'parti.0': 'P1', 'metre.0': '586,00', 'kilo.0': '141,70', 'top.0': '5',
      'parti.1': 'P2', 'metre.1': '3.935,00', 'kilo.1': '819,20', 'top.1': '16',
    });
    expect(o.lines.length, 2);
    expect(o.totalMeters, 4521);
    expect(o.totalKilos, closeTo(960.9, 0.001));
    expect(o.totalRolls, 21);
    expect(o.lines[1].meters, '3.935');
    expect(formatNumber(1708.9), '1.708,90');
  });

  test('okuma hatalı stok kayıtlıya bağlanır', () {
    expect(Store.match(['ZİNCİR'], 'zincir'), 'ZİNCİR');
    expect(Store.match(['ZİNCİR'], 'ZINCR'), 'ZİNCİR');
    expect(Store.match(['ZİNCİR'], 'BRODE'), isNull);
  });

  test('kumaş adındaki okuma hatası düzelir, bilinmeyen ad korunur', () {
    expect(correctFabric('ziİNCİR'), 'ZİNCİR');
    expect(correctFabric('BRODE (İPL)'), 'BRODE (İPLİ)');
    expect(correctFabric('PENYE'), 'PENYE');
  });

  test('ham kare konumu ekran yönüne çevrilir', () {
    expect(sensorToDisplay(const Offset(320, 661), 1920, 1080, 90), const Offset(418, 320));
    expect(sensorToDisplay(const Offset(5, 5), 1920, 1080, 0), const Offset(5, 5));
  });

  test('satır dolgusu atılır, renk düzlemi nötr olur', () {
    expect(yPlaneToNv21(Uint8List.fromList([1, 2, 0, 3, 4, 0]), 2, 2, 3), [1, 2, 3, 4, 128, 128]);
  });
}
