import 'dart:ui';

import 'page.dart';
import 'templates.dart';

/// İş emrinin belgeden isteyebileceği alanlar.
const definableFields = [
  FieldSpec('firma', 'Firma'),
  FieldSpec('stok', 'Stok'),
  FieldSpec('parti.0', 'Parti No'),
  FieldSpec('en.0', 'En', required: false),
  FieldSpec('metre.0', 'Giriş Metre'),
  FieldSpec('kilo.0', 'Giriş Kilo'),
  FieldSpec('top.0', 'Top Adedi', required: false),
  FieldSpec('renk', 'Renk', required: false),
  FieldSpec('islem', 'İşlem', required: false),
  FieldSpec('evrak', 'Evrak No', required: false),
  FieldSpec('tarih', 'Tarih', required: false),
];

const _numericKeys = {'en.0', 'metre.0', 'kilo.0', 'top.0'};

/// Tanımlanmış tek alan: hangi etiketin hangi yanında okunacağı.
class CustomField {
  const CustomField(this.key, this.label, this.side, {this.stops = const []});
  final String key;
  final String label;
  final ValueSide side;

  /// Örnek belgede değerin hemen yanındaki yazılar; değer buralarda biter.
  final List<String> stops;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'side': side.name, 'stops': stops};
  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        j['key'] as String,
        j['label'] as String,
        ValueSide.values.byName(j['side'] as String),
        stops: (j['stops'] as List).cast<String>(),
      );
}

/// Kullanıcının belge üzerinde seçerek oluşturduğu okuma tasarımı.
class CustomDoc {
  const CustomDoc({required this.id, required this.name, required this.title, required this.fields});
  final String id;
  final String name;
  final String title;
  final List<CustomField> fields;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'title': title, 'fields': fields.map((f) => f.toJson()).toList()};
  factory CustomDoc.fromJson(Map<String, dynamic> j) => CustomDoc(
        id: j['id'] as String,
        name: j['name'] as String,
        title: j['title'] as String,
        fields: (j['fields'] as List).map((e) => CustomField.fromJson(e as Map<String, dynamic>)).toList(),
      );

  DocTemplate toTemplate() {
    final stock = fields.where((f) => f.key == 'stok').firstOrNull;
    return DocTemplate(
      id: id,
      name: name,
      title: title,
      stockTerm: stock?.label ?? 'Stok',
      labels: [for (final f in fields) ...[f.label, ...f.stops]],
      fields: [
        for (final spec in definableFields)
          if (fields.any((f) => f.key == spec.id)) spec,
      ],
      read: _read,
    );
  }

  Map<String, String> _read(Page page) {
    final out = <String, String>{};
    for (final f in fields) {
      final raw = page.near(f.label, f.side);
      if (raw == null) continue;
      final value = _numericKeys.contains(f.key)
          ? firstNumber(raw)
          : f.key == 'tarih'
              ? dateOf(raw) ?? raw
              : raw;
      if (value != null) out[f.key] = value;
    }
    return out;
  }
}

bool _hasDigit(OcrWord w) => w.text.contains(RegExp(r'\d'));
bool _endsLabel(OcrWord w) => w.text.trimRight().endsWith(':');

/// Komşu kelimeleri ([from] başta olmak üzere) etiket olacak şekilde toplar.
List<OcrWord> _labelRun(OcrWord from, List<OcrWord> outward, {required bool leftward}) {
  final run = [from];
  for (final w in outward) {
    if (run.length == 3 || w == from) continue;
    if (w.norm.isEmpty) continue;
    final gap = leftward ? run.last.box.left - w.box.right : w.box.left - run.last.box.right;
    if (gap < 0) continue;
    if (gap > from.box.height * 1.5 || _hasDigit(w) || (leftward && _endsLabel(w))) break;
    run.add(w);
  }
  return leftward ? run.reversed.toList() : run;
}

/// Seçilen değerin etiketini tahmin eder: önce solundaki, sonra üstündeki,
/// en son sağındaki yazı (ör. "1.764 Mt"). Formlarda etiket yakın soldadır; sol
/// yazı uzaksa (tablo sütunları) ve üstte yazı varsa üstteki alınır.
List<OcrWord> inferLabel(Page page, List<OcrWord> value) {
  if (value.isEmpty) return const [];
  final box = value.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
  // Kâğıt bombesinde birleşik kutu şişer; yükseklik tek kelimeden ölçülür.
  final h = value.first.box.height;

  final first = value.reduce((a, b) => a.box.left <= b.box.left ? a : b);
  final leftWords = page.bandLeft(first.box).where((w) => !value.contains(w)).toList();
  var colon = false;
  OcrWord? left;
  for (final w in leftWords) {
    if (w.norm.isEmpty) {
      colon = colon || w.text.contains(':');
      continue;
    }
    if (!_hasDigit(w) && box.left - w.box.right < h * 18) left = w;
    break;
  }
  if (left != null && _endsLabel(left)) colon = true;

  final aboveWords = page.words
      .where((w) =>
          !value.contains(w) &&
          w.norm.isNotEmpty &&
          w.box.center.dy < box.top &&
          box.top - w.box.bottom < h * 3 &&
          w.box.right > box.left - h &&
          w.box.left < box.right + h)
      .toList()
    ..sort((a, b) => b.box.bottom.compareTo(a.box.bottom));
  final above = aboveWords.isNotEmpty && !_hasDigit(aboveWords.first) ? aboveWords.first : null;

  if (left != null && (colon || above == null || box.left - left.box.right <= h * 6)) {
    return _labelRun(left, page.bandLeft(left.box), leftward: true);
  }
  if (above != null) {
    final line = page.bandLeft(above.box);
    final run = _labelRun(above, line, leftward: true);
    final after = page.bandRight(above.box, maxDistance: h * 1.5).where((w) => !_hasDigit(w) && w.norm.isNotEmpty).take(1);
    return [...run, ...after];
  }
  final right = page.bandRight(box, maxDistance: h * 3).where((w) => !value.contains(w) && w.norm.isNotEmpty).firstOrNull;
  return right != null && !_hasDigit(right) ? [right] : const [];
}

/// Etiket ile değerin konumundan okuma yönünü çıkarır.
ValueSide sideOf(Rect label, Rect value) {
  if ((label.center.dy - value.center.dy).abs() < label.height) {
    return value.center.dx >= label.center.dx ? ValueSide.right : ValueSide.left;
  }
  return value.center.dy > label.center.dy ? ValueSide.below : ValueSide.above;
}

/// Değerin hemen yanındaki metinler: yeni belgede değer buralarda bitmeli.
List<String> stopsAround(Page page, List<OcrWord> value, List<OcrWord> label) {
  final sorted = [...value]..sort((a, b) => a.box.left.compareTo(b.box.left));
  final first = sorted.first.box, last = sorted.last.box;
  final near = [
    page.bandRight(last, maxDistance: last.height * 2.5),
    page.bandLeft(first).where((w) => first.left - w.box.right < first.height * 2.5),
  ];
  return {
    for (final side in near)
      for (final w in side.where((w) => w.norm.isNotEmpty && !value.contains(w)).take(1))
        if (!label.contains(w) && !_hasDigit(w)) w.text,
  }.toList();
}

/// Metne çevirir: kelimeler soldan sağa.
String joinWords(List<OcrWord> words) {
  final sorted = [...words]..sort((a, b) => a.box.left.compareTo(b.box.left));
  return sorted.map((w) => w.text).join(' ');
}
