import 'ocr/page.dart';
import 'ocr/templates.dart';

/// "3.935,00" biçiminde yazar.
String formatNumber(double? value, {int decimals = 2}) {
  if (value == null) return '-';
  final fixed = value.toStringAsFixed(decimals).split('.');
  final buffer = StringBuffer();
  final whole = fixed[0];
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  return decimals == 0 ? buffer.toString() : '$buffer,${fixed[1]}';
}

class OrderLine {
  OrderLine({this.party = '', this.width = '', this.meters = '', this.kilos = '', this.rolls = '', this.process = ''});
  String party;
  String width;
  String meters;
  String kilos;
  String rolls;
  String process;

  Map<String, dynamic> toJson() =>
      {'party': party, 'width': width, 'meters': meters, 'kilos': kilos, 'rolls': rolls, 'process': process};
  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        party: j['party'] as String,
        width: j['width'] as String,
        meters: j['meters'] as String,
        kilos: j['kilos'] as String,
        rolls: j['rolls'] as String,
        process: j['process'] as String,
      );
}

/// Bilinen kumaş adları: okuma hatasını düzeltir (ziİNCİR → ZİNCİR, BRODE (İPL) → BRODE (İPLİ)).
const knownFabrics = ['ZİNCİR', 'BRODE (İPLİ)', 'MAT KREP', 'FULAR'];

String correctFabric(String text) {
  final n = normalizeText(text);
  for (final fabric in knownFabrics) {
    if (isClose(n, normalizeText(fabric))) return fabric;
  }
  return text;
}

const allProcesses = ['Kurşun', 'Tambur'];

class WorkOrder {
  WorkOrder({
    this.number = '',
    DateTime? createdAt,
    required this.docName,
    required this.stockTerm,
    this.docRef = '',
    this.docDate = '',
    this.customer = '',
    this.stock = '',
    this.color = '',
    this.note = '',
    List<OrderLine>? lines,
    List<String>? processes,
    this.stage = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        lines = lines ?? [OrderLine()],
        processes = processes ?? [...allProcesses];

  String number;
  DateTime createdAt;
  String docName;
  String stockTerm;
  String docRef;
  String docDate;
  String customer;
  String stock;
  String color;
  String note;
  List<OrderLine> lines;
  List<String> processes;
  int stage;

  /// Sürecin aşamaları: kabul, seçilen işlemler, sevk.
  List<String> get stages => ['Kabul', ...processes, 'Sevk'];
  bool get finished => stage >= stages.length - 1;
  double get totalMeters => lines.fold(0, (s, l) => s + (parseNumber(l.meters) ?? 0));
  double get totalKilos => lines.fold(0, (s, l) => s + (parseNumber(l.kilos) ?? 0));
  double get totalRolls => lines.fold(0, (s, l) => s + (parseNumber(l.rolls) ?? 0));

  Map<String, dynamic> toJson() => {
        'number': number,
        'createdAt': createdAt.toIso8601String(),
        'docName': docName,
        'stockTerm': stockTerm,
        'docRef': docRef,
        'docDate': docDate,
        'customer': customer,
        'stock': stock,
        'color': color,
        'note': note,
        'lines': lines.map((l) => l.toJson()).toList(),
        'processes': processes,
        'stage': stage,
      };

  factory WorkOrder.fromJson(Map<String, dynamic> j) => WorkOrder(
        number: j['number'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        docName: j['docName'] as String,
        stockTerm: j['stockTerm'] as String,
        docRef: j['docRef'] as String,
        docDate: j['docDate'] as String,
        customer: j['customer'] as String,
        stock: j['stock'] as String,
        color: j['color'] as String,
        note: j['note'] as String,
        lines: (j['lines'] as List).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
        processes: (j['processes'] as List).cast<String>(),
        stage: j['stage'] as int,
      );

  /// Okunan alanlardan taslak iş emri.
  factory WorkOrder.fromScan(DocTemplate t, Map<String, String> v) {
    final indexes = v.keys
        .where((k) => k.contains('.'))
        .map((k) => int.parse(k.split('.').last))
        .fold<int>(0, (a, b) => a > b ? a : b);
    return WorkOrder(
      docName: t.name,
      stockTerm: t.stockTerm,
      docRef: v['evrak'] ?? '',
      docDate: v['tarih'] ?? '',
      customer: v['firma'] ?? '',
      stock: correctFabric(v['stok'] ?? ''),
      color: v['renk'] ?? '',
      note: v['islem'] ?? '',
      lines: [
        for (var i = 0; i <= indexes; i++)
          OrderLine(
            party: v['parti.$i'] ?? '',
            width: _clean(v['en.$i']),
            meters: _clean(v['metre.$i']),
            kilos: _clean(v['kilo.$i']),
            rolls: v['top.$i'] ?? '',
            process: v['islem.$i'] ?? '',
          ),
      ],
    );
  }
}

/// Okunan sayıyı tek biçime getirir: 198.10 → 198,10.
String _clean(String? raw) {
  final n = parseNumber(raw);
  if (n == null) return '';
  return formatNumber(n, decimals: n == n.roundToDouble() ? 0 : 2);
}
