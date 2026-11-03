import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'definitions_screen.dart';
import 'order_screen.dart';
import 'review_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _scan(BuildContext context, {bool fromPhoto = false}) async {
    final nav = Navigator.of(context);
    final photo = fromPhoto ? await ImagePicker().pickImage(source: ImageSource.gallery) : null;
    if (fromPhoto && photo == null) return;
    final bytes = await photo?.readAsBytes();
    final outcome = await nav.push<ScanOutcome>(
      MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes), fullscreenDialog: true),
    );
    if (outcome == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => ReviewScreen(
        order: WorkOrder.fromScan(outcome.template, outcome.values),
        handwritten: outcome.template.handwritten,
      ),
    ));
  }

  Future<void> _confirmReset(BuildContext context) async {
    final yes = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: navyLight,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Demo sıfırlansın mı?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Tüm iş emirleri, cariler ve stoklar silinir. Belge tanımları kalır.', style: TextStyle(color: muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sıfırla')),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          ]),
        ),
      ),
    );
    if (yes == true) await Store.instance.reset();
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Image.asset('assets/logo.png', height: 64),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Demoyu sıfırla',
                    onPressed: () => _confirmReset(context),
                    icon: const Icon(Icons.restart_alt, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Belgeyi okut, iş emrin hazır olsun.', style: TextStyle(color: muted, fontSize: 15)),
              const SizedBox(height: 18),
              Row(children: [
                _Stat('İş Emri', store.orders.length, Icons.assignment_outlined),
                const SizedBox(width: 10),
                _Stat('Firma', store.customers.length, Icons.apartment_outlined),
                const SizedBox(width: 10),
                _Stat('Stok', store.stocks.length, Icons.layers_outlined),
              ]),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _scan(context),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(68)),
                icon: const Icon(Icons.document_scanner_outlined, size: 28),
                label: const Text('Belge Tara', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _scan(context, fromPhoto: true),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Fotoğraftan Oku'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DefinitionsScreen())),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: Text(store.docs.isEmpty ? 'Belge Tanımları' : 'Belge Tanımları (${store.docs.length})'),
              ),
              const SizedBox(height: 24),
              const Text('İş Emirleri', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (store.orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('Henüz iş emri yok. İlk belgeyi tarayın.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
                ),
              for (final o in store.orders) ...[
                _OrderCard(order: o),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: amber, size: 20),
            const SizedBox(height: 6),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value),
              duration: const Duration(milliseconds: 500),
              builder: (_, v, __) => Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Text(label, style: const TextStyle(color: muted, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderScreen(order: o))),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(o.number, style: const TextStyle(color: amber, fontWeight: FontWeight.w700, fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: o.finished ? success.withValues(alpha: 0.18) : navy, borderRadius: BorderRadius.circular(12)),
                  child: Text(o.stages[o.stage], style: TextStyle(fontSize: 12, color: o.finished ? success : Colors.white, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(o.customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                '${o.stock}  ·  ${formatNumber(o.totalMeters)} mt  ·  ${formatNumber(o.totalKilos)} kg',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
