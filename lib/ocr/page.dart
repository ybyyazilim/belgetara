import 'dart:math' as math;
import 'dart:ui';

/// Okuyucudan gelen kelime. [box] eğikliği düzeltilmiş, [raw] görüntüdeki konumdur.
class OcrWord {
  const OcrWord(this.text, this.box, {Rect? raw, this.touchesEdge = false}) : raw = raw ?? box;
  final String text;
  final Rect box;
  final Rect raw;
  final bool touchesEdge;
  String get norm => normalizeText(text);
}

/// Türkçe karakter ve büyük/küçük harf farkını kaldırır, noktalamayı atar.
String normalizeText(String input) {
  const map = {'ş': 's', 'ğ': 'g', 'ü': 'u', 'ö': 'o', 'ç': 'c', 'ı': 'i', 'â': 'a', 'î': 'i', 'û': 'u'};
  final lower = input.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
  return lower.split('').map((c) => map[c] ?? c).join().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = [i];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current.add(math.min(math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost));
    }
    previous = current;
  }
  return previous[b.length];
}

bool isClose(String word, String keyword) {
  final allowed = keyword.length >= 8 ? 2 : (keyword.length >= 4 ? 1 : 0);
  if ((word.length - keyword.length).abs() > allowed) return false;
  return _editDistance(word, keyword) <= allowed;
}

/// Yan ya da eğik çekilmiş belgeyi düzeltir: kelimeleri ortanca açı kadar geri döndürür.
List<OcrWord> uprightWords(List<({String text, List<Offset> corners})> raw, Size frame) {
  final usable = raw.where((w) => w.corners.length == 4).toList();
  if (usable.isEmpty) return const [];
  final angles = usable.map((w) {
    final d = w.corners[1] - w.corners[0];
    return math.atan2(d.dy, d.dx);
  }).toList()
    ..sort();
  final angle = angles[angles.length ~/ 2];
  final cosA = math.cos(angle), sinA = math.sin(angle);
  final margin = frame.shortestSide * 0.01;
  return usable.map((w) {
    final c = w.corners;
    final center = (c[0] + c[2]) / 2;
    final rotated = Offset(center.dx * cosA + center.dy * sinA, -center.dx * sinA + center.dy * cosA);
    final xs = c.map((p) => p.dx), ys = c.map((p) => p.dy);
    return OcrWord(
      w.text,
      Rect.fromCenter(center: rotated, width: (c[1] - c[0]).distance, height: (c[3] - c[0]).distance),
      raw: Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)),
      touchesEdge: c.any((p) =>
          p.dx <= margin || p.dy <= margin || p.dx >= frame.width - margin || p.dy >= frame.height - margin),
    );
  }).toList();
}

/// Okuma hatalarını sayıda düzeltir: 141,7d → 141,70, Z8,60 → 28,60.
String fixNumber(String s) => s
    .replaceAll(RegExp(r'[OoDd]'), '0')
    .replaceAll(RegExp(r'[Ss$]'), '5')
    .replaceAll(RegExp(r'[Zz]'), '2')
    .replaceAll(RegExp(r'[lI|]'), '1');

final _numberLike = RegExp(r'^[0-9OoDdSs$Zz]{0,4}[.,]?[0-9OoDdSs$Zz]*[.,][0-9OoDdSs$Zz]{1,3}$|^\d+$');

/// Sayı gibi duran kelimeyi temizler; değilse null.
String? numberOf(String text) {
  final t = text.replaceAll(RegExp(r'^[|\-·.\s]+|[|\s]+$'), '');
  if (!_numberLike.hasMatch(t) || !t.contains(RegExp(r'\d'))) return null;
  return fixNumber(t);
}

/// "3.935,00", "1.764", "198.10" biçimlerini sayıya çevirir.
double? parseNumber(String? text) {
  if (text == null) return null;
  var t = text.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    final i = t.lastIndexOf(',');
    t = '${t.substring(0, i).replaceAll(RegExp(r'[.,]'), '')}.${t.substring(i + 1)}';
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t);
}

/// Değerin etikete göre durduğu yan.
enum ValueSide { right, left, below, above }

class LabelMatch {
  LabelMatch(this.words, this.exact);
  final List<OcrWord> words;
  final bool exact;
  Rect get box => words.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
}

final _edgePunctuation = RegExp(r'^[\s:;=|_\-–—.,/]+|[\s:;=|_\-–—.,/]+$');

/// Tek karedeki kelimeler üzerinde etikete göre arama yapar.
class Page {
  Page(List<OcrWord> words, {List<String> labels = const [], String? title}) : words = [...words] {
    if (title != null) {
      for (final m in matches(title).take(1)) {
        this.words.removeWhere(m.words.contains);
      }
    }
    for (final label in labels) {
      for (final m in matches(label)) {
        _stops.addAll(m.words);
      }
    }
  }

  final List<OcrWord> words;
  final Set<OcrWord> _stops = {};

  /// Sağa doğru aynı satırdaki kelimeler; kâğıt bombesi için uzaklıkla tolerans artar.
  List<OcrWord> bandRight(Rect key, {double? maxDistance}) {
    final list = words.where((w) {
      final dx = w.box.left - key.right;
      if (w.box.center.dx <= key.right || (maxDistance != null && dx > maxDistance)) return false;
      return (w.box.center.dy - key.center.dy).abs() < key.height * 0.7 + dx.abs() * 0.03;
    }).toList();
    list.sort((a, b) => a.box.left.compareTo(b.box.left));
    return list;
  }

  List<OcrWord> bandLeft(Rect key) {
    final list = words.where((w) {
      final dx = key.left - w.box.right;
      return w.box.center.dx < key.left && (w.box.center.dy - key.center.dy).abs() < key.height * 0.7 + dx.abs() * 0.03;
    }).toList();
    list.sort((a, b) => b.box.right.compareTo(a.box.right));
    return list;
  }

  /// Etiketin geçtiği yerler: tam eşleşenler önce, sonra yukarıdan aşağıya.
  List<LabelMatch> matches(String label) {
    final parts = label.split(RegExp(r'\s+')).map(normalizeText).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const [];
    final joined = parts.join();
    final found = <LabelMatch>[];
    for (final word in words) {
      final n = word.norm;
      if (parts.length > 1 && _editDistance(n, joined) <= 1) {
        found.add(LabelMatch([word], n == joined)); // bitişik okunmuş: "PartiNo", "TAdet"
        continue;
      }
      if (!isClose(n, parts.first)) continue;
      final chain = [word];
      var exact = n == parts.first;
      for (var i = 1; i < parts.length; i++) {
        final h = chain.last.box.height;
        final next = bandRight(chain.last.box, maxDistance: h * 2.5).where((w) => w.norm.isNotEmpty).firstOrNull;
        if (next == null || !isClose(next.norm, parts[i])) {
          chain.clear();
          break;
        }
        if (next.norm != parts[i]) exact = false;
        chain.add(next);
      }
      if (chain.isNotEmpty) found.add(LabelMatch(chain, exact));
    }
    found.sort((a, b) => a.exact == b.exact ? a.box.top.compareTo(b.box.top) : (a.exact ? -1 : 1));
    return found;
  }

  bool has(String phrase) => matches(phrase).isNotEmpty;

  /// Etiketin hemen sağındaki değer; başka bir etikete ya da büyük boşluğa gelince biter.
  String? right(String label, {double firstGap = 18}) {
    for (final match in matches(label)) {
      final v = _valueRight(match.box, match.words, firstGap);
      if (v != null) return v;
    }
    return null;
  }

  /// Yukarıdan aşağıya her eşleşmenin sağındaki değer (yoksa null); bloklu belgeler için.
  List<String?> rightAll(String label, {double firstGap = 18}) {
    final all = matches(label)..sort((a, b) => a.box.top.compareTo(b.box.top));
    return [for (final m in all) _valueRight(m.box, m.words, firstGap)];
  }

  String? _valueRight(Rect key, List<OcrWord> own, double firstGap) {
    final h = key.height;
    final taken = <OcrWord>[];
    for (final word in bandRight(key)) {
      if (own.contains(word)) continue;
      if (_stops.contains(word)) break;
      final anchor = taken.isEmpty ? key : taken.last.box;
      final gap = word.box.left - anchor.right;
      if (taken.isEmpty && word.norm.isEmpty) continue; // ":" gibi işaretler
      if (gap > h * (taken.isEmpty ? firstGap : 2.5)) break;
      taken.add(word);
    }
    return _join(taken);
  }

  String? _join(List<OcrWord> taken) {
    if (taken.isEmpty || taken.any((w) => w.touchesEdge)) return null;
    final text = taken.map((w) => w.text).join(' ').replaceAll(_edgePunctuation, '');
    return normalizeText(text).isEmpty ? null : text;
  }

  /// Etiketin verilen yanındaki değer; kullanıcı tanımlı belgeler için.
  String? near(String label, ValueSide side) {
    if (side == ValueSide.right) return right(label);
    for (final match in matches(label)) {
      final v = side == ValueSide.left ? _valueLeft(match) : _valueVertical(match, side == ValueSide.below);
      if (v != null) return v;
    }
    return null;
  }

  String? _valueLeft(LabelMatch match) {
    final h = match.box.height;
    final taken = <OcrWord>[];
    for (final word in bandLeft(match.box)) {
      if (match.words.contains(word)) continue;
      if (_stops.contains(word)) break;
      if (taken.isEmpty && word.norm.isEmpty) continue;
      final gap = (taken.isEmpty ? match.box.left : taken.last.box.left) - word.box.right;
      if (gap > h * (taken.isEmpty ? 18 : 2.5)) break;
      taken.add(word);
    }
    return _join(taken.reversed.toList());
  }

  String? _valueVertical(LabelMatch match, bool below) {
    final key = match.box, h = key.height;
    final column = words.where((w) {
      if (match.words.contains(w) || w.norm.isEmpty) return false;
      if (w.box.right < key.left - h || w.box.left > key.right + h) return false;
      final dy = below ? w.box.center.dy - key.center.dy : key.center.dy - w.box.center.dy;
      return dy > h * 0.5 && dy < h * 6;
    }).toList()
      ..sort((a, b) => (a.box.center.dy - key.center.dy).abs().compareTo((b.box.center.dy - key.center.dy).abs()));
    if (column.isEmpty || _stops.contains(column.first)) return null;
    final seed = column.first;
    final left = <OcrWord>[];
    for (final w in bandLeft(seed.box)) {
      if (_stops.contains(w) || (left.isEmpty ? seed : left.last).box.left - w.box.right > h * 2.5) break;
      left.add(w);
    }
    final right = <OcrWord>[];
    for (final w in bandRight(seed.box)) {
      if (_stops.contains(w) || w.box.left - (right.isEmpty ? seed : right.last).box.right > h * 2.5) break;
      right.add(w);
    }
    return _join([...left.reversed, seed, ...right]);
  }

  /// Etiketin bir üst satırı (etiketi okunamayan alanlar için son çare).
  String? lineAbove(String label) {
    for (final match in matches(label)) {
      final key = match.box;
      final above = words.where((w) {
        final dy = key.center.dy - w.box.center.dy;
        return dy > key.height * 0.7 && dy < key.height * 3 && !_stops.contains(w);
      }).toList();
      if (above.isEmpty) continue;
      above.sort((a, b) => b.box.center.dy.compareTo(a.box.center.dy));
      final y = above.first.box.center.dy;
      final line = above.where((w) => (w.box.center.dy - y).abs() < key.height * 0.7).toList()
        ..sort((a, b) => a.box.left.compareTo(b.box.left));
      // Satırın devamındaki tarih gibi uzak sütunlar alınmaz.
      final run = <OcrWord>[line.first];
      for (final w in line.skip(1)) {
        if (w.box.left - run.last.box.right > key.height * 2.5) break;
        run.add(w);
      }
      final v = _join(run);
      if (v != null) return v;
    }
    return null;
  }

  /// Birime bitişik sayı: "1.764 Mt", "35.70 ka". Birim düzenli ifadeyle verilir.
  String? numberBefore(RegExp unit) {
    for (final w in words) {
      final glued = RegExp(r'^([0-9.,]+)(.+)$').firstMatch(w.text);
      if (glued != null && unit.hasMatch(normalizeText(glued.group(2)!))) return numberOf(glued.group(1)!);
      if (!unit.hasMatch(w.norm)) continue;
      final left = bandLeft(w.box).where((o) => o.box.right > w.box.left - w.box.height * 3).firstOrNull;
      final n = left == null ? null : numberOf(left.text);
      if (n != null) return n;
    }
    return null;
  }

  /// Etiketin sağındaki sayılar sırayla.
  List<String> numbersRight(Rect key) => [
        for (final w in bandRight(key))
          if (numberOf(w.text) != null) numberOf(w.text)!,
      ];

  /// Deseni tutan kelimeler, yukarıdan aşağıya.
  List<OcrWord> find(RegExp pattern) => words.where((w) => pattern.hasMatch(w.text.replaceAll(RegExp(r'^[|]+|[|]+$'), ''))).toList()
    ..sort((a, b) => a.box.top.compareTo(b.box.top));
}
