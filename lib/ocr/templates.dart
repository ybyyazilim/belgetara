import 'custom_doc.dart';
import 'page.dart';

/// Taramada listelenecek bir alan. id sonundaki `.0`, `.1` parti satırıdır.
class FieldSpec {
  const FieldSpec(this.id, this.title, {this.required = true});
  final String id;
  final String title;
  final bool required;
}

/// Bir belge türünün okuma tasarımı: başlığı, alan adları ve okuma kuralları.
class DocTemplate {
  const DocTemplate({
    required this.id,
    required this.name,
    required this.title,
    required this.stockTerm,
    required this.labels,
    required this.fields,
    required this.read,
    this.lineFields = const [],
    this.handwritten = false,
  });

  final String id;
  final String name;
  final String title;

  /// Belgenin stoğa verdiği ad: Kumaş, Kalite, Kumaş Cinsi, Cinsi.
  final String stockTerm;
  final List<String> labels;
  final List<FieldSpec> fields;

  /// Parti başına tekrarlanan alanlar.
  final List<FieldSpec> lineFields;
  final bool handwritten;
  final Map<String, String> Function(Page) read;

  Page page(List<OcrWord> words) => Page(words, labels: labels, title: title);
}

void _put(Map<String, String> m, String key, String? value) {
  final v = value?.trim();
  if (v != null && v.isNotEmpty) m[key] = v;
}

final _mt = RegExp(r'^mt$');
final _kg = RegExp(r'^k[gao]$');
final _date = RegExp(r'\d{2}[./ ]\d{2}[./ ]\d{4}');
String? dateOf(String? s) => s == null ? null : _date.firstMatch(s)?.group(0)?.replaceAll(RegExp(r'[/ ]'), '.');
String? firstNumber(String? s) {
  if (s == null) return null;
  final m = RegExp(r'[0-9][0-9.,]*').firstMatch(s);
  return m == null ? null : numberOf(m.group(0)!);
}

/// "1234-56 KOYU BEJ FULAR" gibi alanı parti kodu ve açıklama olarak böler.
(String, String?) _splitParty(String s) {
  final i = s.indexOf(' ');
  return i < 0 ? (s, null) : (s.substring(0, i), s.substring(i + 1));
}

const sevkCeki = DocTemplate(
  id: 'sevk_ceki',
  name: 'Kumaş Sevk Çeki Listesi',
  title: 'Kumaş Sevk Çeki Listesi',
  stockTerm: 'Kumaş',
  labels: ['Firma', 'Açıklama', 'Tarih', 'Evrak No', 'İrsaliye No', 'Parti No', 'Kumaş', 'İşlem', 'Renk', 'Giriş', 'Sıra', 'Barkot', 'Kilo', 'Metre', 'P.Toplam', 'G.Toplam'],
  fields: [
    FieldSpec('firma', 'Firma'),
    FieldSpec('stok', 'Kumaş'),
    FieldSpec('parti.0', 'Parti No'),
    FieldSpec('metre.0', 'Giriş Metre'),
    FieldSpec('kilo.0', 'Giriş Kilo'),
    FieldSpec('top.0', 'Top Adedi', required: false),
    FieldSpec('renk', 'Renk', required: false),
    FieldSpec('islem', 'İşlem', required: false),
    FieldSpec('evrak', 'Evrak No', required: false),
    FieldSpec('tarih', 'Tarih', required: false),
  ],
  read: _readSevkCeki,
);

Map<String, String> _readSevkCeki(Page p) {
  final m = <String, String>{};
  _put(m, 'firma', p.right('Firma') ?? p.lineAbove('Açıklama'));
  _put(m, 'stok', p.right('Kumaş'));
  final parti = p.find(RegExp(r'^P-\d{6}-\d+$'));
  _put(m, 'parti.0', parti.isNotEmpty ? parti.first.text.replaceAll('|', '') : p.right('Parti No'));
  final total = p.matches('G.Toplam').firstOrNull;
  final totals = total == null ? const <String>[] : p.numbersRight(total.box).where((n) => n.contains(RegExp(r'[.,]'))).toList();
  _put(m, 'metre.0', p.numberBefore(_mt) ?? (totals.length > 1 ? totals[1] : null));
  _put(m, 'kilo.0', p.numberBefore(_kg) ?? (totals.isNotEmpty ? totals[0] : null));
  if (total != null) _put(m, 'top.0', p.numbersRight(total.box).where((n) => RegExp(r'^\d+$').hasMatch(n)).firstOrNull);
  _put(m, 'renk', p.right('Renk'));
  _put(m, 'islem', p.right('İşlem'));
  _put(m, 'evrak', firstNumber(p.right('Evrak No')));
  _put(m, 'tarih', dateOf(p.right('Tarih')));
  return m;
}

const kumasCeki = DocTemplate(
  id: 'kumas_ceki',
  name: 'Kumaş Çeki Listesi',
  title: 'Kumaş Çeki Listesi',
  stockTerm: 'Kalite',
  labels: ['Fiş No', 'Firma', 'Açıklama', 'Tarih', 'Fat/İrsaliye No', 'Sipariş No', 'Kalite', 'Model', 'İşlem', 'Desen/Vrynt', 'Renk Kodu', 'Renk Adı', 'İş Emri No', 'P.No', 'Ham PartiNo', 'Ham Giriş', 'Sıra No', 'Top No', 'Kilo', 'Metre'],
  fields: [
    FieldSpec('firma', 'Firma'),
    FieldSpec('stok', 'Kalite'),
    FieldSpec('evrak', 'Fiş No', required: false),
    FieldSpec('tarih', 'Tarih', required: false),
  ],
  lineFields: [
    FieldSpec('parti', 'Parti'),
    FieldSpec('metre', 'Metre'),
    FieldSpec('kilo', 'Kilo'),
    FieldSpec('top', 'Top', required: false),
    FieldSpec('islem', 'İşlem', required: false),
  ],
  read: _readKumasCeki,
);

Map<String, String> _readKumasCeki(Page p) {
  final m = <String, String>{};
  _put(m, 'firma', p.right('Firma'));
  _put(m, 'stok', p.right('Kalite'));
  _put(m, 'evrak', firstNumber(p.right('Fiş No')));
  _put(m, 'tarih', dateOf(p.right('Tarih')));

  // Tek kâğıtta birden çok parti: her bloğun kendi satırı olur.
  final parties = p.find(RegExp(r'^P\d{6,8}$'));
  for (var i = 0; i < parties.length; i++) {
    _put(m, 'parti.$i', parties[i].text.replaceAll('|', ''));
  }

  // Ham giriş bu belgede genelde boş; o zaman bloğun T.Adet toplamı kullanılır.
  // Son bloğun toplamı kâğıdın sağ sütununa taşar, bu yüzden sağdakiler sona alınır.
  final adet = p.words.where((w) => w.norm.startsWith('tadet')).toList();
  if (adet.isNotEmpty) {
    final leftEdge = adet.map((w) => w.box.left).reduce((a, b) => a < b ? a : b);
    final h = adet.first.box.height;
    bool isLeft(OcrWord w) => w.box.left - leftEdge < h * 5;
    adet.sort((a, b) {
      if (isLeft(a) != isLeft(b)) return isLeft(a) ? -1 : 1;
      return a.box.top.compareTo(b.box.top);
    });
    for (var i = 0; i < adet.length; i++) {
      final word = adet[i];
      final nums = p.numbersRight(word.box);
      final decimals = nums.where((n) => n.contains(',')).toList();
      final glued = RegExp(r'(\d+)$').firstMatch(word.text)?.group(1);
      _put(m, 'top.$i', glued ?? nums.where((n) => RegExp(r'^\d+$').hasMatch(n)).firstOrNull);
      if (decimals.length >= 2) {
        _put(m, 'kilo.$i', decimals[0]);
        _put(m, 'metre.$i', decimals[1]);
      }
    }
  }

  final islem = p.rightAll('İşlem');
  for (var i = 0; i < islem.length; i++) {
    _put(m, 'islem.$i', islem[i]);
  }
  return m;
}

const urunSevk = DocTemplate(
  id: 'urun_sevk',
  name: 'Ürün Sevk Fişi',
  title: 'Ürün Sevk Fişi',
  stockTerm: 'Kumaş Cinsi',
  labels: ['Müşteri Adı', 'Sevk Tarih', 'Sevk No', 'Açıklama', 'Parti No', 'Giriş Adet', 'Yapılan İşlem', 'Kumaş Cinsi', 'Giriş İrs. No', 'Giriş Mamul En', 'Giriş Toplam Mt', 'Giriş Toplam Kg', 'Çıkış Adet', 'Araba Adet', 'Not', 'Çıkış İrs. No', 'Çıkış Mamul En', 'Araba Bilgi', 'Toplam Metre', 'Toplam Kg', 'Teslim Eden', 'Teslim Alan'],
  fields: [
    FieldSpec('firma', 'Müşteri Adı'),
    FieldSpec('stok', 'Kumaş Cinsi'),
    FieldSpec('parti.0', 'Parti No'),
    FieldSpec('en.0', 'Mamul En'),
    FieldSpec('metre.0', 'Giriş Metre'),
    FieldSpec('kilo.0', 'Giriş Kilo'),
    FieldSpec('top.0', 'Giriş Adet', required: false),
    FieldSpec('islem', 'Yapılan İşlem', required: false),
    FieldSpec('evrak', 'Sevk No', required: false),
    FieldSpec('tarih', 'Sevk Tarihi', required: false),
  ],
  read: _readUrunSevk,
);

Map<String, String> _readUrunSevk(Page p) {
  final m = <String, String>{};
  _put(m, 'firma', p.right('Müşteri Adı'));
  _put(m, 'stok', p.right('Kumaş Cinsi'));
  _put(m, 'parti.0', firstNumber(p.right('Parti No')) ?? p.right('Parti No'));
  _put(m, 'en.0', firstNumber(p.right('Giriş Mamul En') ?? p.right('Çıkış Mamul En')));
  _put(m, 'metre.0', firstNumber(p.right('Giriş Toplam Mt')) ?? p.numberBefore(_mt));
  _put(m, 'kilo.0', firstNumber(p.right('Giriş Toplam Kg')) ?? p.numberBefore(_kg));
  _put(m, 'top.0', firstNumber(p.right('Giriş Adet')));
  _put(m, 'islem', p.right('Yapılan İşlem'));
  _put(m, 'evrak', firstNumber(p.right('Sevk No')));
  _put(m, 'tarih', dateOf(p.right('Sevk Tarih')));
  return m;
}

const cikisCeki = DocTemplate(
  id: 'cikis_ceki',
  name: 'Çıkış Çeki Listesi',
  title: 'Çıkış Çeki Listesi',
  stockTerm: 'Cinsi',
  labels: ['Müşteri', 'Müş. Parti No', 'İşlem', 'Taşıma Tipi', 'İş Emri', 'Tarih', 'Müşteri KG', 'Müşteri MT', 'Cinsi', 'Mamül En', 'Sevk Tarihi', 'Kod', 'Miktar 1', 'Miktar 2', 'Miktar 3', 'Açıklama', 'Toplam'],
  fields: [
    FieldSpec('firma', 'Müşteri'),
    FieldSpec('parti.0', 'Müşteri Parti No'),
    FieldSpec('en.0', 'Mamül En'),
    FieldSpec('metre.0', 'Müşteri Metre'),
    FieldSpec('kilo.0', 'Kilo'),
    FieldSpec('stok', 'Cinsi', required: false),
    FieldSpec('renk', 'Renk', required: false),
    FieldSpec('islem', 'İşlem', required: false),
    FieldSpec('evrak', 'İş Emri', required: false),
    FieldSpec('tarih', 'Tarih', required: false),
  ],
  read: _readCikisCeki,
);

Map<String, String> _readCikisCeki(Page p) {
  final m = <String, String>{};
  _put(m, 'firma', p.right('Müşteri'));
  _put(m, 'stok', p.right('Cinsi'));
  final party = p.right('Müş. Parti No');
  if (party != null) {
    final (code, rest) = _splitParty(party);
    _put(m, 'parti.0', code);
    _put(m, 'renk', rest);
  }
  _put(m, 'en.0', firstNumber(p.right('Mamül En')));
  _put(m, 'metre.0', firstNumber(p.right('Müşteri MT')) ?? p.numberBefore(_mt));
  // Müşteri KG 0,00 yazıyorsa giriş kilosu verilmemiştir; TOPLAM satırındaki kilo alınır.
  final kilo = firstNumber(p.right('Müşteri KG'));
  _put(m, 'kilo.0', (parseNumber(kilo) ?? 0) > 0 ? kilo : p.numberBefore(_kg));
  _put(m, 'islem', p.right('İşlem'));
  _put(m, 'evrak', p.right('İş Emri'));
  _put(m, 'tarih', dateOf(p.right('Tarih')));
  return m;
}

const kesimTakip = DocTemplate(
  id: 'kesim_takip',
  name: 'Kesim Takip Formu',
  title: 'Kesim Takip Formu',
  stockTerm: 'Kumaş',
  handwritten: true,
  labels: ['Sıra No', 'Müşteri Adı', 'Giriş Tarihi', 'Giriş Mt', 'Çıkış Tarihi', 'Çıkış Mt', 'Top No', 'Metre'],
  fields: [FieldSpec('evrak', 'Form Sıra No')],
  read: _readKesimTakip,
);

Map<String, String> _readKesimTakip(Page p) {
  final m = <String, String>{};
  _put(m, 'evrak', firstNumber(p.right('Sıra No')));
  return m;
}

const kumasIrsaliye = DocTemplate(
  id: 'irsaliye',
  name: 'Kumaş İrsaliyesi',
  title: 'Kumaş İrsaliyesi',
  stockTerm: 'Cinsi',
  handwritten: true,
  labels: ['Sayın', 'İrsaliye No', 'Tarih', 'Cinsi', 'Top', 'Metre', 'Fiyatı', 'Tutarı', 'Toplam'],
  fields: [],
  read: _readNothing,
);

Map<String, String> _readNothing(Page p) => const {};

/// Uzun başlık önce: "Kumaş Sevk Çeki" ile "Kumaş Çeki" karışmaz.
const templates = [sevkCeki, kumasCeki, cikisCeki, urunSevk, kesimTakip, kumasIrsaliye];

/// Uzun başlık önce denenir; aynı başlıkta kullanıcı tanımı hazır tasarımın önüne geçer.
DocTemplate? detectTemplate(List<OcrWord> words, {List<CustomDoc> custom = const []}) {
  final page = Page(words);
  final all = [...custom.map((c) => c.toTemplate()), ...templates];
  final ordered = mergeSorted(all);
  for (final t in ordered) {
    if (page.has(t.title)) return t;
  }
  return null;
}

/// Sıralama kararlıdır: eşit uzunlukta önceki sıra korunur.
List<DocTemplate> mergeSorted(List<DocTemplate> all) {
  final indexed = all.indexed.toList();
  indexed.sort((a, b) {
    final byLength = normalizeText(b.$2.title).length.compareTo(normalizeText(a.$2.title).length);
    return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
