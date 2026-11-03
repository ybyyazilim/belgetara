import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'order_screen.dart';

/// Okunanlar burada görülür ve düzeltilir; onaylanınca iş emri oluşur.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.order, this.handwritten = false});
  final WorkOrder order;
  final bool handwritten;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  WorkOrder get o => widget.order;

  @override
  void initState() {
    super.initState();
    // Kayıtlı ada denk geliyorsa okuma hatası da düzelmiş olur.
    final store = Store.instance;
    o.customer = Store.match(store.customers, o.customer) ?? o.customer;
    o.stock = Store.match(store.stocks, o.stock) ?? o.stock;
  }

  bool get _valid => o.customer.trim().isNotEmpty && o.stock.trim().isNotEmpty;

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    o.customer = o.customer.trim();
    o.stock = o.stock.trim();
    await Store.instance.create(o);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderScreen(order: o, justCreated: true)));
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('İş Emri Taslağı')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          _DocHeader(order: o),
          if (widget.handwritten) ...[
            const SizedBox(height: 10),
            const Text('Bu belge el yazılı. Boş alanları belgeye bakarak doldurun.', style: TextStyle(color: warning)),
          ],
          const SizedBox(height: 14),
          _Section(title: 'Firma ve Stok', children: [
            _field('Firma', o.customer, (v) => o.customer = v,
                badge: _Badge.of(o.customer, Store.match(store.customers, o.customer) != null, 'cari')),
            _field('Stok (belgede: ${o.stockTerm})', o.stock, (v) => o.stock = v,
                badge: _Badge.of(o.stock, Store.match(store.stocks, o.stock) != null, 'stok')),
            _field('Renk', o.color, (v) => o.color = v),
            _field('İşlem / Açıklama', o.note, (v) => o.note = v),
          ]),
          const SizedBox(height: 14),
          for (var i = 0; i < o.lines.length; i++) ...[
            _LineEditor(
              key: ObjectKey(o.lines[i]),
              title: o.lines.length > 1 ? 'Parti ${i + 1}' : 'Parti',
              line: o.lines[i],
              onDelete: o.lines.length > 1 ? () => setState(() => o.lines.removeAt(i)) : null,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 14),
          ],
          OutlinedButton.icon(
            onPressed: () => setState(() => o.lines.add(OrderLine())),
            icon: const Icon(Icons.add),
            label: const Text('Parti ekle'),
          ),
          const SizedBox(height: 14),
          _Section(title: 'Yapılacak İşlemler', children: [
            Wrap(
              spacing: 8,
              children: [
                for (final p in allProcesses)
                  FilterChip(
                    label: Text(p),
                    selected: o.processes.contains(p),
                    selectedColor: amber,
                    checkmarkColor: navy,
                    labelStyle: TextStyle(color: o.processes.contains(p) ? navy : Colors.white, fontWeight: FontWeight.w600),
                    onSelected: (on) => setState(() {
                      if (on) {
                        o.processes = allProcesses.where((x) => x == p || o.processes.contains(x)).toList();
                      } else {
                        o.processes.remove(p);
                      }
                    }),
                  ),
              ],
            ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _valid ? _create : null,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            label: const Text('İş Emri Oluştur'),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged, {Widget? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: value,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: label),
            onChanged: (v) => setState(() => onChanged(v)),
          ),
          if (badge != null) Padding(padding: const EdgeInsets.only(top: 5), child: badge),
        ],
      ),
    );
  }
}

class _DocHeader extends StatelessWidget {
  const _DocHeader({required this.order});
  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (order.docRef.isNotEmpty) 'No: ${order.docRef}',
      if (order.docDate.isNotEmpty) order.docDate,
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: amber, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: navy, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.docName, style: const TextStyle(color: navy, fontSize: 16, fontWeight: FontWeight.w800)),
                if (details.isNotEmpty) Text(details, style: const TextStyle(color: navy, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, this.icon);
  final String text;
  final Color color;
  final IconData icon;

  static Widget? of(String value, bool known, String kind) {
    if (value.trim().isEmpty) return _Badge('Belgede okunamadı, elle girin', warning, Icons.edit_outlined);
    return known
        ? _Badge('Kayıtlı $kind', success, Icons.check_circle_outline)
        : _Badge('Yeni $kind açılacak', amber, Icons.add_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({super.key, required this.title, required this.line, required this.onChanged, this.onDelete});
  final String title;
  final OrderLine line;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  Widget _box(String label, String value, ValueChanged<String> set, {bool flagEmpty = false, bool numeric = true}) {
    return TextFormField(
      initialValue: value,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        enabledBorder: flagEmpty && value.isEmpty
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: warning))
            : null,
      ),
      onChanged: (v) {
        set(v);
        onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (onDelete != null)
                IconButton(onPressed: onDelete, tooltip: 'Partiyi sil', visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, color: muted)),
            ]),
            const SizedBox(height: 8),
            _box('Parti No', line.party, (v) => line.party = v, flagEmpty: true, numeric: false),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _box('En (cm)', line.width, (v) => line.width = v, flagEmpty: true)),
              const SizedBox(width: 10),
              Expanded(child: _box('Top', line.rolls, (v) => line.rolls = v)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _box('Giriş Metre', line.meters, (v) => line.meters = v, flagEmpty: true)),
              const SizedBox(width: 10),
              Expanded(child: _box('Giriş Kilo', line.kilos, (v) => line.kilos = v, flagEmpty: true)),
            ]),
            if (line.process.isNotEmpty) ...[
              const SizedBox(height: 10),
              _box('Parti İşlemi', line.process, (v) => line.process = v, numeric: false),
            ],
          ],
        ),
      ),
    );
  }
}
