import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ocr/custom_doc.dart';
import '../ocr/still.dart';
import '../ocr/templates.dart';
import '../store.dart';
import '../theme.dart';
import 'define_screen.dart';
import 'scan_screen.dart';

/// Kullanıcının tanımladığı belgeler ve yeni tanım başlatma.
class DefinitionsScreen extends StatelessWidget {
  const DefinitionsScreen({super.key});

  Future<void> _new(BuildContext context, {bool fromPhoto = false}) async {
    final nav = Navigator.of(context);
    final picked = fromPhoto ? await ImagePicker().pickImage(source: ImageSource.gallery) : null;
    if (fromPhoto && picked == null) return;
    final bytes = await picked?.readAsBytes();
    final still = await nav.push<Still>(
      MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes, learn: true), fullscreenDialog: true),
    );
    if (still == null) return;
    nav.push(MaterialPageRoute(builder: (_) => DefineScreen(still: still)));
  }

  Future<void> _delete(BuildContext context, CustomDoc doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tanım silinsin mi?'),
        content: Text(doc.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (yes == true) await Store.instance.removeDoc(doc);
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Belge Tanımları')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Text('Yeni bir belge türü tarayın, ihtiyacınız olan alanları belgenin üzerinden seçin.', style: TextStyle(color: muted)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _new(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Yeni Belge Tanımla'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _new(context, fromPhoto: true),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Fotoğraftan Tanımla'),
            ),
            const SizedBox(height: 22),
            if (store.docs.isNotEmpty) ...[
              const Text('Tanımladıklarım', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final d in store.docs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined, color: amber),
                    title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${d.fields.length} alan · başlık: ${d.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Tanımı sil',
                      onPressed: () => _delete(context, d),
                      icon: const Icon(Icons.delete_outline, color: muted),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
            ],
            const Text('Hazır tanımlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final t in templates)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  const Icon(Icons.verified_outlined, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.name, style: const TextStyle(color: muted))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
