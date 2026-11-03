import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Page;

import '../ocr/custom_doc.dart';
import '../ocr/page.dart';
import '../ocr/still.dart';
import '../store.dart';
import '../theme.dart';

class _Pick {
  List<OcrWord> value = [];
  List<OcrWord> label = [];
}

/// Dondurulmuş belge üzerinde başlığı ve alanları dokunarak seçtirir.
class DefineScreen extends StatefulWidget {
  const DefineScreen({super.key, required this.still});
  final Still still;

  @override
  State<DefineScreen> createState() => _DefineScreenState();
}

class _DefineScreenState extends State<DefineScreen> {
  static const _titleKey = 'baslik';

  ui.Image? _image;
  final List<OcrWord> _title = [];
  final Map<String, _Pick> _picks = {};
  String _current = _titleKey;
  bool _editingLabel = false;

  List<OcrWord> get _words => widget.still.words;
  Page get _page => Page(_words);

  @override
  void initState() {
    super.initState();
    widget.still.toImage().then((image) {
      if (mounted) {
        setState(() => _image = image);
      } else {
        image.dispose();
      }
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _tap(Offset local, Size canvas) {
    final size = widget.still.size;
    final point = Offset(local.dx * size.width / canvas.width, local.dy * size.height / canvas.height);
    OcrWord? hit;
    var bestDistance = double.infinity;
    for (final w in _words) {
      final r = w.raw;
      if (!r.inflate(r.shortestSide * 0.6).contains(point)) continue;
      final d = (r.center - point).distance;
      if (d < bestDistance) {
        bestDistance = d;
        hit = w;
      }
    }
    if (hit == null) return;
    final word = hit;
    setState(() {
      if (_current == _titleKey) {
        _toggle(_title, word);
        return;
      }
      final pick = _picks.putIfAbsent(_current, _Pick.new);
      if (_editingLabel) {
        pick.value.remove(word);
        _toggle(pick.label, word);
      } else {
        pick.label.remove(word);
        _toggle(pick.value, word);
        pick.label = [...inferLabel(_page, pick.value)];
      }
    });
  }

  void _toggle(List<OcrWord> list, OcrWord word) {
    if (!list.remove(word)) list.add(word);
  }

  CustomField? _fieldOf(String key) {
    final pick = _picks[key];
    if (pick == null || pick.value.isEmpty || pick.label.isEmpty) return null;
    Rect union(List<OcrWord> l) => l.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
    return CustomField(
      key,
      joinWords(pick.label),
      sideOf(union(pick.label), union(pick.value)),
      stops: stopsAround(_page, pick.value, pick.label),
    );
  }

  CustomDoc _build(String name) => CustomDoc(
        id: 'custom_${normalizeText(joinWords(_title))}',
        name: name,
        title: joinWords(_title),
        fields: [
          for (final key in _picks.keys)
            if (_fieldOf(key) != null) _fieldOf(key)!,
        ],
      );

  /// Tanım bu belgeye uygulanınca her alanın ne okuduğu; kullanıcı anında görür.
  Map<String, String> get _preview {
    if (_title.isEmpty) return const {};
    final t = _build('').toTemplate();
    return t.read(t.page(_words));
  }

  bool get _canSave => _title.isNotEmpty && _build('').fields.isNotEmpty;

  void _next() {
    final keys = [_titleKey, for (final f in definableFields) f.id];
    final i = keys.indexOf(_current);
    setState(() {
      _current = keys[(i + 1) % keys.length];
      _editingLabel = false;
    });
  }

  Future<void> _save() async {
    final controller = TextEditingController(text: joinWords(_title));
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Belgenin adı'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await Store.instance.saveDoc(_build(name));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name tanımlandı. Artık taramada tanınır.')));
    Navigator.of(context).pop();
  }

  String _titleOf(String key) => key == _titleKey ? 'Belge Başlığı' : definableFields.firstWhere((f) => f.id == key).title;

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final size = widget.still.size;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Belge Tanımı'),
        actions: [
          TextButton(onPressed: _canSave ? _save : null, child: const Text('Kaydet')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: InteractiveViewer(
                maxScale: 8,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: size.width / size.height,
                    child: LayoutBuilder(
                      builder: (_, box) => GestureDetector(
                        onTapUp: (d) => _tap(d.localPosition, box.biggest),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (image != null) RawImage(image: image, fit: BoxFit.fill),
                            CustomPaint(
                              painter: _SelectionPainter(
                                words: _words,
                                frame: size,
                                title: _title,
                                picks: _picks,
                                current: _current,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _panel(),
        ],
      ),
    );
  }

  Widget _panel() {
    final preview = _preview;
    final isTitle = _current == _titleKey;
    final pick = _picks[_current];
    return Container(
      color: navyLight,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip(_titleKey, _title.isNotEmpty),
                    for (final f in definableFields) _chip(f.id, preview.containsKey(f.id)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTitle
                          ? 'Belgeyi tanıtan başlığa dokunun.'
                          : _editingLabel
                              ? '${_titleOf(_current)} etiketinin kelimelerine dokunun.'
                              : '${_titleOf(_current)} değerine dokunun. Yakınlaştırabilirsiniz.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    if (isTitle)
                      Text(_title.isEmpty ? 'Henüz seçilmedi' : joinWords(_title), style: const TextStyle(color: muted))
                    else ...[
                      Text(
                        pick == null || pick.value.isEmpty ? 'Henüz seçilmedi' : 'Etiket: ${pick.label.isEmpty ? 'bulunamadı, elle seçin' : joinWords(pick.label)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pick != null && pick.value.isNotEmpty && pick.label.isEmpty ? warning : muted),
                      ),
                      if (pick != null && pick.value.isNotEmpty)
                        Text(
                          preview[_current] == null ? 'Bu seçimle değer okunamadı; etiketi değiştirin.' : 'Okunan: ${preview[_current]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: preview[_current] == null ? warning : success, fontWeight: FontWeight.w600),
                        ),
                    ],
                    Row(
                      children: [
                        if (!isTitle && pick != null && pick.value.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _editingLabel = !_editingLabel),
                            child: Text(_editingLabel ? 'Değer seçimine dön' : 'Etiketi değiştir'),
                          ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _next,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Sonraki'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String key, bool done) {
    final selected = _current == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        selectedColor: amber,
        avatar: done ? Icon(Icons.check_circle, size: 17, color: selected ? navy : success) : null,
        labelStyle: TextStyle(color: selected ? navy : Colors.white, fontWeight: FontWeight.w600),
        label: Text(_titleOf(key)),
        onSelected: (_) => setState(() {
          _current = key;
          _editingLabel = false;
        }),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.words, required this.frame, required this.title, required this.picks, required this.current});
  final List<OcrWord> words;
  final Size frame;
  final List<OcrWord> title;
  final Map<String, _Pick> picks;
  final String current;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / frame.width, sy = size.height / frame.height;
    Rect scale(Rect b) => Rect.fromLTRB(b.left * sx, b.top * sy, b.right * sx, b.bottom * sy);
    final idle = Paint()
      ..color = amber.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    void mark(OcrWord w, Color color, double alpha) {
      canvas.drawRect(scale(w.raw), Paint()..color = color.withValues(alpha: alpha));
      canvas.drawRect(
        scale(w.raw),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    for (final w in words) {
      canvas.drawRect(scale(w.raw), idle);
    }
    for (final w in title) {
      mark(w, Colors.lightBlueAccent, 0.35);
    }
    picks.forEach((key, pick) {
      final active = key == current;
      for (final w in pick.label) {
        mark(w, amber, active ? 0.45 : 0.15);
      }
      for (final w in pick.value) {
        mark(w, success, active ? 0.5 : 0.25);
      }
    });
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}
