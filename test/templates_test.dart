import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:belgetara/ocr/page.dart';
import 'package:belgetara/ocr/templates.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gerçek belge fotoğraflarının ML Kit çıktısı ve beklenen değerleri.
/// Depoda yoktur (gerçek müşteri verisi); yerelde eklenir, bkz. README.
const fixtureDir = 'test/fixtures/ocr';

bool hasFixture(String name) => File('$fixtureDir/$name.json').existsSync();

/// Belgeler veya beklenen değerler eksikse testi atlatan gerekçe; tamamsa null.
String? skipWithout(List<String> names) =>
    names.every(hasFixture) && hasFixture('expected') ? null : '$fixtureDir altında örnek belge yok (README: Test verisi)';

/// expected.json içindeki bir belgenin beklenen alan değerleri.
Map<String, dynamic> expected(String name) =>
    (jsonDecode(File('$fixtureDir/expected.json').readAsStringSync()) as Map<String, dynamic>)[name] as Map<String, dynamic>;

List<OcrWord> load(String name) {
  final d = jsonDecode(File('$fixtureDir/$name.json').readAsStringSync());
  final raw = [
    for (final w in d['words'])
      (
        text: w['t'] as String,
        corners: [for (final c in w['c']) Offset((c[0] as num).toDouble(), (c[1] as num).toDouble())],
      )
  ];
  return uprightWords(raw, Size((d['width'] as num).toDouble(), (d['height'] as num).toDouble()));
}

Map<String, String> readDoc(String name, DocTemplate expectedTemplate) {
  final words = load(name);
  final t = detectTemplate(words);
  expect(t?.id, expectedTemplate.id, reason: 'belge türü');
  return t!.read(t.page(words));
}

/// Okunan değerleri expected.json ile karşılaştırır.
void expectRead(String name, DocTemplate template) {
  final m = readDoc(name, template);
  expected(name).forEach((key, value) => expect(m[key], value, reason: '$name: $key'));
}

void main() {
  test('Kumaş Çeki: tek kâğıttan iki parti, sağa taşan toplam doğru bloğa gider',
      () => expectRead('ceki_net', kumasCeki),
      skip: skipWithout(['ceki_net']));

  test('Kumaş Çeki: bulanık fotoğrafta sayı hataları düzelir',
      () => expectRead('ceki_bulanik', kumasCeki),
      skip: skipWithout(['ceki_bulanik']));

  test('Kumaş Sevk Çeki: Firma etiketi kıvrımda kaybolsa da firma, giriş değerleri alınır',
      () => expectRead('sevk_ceki', sevkCeki),
      skip: skipWithout(['sevk_ceki']));

  test('Ürün Sevk Fişi: yan çekilmiş belge', () => expectRead('sevk_fisi', urunSevk), skip: skipWithout(['sevk_fisi']));

  test('Çıkış Çeki: Müşteri ile Müşteri MT/KG karışmaz, kilo 0 ise toplam alınır',
      () => expectRead('cikis_ceki', cikisCeki),
      skip: skipWithout(['cikis_ceki']));

  test('El yazılı belgeler türünden tanınır', () {
    expectRead('kesim_takip', kesimTakip);
    expectRead('irsaliye', kumasIrsaliye);
  }, skip: skipWithout(['kesim_takip', 'irsaliye']));

  test('sayı çözümleme', () {
    expect(parseNumber('3.935,00'), 3935);
    expect(parseNumber('1.764'), 1764);
    expect(parseNumber('198.10'), 198.1);
    expect(parseNumber('1,708,90'), 1708.9);
    expect(numberOf('141,7d'), '141,70');
    expect(numberOf('YUMUŞAK'), isNull);
  });
}
