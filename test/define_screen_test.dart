import 'dart:typed_data';

import 'package:belgetara/ocr/page.dart' show OcrWord;
import 'package:belgetara/ocr/still.dart';
import 'package:belgetara/screens/define_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Örnek belge: gerçek veri yok, kelimeler elle yerleştirildi.
OcrWord w(String text, double x, double y, {double width = 160}) => OcrWord(text, Rect.fromLTWH(x, y, width, 40));

void main() {
  testWidgets('belge üzerinde dokunarak seçim: başlık, değer, kaldırıp yeniden seçme, kaydetme', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const width = 1080, height = 1920;
    final words = [
      w('KUMAŞ', 200, 100),
      w('ÇEKİ', 380, 100),
      w('LİSTESİ', 560, 100),
      w('FİRMA', 60, 300, width: 140),
      w('DEMİRÇELİK', 300, 300, width: 260),
      w('TEKSTİL', 580, 300),
      w('Tarih', 60, 400, width: 120),
      w('03.11.2026', 300, 400, width: 240),
    ];
    final still = Still(Uint8List(width * height * 3 ~/ 2), width, height, 0, words);
    await tester.pumpWidget(MaterialApp(home: DefineScreen(still: still)));

    Future<void> tapWord(String text) async {
      final OcrWord w = words.firstWhere((w) => w.text == text);
      final r = tester.getRect(find.byType(AspectRatio));
      await tester.tapAt(r.topLeft + Offset(w.raw.center.dx * r.width / width, w.raw.center.dy * r.height / height));
      await tester.pump();
    }

    await tapWord('KUMAŞ');
    await tester.tap(find.text('Firma'));
    await tester.pump();
    await tapWord('DEMİRÇELİK');
    await tapWord('DEMİRÇELİK'); // kaldır
    expect(find.text('Henüz seçilmedi'), findsOneWidget);
    await tapWord('DEMİRÇELİK'); // yeniden seç
    await tapWord('TEKSTİL');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Etiket: FİRMA'), findsOneWidget);
    expect(find.text('Okunan: DEMİRÇELİK TEKSTİL'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Kaydet')).onPressed, isNotNull);
  });
}
