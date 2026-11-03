import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'ocr/custom_doc.dart';
import 'ocr/page.dart';

/// Demo verisi telefonda tutulur: cariler, stoklar, iş emirleri.
class Store extends ChangeNotifier {
  Store._();
  static final instance = Store._();
  static const _key = 'demo_data_v1';
  static const _docsKey = 'doc_definitions_v1';

  final List<String> customers = [];
  final List<String> stocks = [];
  final List<WorkOrder> orders = [];
  final List<CustomDoc> docs = [];
  int _sequence = 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawDocs = prefs.getString(_docsKey);
    if (rawDocs != null) {
      docs.addAll((jsonDecode(rawDocs) as List).map((e) => CustomDoc.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    }
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    customers.addAll((j['customers'] as List).cast<String>());
    stocks.addAll((j['stocks'] as List).cast<String>());
    orders.addAll((j['orders'] as List).map((e) => WorkOrder.fromJson(e as Map<String, dynamic>)));
    _sequence = j['sequence'] as int;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'customers': customers,
        'stocks': stocks,
        'orders': orders.map((o) => o.toJson()).toList(),
        'sequence': _sequence,
      }),
    );
  }

  /// Kayıtlı ada denk geleni bulur; okuma hatası olan ad da eşleşir (ZNCR → ZİNCİR).
  static String? match(List<String> list, String text) {
    final n = normalizeText(text);
    if (n.isEmpty) return null;
    for (final item in list) {
      if (normalizeText(item) == n) return item;
    }
    for (final item in list) {
      if (isClose(n, normalizeText(item))) return item;
    }
    return null;
  }

  /// İş emrini kaydeder; yoksa cari ve stok da açılır.
  Future<void> create(WorkOrder order) async {
    final customer = match(customers, order.customer);
    if (customer == null) {
      customers.add(order.customer);
    } else {
      order.customer = customer;
    }
    final stock = match(stocks, order.stock);
    if (stock == null) {
      stocks.add(order.stock);
    } else {
      order.stock = stock;
    }
    _sequence++;
    order.number = 'GK-${order.createdAt.year}-${_sequence.toString().padLeft(4, '0')}';
    orders.insert(0, order);
    await _save();
  }

  Future<void> advance(WorkOrder order) async {
    if (order.finished) return;
    order.stage++;
    await _save();
  }

  /// Aynı başlıklı eski tanım yenisiyle değişir.
  Future<void> saveDoc(CustomDoc doc) async {
    docs.removeWhere((d) => normalizeText(d.title) == normalizeText(doc.title));
    docs.insert(0, doc);
    await _saveDocs();
  }

  Future<void> removeDoc(CustomDoc doc) async {
    docs.remove(doc);
    await _saveDocs();
  }

  Future<void> _saveDocs() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_docsKey, jsonEncode(docs.map((d) => d.toJson()).toList()));
  }

  /// İş verilerini siler; belge tanımları kalır.
  Future<void> reset() async {
    customers.clear();
    stocks.clear();
    orders.clear();
    _sequence = 0;
    await _save();
  }
}
