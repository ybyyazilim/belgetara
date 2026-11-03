import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../camera_frame.dart';
import '../image_input.dart';
import '../models.dart';
import '../ocr/doc_session.dart';
import '../ocr/page.dart';
import '../ocr/still.dart';
import '../ocr/templates.dart';
import '../store.dart';
import '../theme.dart';

class ScanOutcome {
  const ScanOutcome(this.template, this.values);
  final DocTemplate template;
  final Map<String, String> values;
}

/// Kameradan gelen ham kare (parlaklık düzlemi).
class RawFrame {
  const RawFrame(this.y, this.width, this.height, this.stride);
  final Uint8List y;
  final int width;
  final int height;
  final int stride;

  factory RawFrame.of(CameraImage image) {
    final plane = image.planes.first;
    return RawFrame(plane.bytes, image.width, image.height, plane.bytesPerRow);
  }
}

/// Sabit tutma süresinde görülen en iyi kare.
class _Candidate {
  _Candidate(this.nv21, this.width, this.height, this.words, this.fields, this.sharpness);
  final Uint8List nv21;
  final int width;
  final int height;
  final List<OcrWord> words;
  final int fields;
  final double sharpness;

  /// Çok alan okunan kare önce gelir; eşitse net olan.
  bool beats(_Candidate o) => fields != o.fields ? fields > o.fields : sharpness > o.sharpness;
}

/// Belgeyi tanır, kamera 2 sn kıpırdamazsa en iyi kareyi dondurur ve onu okur.
/// [learn] açıkken tür aranmaz: dondurulan kare [Still] olarak döner (belge tanımı).
/// [photo] verilirse kamera yerine o fotoğraf kullanılır.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.photo, this.learn = false, this.frames});
  final Uint8List? photo;
  final bool learn;

  /// Kamera yerine kare akışı; yalnız denemede kullanılır.
  final Stream<RawFrame>? frames;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  static const _minWordsToLearn = 8;

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _hold = HoldTracker();
  late final DocSession _session = DocSession(
    custom: Store.instance.docs,
    framesToDetect: widget.photo == null ? 2 : 1,
  );
  CameraController? _camera;
  StreamSubscription<RawFrame>? _frameFeed;
  String? _error;
  bool _busy = false;
  bool _starting = false;
  bool _done = false;
  bool _armed = false; // belge bulundu, sabit tutma sayılıyor
  bool _frozen = false;
  bool _askRetry = false; // zorunlu alan eksik: tekrar mı, devam mı
  int _generation = 0; // kamera kıpırdayınca artar; eski kare aday olamaz
  int _sensor = 90;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  _Candidate? _best;
  ui.Image? _stillImage;
  List<Rect> _boxes = const [];
  Size _frame = Size.zero;
  Set<String>? _revealed; // alanlar sırayla açılır

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.photo != null) {
      _readPhoto();
    } else if (widget.frames != null) {
      _frameFeed = widget.frames!.listen(_onFrame);
    } else {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameFeed?.cancel();
    _camera?.dispose();
    _recognizer.close();
    _stillImage?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.photo != null || widget.frames != null) return;
    // Uygulama arka plana geçince kamera bırakılır, dönünce yeniden açılır.
    if (state == AppLifecycleState.inactive) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        !_starting &&
        !_done &&
        !_frozen &&
        _error == null) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    // İzin penceresi kapanınca gelen "resumed" ikinci bir kamera açmasın.
    _starting = true;
    CameraController? camera;
    try {
      final cameras = await availableCameras();
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      camera = CameraController(
        description,
        ResolutionPreset.veryHigh, // küçük yazılar için 1080p
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _sensor = description.sensorOrientation;
      await camera.startImageStream((image) => _onFrame(RawFrame.of(image)));
      setState(() => _camera = camera);
    } on CameraException catch (e) {
      await camera?.dispose();
      if (mounted) {
        setState(
          () => _error =
              e.code.contains('AccessDenied') || e.code.contains('Permission')
              ? 'Kamera izni verilmedi. Telefon ayarlarından izin verip tekrar deneyin.'
              : 'Kamera açılamadı: ${e.description ?? e.code}',
        );
      }
    } on StateError {
      if (mounted) setState(() => _error = 'Bu cihazda kamera bulunamadı.');
    } finally {
      _starting = false;
    }
  }

  void _onFrame(RawFrame image) {
    if (_frozen || _done) return;
    final now = DateTime.now();
    if (now.difference(_lastTick) >= const Duration(milliseconds: 100)) {
      _lastTick = now;
      final signature = motionSignature(image.y, image.width, image.height, image.stride);
      if (_hold.update(signature, now)) {
        _generation++;
        _best = null;
      }
      if (_armed) {
        if (_hold.done(now) && _best != null) {
          _freeze();
          return;
        }
        setState(() {}); // geri sayım
      }
    }
    if (!_busy) _readFrame(image);
  }

  // Okuyucu meşgulken gelen kareler atlanır; telefon bu sayede kasmaz.
  Future<void> _readFrame(RawFrame image) async {
    _busy = true;
    final generation = _generation;
    try {
      final width = image.width, height = image.height;
      final nv21 = yPlaneToNv21(image.y, width, height, image.stride);
      final input = nv21Input(nv21, width, height, _sensor);
      if (input == null) return;
      final text = await _recognizer.processImage(input);
      if (!mounted || _frozen || _done) return;
      final sideways = _sensor % 180 != 0;
      final frame = sideways
          ? Size(height.toDouble(), width.toDouble())
          : Size(width.toDouble(), height.toDouble());
      final words = wordsFrom(text, frame, sensorSize: Size(width.toDouble(), height.toDouble()), rotation: _sensor);

      if (widget.learn) {
        if (!_armed && words.length >= _minWordsToLearn) _arm();
      } else if (_session.detect(words)) {
        HapticFeedback.mediumImpact();
        _best = null;
        _arm();
      }
      if (_armed && generation == _generation) {
        final fields = widget.learn ? words.length : _session.peek(words).length;
        final candidate = _Candidate(nv21, width, height, words, fields, sharpnessOf(nv21, width, height));
        final best = _best;
        if (best == null || candidate.beats(best)) _best = candidate;
      }
      setState(() {
        _frame = frame;
        _boxes = words.map((w) => w.raw).toList();
      });
    } catch (e) {
      debugPrint('Kare okunamadı: $e');
    } finally {
      _busy = false;
    }
  }

  void _arm() {
    _armed = true;
    _hold.restart(DateTime.now());
  }

  Future<void> _freeze() async {
    final best = _best;
    if (best == null || _frozen) return;
    _frozen = true;
    HapticFeedback.heavyImpact();
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    final still = Still(best.nv21, best.width, best.height, _sensor, best.words);
    final image = await still.toImage();
    if (!mounted) {
      image.dispose();
      return;
    }
    if (widget.learn) {
      image.dispose();
      Navigator.of(context).pop(still);
      return;
    }
    _session.read(best.words);
    setState(() {
      _stillImage = image;
      _frame = still.size;
      _boxes = best.words.map((w) => w.raw).toList();
      _revealed = {};
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _reveal();
    if (!mounted) return;
    if (_session.requiredDone) {
      _finish();
    } else {
      setState(() => _askRetry = true);
    }
  }

  Future<void> _retry() async {
    final old = _stillImage;
    setState(() {
      _frozen = false;
      _armed = false;
      _askRetry = false;
      _best = null;
      _stillImage = null;
      _revealed = null;
      _boxes = const [];
    });
    old?.dispose();
    _session.reset();
    _generation++;
    if (widget.frames != null) return;
    final camera = _camera;
    if (camera == null) {
      await _startCamera();
    } else {
      await camera.startImageStream((image) => _onFrame(RawFrame.of(image)));
    }
  }

  Future<void> _reveal() async {
    for (final row in _session.rows.where((r) => r.value != null)) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _revealed!.add(row.id));
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
  }

  Future<void> _readPhoto() async {
    try {
      final photo = await DecodedPhoto.fromBytes(widget.photo!);
      final frame = Size(photo.width.toDouble(), photo.height.toDouble());
      final text = await _recognizer.processImage(
        photo.toInput(InputImageRotation.rotation0deg),
      );
      if (!mounted) return;
      final words = wordsFrom(text, frame);
      if (widget.learn) {
        if (words.length < _minWordsToLearn) {
          setState(() => _error = 'Bu fotoğrafta yeterince yazı okunamadı.');
          return;
        }
        Navigator.of(context).pop(Still(photo.nv21, photo.width, photo.height, 0, words));
        return;
      }
      _session.detect(words);
      _session.read(words);
      setState(() {
        _frame = frame;
        _boxes = words.map((w) => w.raw).toList();
        _revealed = {};
        if (_session.template == null) {
          _error = 'Bu belge tanınamadı. Başka bir fotoğraf deneyin ya da belge tanımı yapın.';
        }
      });
      if (_session.template == null) return;
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _reveal();
      _finish();
    } catch (e) {
      debugPrint('Fotoğraf okunamadı: $e');
      if (mounted) setState(() => _error = 'Fotoğraf okunamadı.');
    }
  }

  Future<void> _finish() async {
    if (_done || !mounted) return;
    final template = _session.template;
    if (template == null) return;
    setState(() {
      _done = true;
      _askRetry = false;
    });
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (mounted) {
      Navigator.of(context).pop(ScanOutcome(template, Map.of(_session.values)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final photo = widget.photo;
    final still = _stillImage;
    Widget? preview;
    if (photo != null) {
      preview = Image.memory(photo, fit: BoxFit.contain);
    } else if (still != null) {
      preview = RawImage(image: still, fit: BoxFit.fill);
    } else if (camera != null && camera.value.isInitialized) {
      preview = CameraPreview(camera);
    }
    final aspect = _frame != Size.zero
        ? _frame.width / _frame.height
        : (camera != null && camera.value.isInitialized
              ? 1 / camera.value.aspectRatio
              : 9 / 16);
    // Kumaş adı panelde de düzeltilmiş görünür.
    final rows = [
      for (final r in _session.rows)
        FieldRow(
          r.id,
          r.title,
          r.required,
          _revealed == null || !_revealed!.contains(r.id)
              ? null
              : (r.id == 'stok' && r.value != null ? correctFabric(r.value!) : r.value),
        ),
    ];
    final holding = _armed && !_frozen;
    return ScanView(
      template: _session.template,
      rows: rows,
      showFields: _revealed != null,
      complete: _done,
      frozen: _stillImage != null,
      showGuide: photo == null && !_frozen,
      holdProgress: holding ? _hold.progress(DateTime.now()) : null,
      status: widget.learn ? (holding ? 'Belgeyi sabit tutun' : 'Tanıtılacak belgeyi kadraja alın') : null,
      error: _error,
      preview: preview,
      previewAspect: aspect,
      boxes: _boxes,
      frame: _frame,
      onClose: () => Navigator.of(context).pop(),
      onShoot: holding && _best != null ? _freeze : null,
      onRetry: _askRetry ? _retry : null,
      onContinue: _askRetry ? _finish : null,
    );
  }
}

/// Tarama ekranının görünümü; kameradan bağımsızdır.
class ScanView extends StatelessWidget {
  const ScanView({
    super.key,
    required this.template,
    required this.rows,
    required this.complete,
    required this.onClose,
    this.showFields = true,
    this.frozen = false,
    this.showGuide = false,
    this.holdProgress,
    this.status,
    this.onShoot,
    this.onRetry,
    this.onContinue,
    this.preview,
    this.previewAspect = 9 / 16,
    this.boxes = const [],
    this.frame = Size.zero,
    this.error,
  });

  final DocTemplate? template;
  final List<FieldRow> rows;
  final bool complete;
  final VoidCallback onClose;
  final bool showFields;
  final bool frozen;
  final bool showGuide;

  /// Sabit tutma ilerlemesi (0-1); sayım yoksa null.
  final double? holdProgress;
  final String? status;
  final VoidCallback? onShoot;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;
  final Widget? preview;
  final double previewAspect;
  final List<Rect> boxes;
  final Size frame;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: preview == null
                ? _placeholder()
                : AspectRatio(
                    aspectRatio: previewAspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        preview!,
                        CustomPaint(painter: _WordsPainter(boxes, frame)),
                        if (template == null && error == null && holdProgress == null)
                          const _ScanLine(),
                        if (frozen) const _ShutterFlash(),
                      ],
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onClose,
                      tooltip: 'Kapat',
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        heightFactor: 1,
                        alignment: Alignment.centerLeft,
                        child: _StatusPill(
                          template: template,
                          status: status,
                          error: preview == null ? null : error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showGuide)
            IgnorePointer(
              child: CustomPaint(painter: _CornerGuide(holdProgress == null ? Colors.white : amber)),
            ),
          if (holdProgress != null) ...[
            Center(child: _HoldRing(progress: holdProgress!)),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: FilledButton.icon(
                    onPressed: onShoot,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Şimdi çek'),
                  ),
                ),
              ),
            ),
          ],
          if (template != null && showFields)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: _FieldPanel(
                  template: template!,
                  rows: rows,
                  onRetry: onRetry,
                  onContinue: onContinue,
                ),
              ),
            ),
          if (complete) const _CompleteBadge(),
        ],
      ),
    );
  }

  Widget _placeholder() {
    if (error == null) return const CircularProgressIndicator(color: amber);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

/// Okuyucunun gördüğü kelimeleri ince çerçeveyle gösterir.
class _WordsPainter extends CustomPainter {
  _WordsPainter(this.boxes, this.frame);
  final List<Rect> boxes;
  final Size frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame == Size.zero) return;
    final sx = size.width / frame.width, sy = size.height / frame.height;
    final fill = Paint()..color = amber.withValues(alpha: 0.16);
    final line = Paint()
      ..color = amber.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final b in boxes) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(b.left * sx, b.top * sy, b.right * sx, b.bottom * sy),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, line);
    }
  }

  @override
  bool shouldRepaint(_WordsPainter old) => old.boxes != boxes;
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Align(
        alignment: Alignment(0, _c.value * 2 - 1),
        child: Container(
          height: 3,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, amber, Colors.transparent],
            ),
            boxShadow: [
              BoxShadow(color: amber, blurRadius: 18, spreadRadius: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Belgeyi buraya koyun" köşeleri: A4 oranında, ekrana ortalı. Okumayı sınırlamaz.
class _CornerGuide extends CustomPainter {
  _CornerGuide(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.86;
    final height = (width * 1.414).clamp(0.0, size.height * 0.72);
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: height / 1.414, height: height);
    final arm = r.width * 0.11;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(arm * dx, 0), paint);
      canvas.drawLine(corner, corner + Offset(0, arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerGuide old) => old.color != color;
}

/// Sabit tutma geri sayımı.
class _HoldRing extends StatelessWidget {
  const _HoldRing({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final seconds = ((1 - progress) * 2).ceil().clamp(1, 2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: CircularProgressIndicator(value: progress, strokeWidth: 6, color: amber, backgroundColor: Colors.white24),
              ),
              Center(
                child: Text('$seconds', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
          child: const Text('Kıpırdatmayın', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Görüntü donarken kısa beyaz parlama.
class _ShutterFlash extends StatelessWidget {
  const _ShutterFlash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 0),
        duration: const Duration(milliseconds: 350),
        builder: (_, v, __) => ColoredBox(color: Colors.white.withValues(alpha: v)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.template, this.status, this.error});
  final DocTemplate? template;
  final String? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final text = error ?? status ?? (t == null ? 'Belge aranıyor…' : t.name);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, a) => ScaleTransition(
        scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
        child: child,
      ),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: t == null ? Colors.black54 : amber,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              t == null ? Icons.search : Icons.verified,
              size: 18,
              color: t == null ? Colors.white : navy,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t == null ? Colors.white : navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldPanel extends StatelessWidget {
  const _FieldPanel({
    required this.template,
    required this.rows,
    this.onRetry,
    this.onContinue,
  });
  final DocTemplate template;
  final List<FieldRow> rows;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) =>
          Transform.translate(offset: Offset(0, 240 * v), child: child),
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        decoration: BoxDecoration(
          color: navy.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (template.handwritten)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'El yazılı belge: el yazısı alanlar bir sonraki ekranda girilecek.',
                  style: TextStyle(color: warning, fontSize: 13),
                ),
              ),
            Flexible(
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                childAspectRatio: 3.1,
                crossAxisSpacing: 8,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [for (final r in rows) _FieldCell(row: r)],
              ),
            ),
            if (onContinue != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('Tekrar çek')),
                  TextButton(onPressed: onContinue, child: const Text('Okunanlarla devam et')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldCell extends StatelessWidget {
  const _FieldCell({required this.row});
  final FieldRow row;

  @override
  Widget build(BuildContext context) {
    final found = row.value != null;
    return Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: found
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (_, s, c) => Transform.scale(scale: s, child: c),
                  child: const Icon(
                    Icons.check_circle,
                    color: success,
                    size: 22,
                  ),
                )
              : Icon(
                  Icons.radio_button_unchecked,
                  size: 20,
                  color: row.required ? amber : muted,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 11.5),
              ),
              if (found)
                Text(
                  row.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompleteBadge extends StatelessWidget {
  const _CompleteBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        builder: (_, s, c) => Transform.scale(scale: s, child: c),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: amber, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: navy, size: 72),
        ),
      ),
    );
  }
}
