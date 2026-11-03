import 'custom_doc.dart';
import 'page.dart';
import 'templates.dart';

class FieldRow {
  const FieldRow(this.id, this.title, this.required, this.value);
  final String id;
  final String title;
  final bool required;
  final String? value;
}

/// Önce belge türünü bulur, sonra seçilen tek kareden alanlarını okur.
class DocSession {
  DocSession({this.custom = const [], this.framesToDetect = 2});

  final List<CustomDoc> custom;

  /// Tek karelik yanlış tanımayı eler: tür art arda bu kadar karede görülmeli.
  final int framesToDetect;
  DocTemplate? template;
  Map<String, String> values = {};
  String? _candidate;

  /// Yeni bir belge türü kesinleştiyse true döner.
  bool detect(List<OcrWord> words) {
    final found = detectTemplate(words, custom: custom);
    if (found == null || found.id == template?.id) {
      _candidate = null;
      return false;
    }
    if (framesToDetect > 1 && _candidate != found.id) {
      _candidate = found.id;
      return false;
    }
    _candidate = null;
    template = found;
    values = {};
    return true;
  }

  Map<String, String> peek(List<OcrWord> words) {
    final t = template;
    return t == null ? const {} : t.read(t.page(words));
  }

  void read(List<OcrWord> words) => values = peek(words);

  void reset() {
    template = null;
    values = {};
    _candidate = null;
  }

  int get _lineCount => values.keys.where((k) => k.startsWith('parti.')).length;

  List<FieldRow> get rows {
    final t = template;
    if (t == null) return const [];
    final out = [for (final f in t.fields) FieldRow(f.id, f.title, f.required, values[f.id])];
    final lines = _lineCount == 0 ? 1 : _lineCount;
    for (var i = 0; i < lines && t.lineFields.isNotEmpty; i++) {
      for (final f in t.lineFields) {
        final id = '${f.id}.$i';
        out.add(FieldRow(id, lines > 1 ? '${f.title} ${i + 1}' : f.title, f.required, values[id]));
      }
    }
    return out;
  }

  bool get requiredDone => template != null && rows.where((r) => r.required).every((r) => r.value != null);
}
