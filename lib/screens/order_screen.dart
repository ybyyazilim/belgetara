import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../order_pdf.dart';
import '../store.dart';
import '../theme.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.order, this.justCreated = false});
  final WorkOrder order;
  final bool justCreated;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  WorkOrder get o => widget.order;

  void _openPdf() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(o.number)),
        body: PdfPreview(
          build: (_) => buildOrderPdf(o),
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          pdfFileName: '${o.number}.pdf',
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(o.number)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          if (widget.justCreated) ...[const _CreatedBanner(), const SizedBox(height: 14)],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.customer, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text([o.stock, o.color].where((s) => s.isNotEmpty).join('  ·  '), style: const TextStyle(color: amber, fontWeight: FontWeight.w600)),
                  if (o.note.isNotEmpty) Text(o.note, style: const TextStyle(color: muted)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _Total('Metre', formatNumber(o.totalMeters)),
                    _Total('Kilo', formatNumber(o.totalKilos)),
                    _Total('Top', formatNumber(o.totalRolls, decimals: 0)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Süreç', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _StageBar(order: o),
          const SizedBox(height: 10),
          if (!o.finished)
            OutlinedButton.icon(
              onPressed: () async {
                await Store.instance.advance(o);
                setState(() {});
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text('${o.stages[o.stage + 1]} aşamasına geçir'),
            ),
          const SizedBox(height: 14),
          Text('Partiler (${o.lines.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final l in o.lines) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.party.isEmpty ? 'Parti no yok' : l.party, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (l.process.isNotEmpty) Text(l.process, style: const TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(children: [
                      _Mini('En', l.width.isEmpty ? '-' : '${l.width} cm'),
                      _Mini('Metre', l.meters.isEmpty ? '-' : l.meters),
                      _Mini('Kilo', l.kilos.isEmpty ? '-' : l.kilos),
                      _Mini('Top', l.rolls.isEmpty ? '-' : l.rolls),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Kaynak: ${o.docName}${o.docRef.isEmpty ? '' : ' · ${o.docRef}'}${o.docDate.isEmpty ? '' : ' · ${o.docDate}'}',
              style: const TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(onPressed: _openPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF Görüntüle')),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              width: 56,
              child: IconButton.outlined(
                tooltip: 'Paylaş',
                onPressed: () async => Printing.sharePdf(bytes: await buildOrderPdf(o), filename: '${o.number}.pdf'),
                icon: const Icon(Icons.share_outlined, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CreatedBanner extends StatelessWidget {
  const _CreatedBanner();
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Transform.scale(scale: v, child: c),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: success.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14), border: Border.all(color: success)),
        child: const Row(children: [
          Icon(Icons.check_circle, color: success),
          SizedBox(width: 10),
          Expanded(child: Text('İş emri oluşturuldu ve sürece alındı', style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: muted, fontSize: 12.5)),
        ]),
      );
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.order});
  final WorkOrder order;
  @override
  Widget build(BuildContext context) {
    final stages = order.stages;
    return Row(
      children: [
        for (var i = 0; i < stages.length; i++)
          Expanded(
            child: Column(children: [
              Row(children: [
                Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= order.stage ? amber : navyLine))),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i <= order.stage ? amber : navyLight, border: Border.all(color: i <= order.stage ? amber : navyLine)),
                  child: i <= order.stage ? const Icon(Icons.check, size: 17, color: navy) : null,
                ),
                Expanded(child: Container(height: 3, color: i == stages.length - 1 ? Colors.transparent : (i < order.stage ? amber : navyLine))),
              ]),
              const SizedBox(height: 5),
              Text(stages[i], style: TextStyle(fontSize: 12.5, color: i <= order.stage ? Colors.white : muted, fontWeight: i == order.stage ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
      ],
    );
  }
}
