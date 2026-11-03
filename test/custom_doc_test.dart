import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:belgetara/ocr/custom_doc.dart';
import 'package:belgetara/ocr/page.dart';
import 'package:belgetara/ocr/still.dart';
import 'package:belgetara/ocr/templates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'templates_test.dart' show expected, load, skipWithout;

/// Ekranda yapılan seçimin aynısı: değer kelimeleri seçilir, etiket tahmin edilir.
CustomField pick(List<OcrWord> words, String key, String valueText) {
  final page = Page(words);
  final parts = valueText.split(' ');
  final first = words.firstWhere((w) => w.text == parts.first, orElse: () => throw 'yok: $valueText');
  final value = [first, ...page.bandRight(first.box).take(parts.length - 1)];
  final label = inferLabel(page, value);
  expect(label, isNotEmpty, reason: '$key etiketi');
  Rect union(List<OcrWord> l) => l.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
  return CustomField(key, joinWords(label), sideOf(union(label), union(value)), stops: stopsAround(page, value, label));
}

void main() {
  /// Örnek belgede expected.json'daki değerler seçilir; tanım aynı belgeyi geri okumalı.
  void readsBack(String name, String title) {
    final words = load(name);
    final c = expected('custom')[name] as Map<String, dynamic>;
    final picks = (c['picks'] as Map<String, dynamic>).cast<String, String>();
    final doc = CustomDoc(id: 'x', name: name, title: title, fields: [
      for (final e in picks.entries) pick(words, e.key, e.value),
    ]);
    final t = doc.toTemplate();
    final v = t.read(t.page(words));
    (c['values'] as Map<String, dynamic>).forEach((key, value) => expect(v[key], value, reason: key));
  }

  test('Ürün Sevk Fişi: seçilen değerlerden tanım oluşur ve belgeyi okur',
      () => readsBack('sevk_fisi', 'Ürün Sevk Fişi'),
      skip: skipWithout(['sevk_fisi']));

  test('Kumaş Çeki: firma ve fiş tanımı okunur, stok adı etiketten gelir',
      () => readsBack('ceki_net', 'Kumaş Çeki Listesi'),
      skip: skipWithout(['ceki_net']));

  OcrWord w(String text, double x, double y, {double width = 60}) => OcrWord(text, Rect.fromLTWH(x, y, width, 20));

  test('tablo başlığı: değer sütun başlığının altından okunur', () {
    final sample = [w('Metre', 100, 0), w('Kilo', 300, 0), w('586', 100, 30), w('141', 300, 30)];
    final field = pick(sample, 'metre.0', '586');
    expect(field.label, 'Metre');
    expect(field.side, ValueSide.below);
    final other = Page([w('Metre', 100, 0), w('Kilo', 300, 0), w('999', 100, 30), w('141', 300, 30)]);
    expect(other.near('Metre', ValueSide.below), '999');
  });

  test('birim sağdaysa değer etiketin solundan okunur', () {
    final page = Page([w('1.764', 100, 0), w('Mt', 170, 0, width: 30)]);
    expect(page.near('Mt', ValueSide.left), '1.764');
  });

  test('tanım kaydedilip geri okunur, başlıkla tanınır ve hazır tasarımın önüne geçer', () {
    const doc = CustomDoc(id: 'x', name: 'Bizim Fiş', title: 'Ürün Sevk Fişi', fields: [CustomField('firma', 'Müşteri Adı', ValueSide.right, stops: ['Sevk'])]);
    final back = CustomDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    expect(back.fields.single.stops, ['Sevk']);
    final t = detectTemplate(load('sevk_fisi'), custom: [back]);
    expect(t?.name, 'Bizim Fiş');
    expect(detectTemplate(load('ceki_net'), custom: [back])?.id, kumasCeki.id);
    expect(mergeSorted(templates).first.id, sevkCeki.id);
  }, skip: skipWithout(['sevk_fisi', 'ceki_net']));

  group('dondurma', () {
    test('sabit kamerada süre dolar, kıpırdayınca baştan başlar', () {
      final hold = HoldTracker();
      final t0 = DateTime(2026);
      final a = Uint8List(576), moved = Uint8List(576);
      for (var i = 0; i < 576; i++) {
        moved[i] = i.isEven ? 60 : 0;
      }
      expect(hold.update(a, t0), isFalse);
      expect(hold.update(a, t0.add(const Duration(seconds: 1))), isFalse);
      expect(hold.progress(t0.add(const Duration(seconds: 1))), 0.5);
      expect(hold.update(moved, t0.add(const Duration(milliseconds: 1500))), isTrue);
      expect(hold.done(t0.add(const Duration(seconds: 2))), isFalse);
      expect(hold.done(t0.add(const Duration(milliseconds: 3500))), isTrue);
    });

    test('tüm karenin aydınlanması hareket sayılmaz', () {
      final a = Uint8List(576), b = Uint8List(576)..fillRange(0, 576, 40);
      expect(motionBetween(a, b), 0);
    });

    test('keskin kare bulanıktan yüksek puan alır', () {
      final sharp = Uint8List(100 * 100), flat = Uint8List(100 * 100)..fillRange(0, 10000, 128);
      for (var i = 0; i < sharp.length; i++) {
        sharp[i] = (i ~/ 4).isEven ? 255 : 0;
      }
      expect(sharpnessOf(sharp, 100, 100), greaterThan(sharpnessOf(flat, 100, 100)));
    });

    test('kare telefondaki dik yönüne çevrilir', () {
      final out = rotatedRgba(Uint8List.fromList([1, 2, 3, 4, 5, 6]), 3, 2, 90);
      // 1 2 3 / 4 5 6 → saat yönünde: 4 1 / 5 2 / 6 3
      expect([for (var i = 0; i < out.length; i += 4) out[i]], [4, 1, 5, 2, 6, 3]);
      final left = rotatedRgba(Uint8List.fromList([1, 2, 3, 4, 5, 6]), 3, 2, 270);
      expect([for (var i = 0; i < left.length; i += 4) left[i]], [3, 6, 2, 5, 1, 4]);
    });
  });
}
