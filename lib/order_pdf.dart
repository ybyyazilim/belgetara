
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

const _navy = PdfColor.fromInt(0xFF14203A);
const _amber = PdfColor.fromInt(0xFFFDB813);
const _line = PdfColor.fromInt(0xFFD5DAE5);
const _soft = PdfColor.fromInt(0xFFF3F5F9);
const _grey = PdfColor.fromInt(0xFF5E6A82);

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<Uint8List> buildOrderPdf(WorkOrder o) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final logo = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());

  final doc = pw.Document(title: o.number, theme: pw.ThemeData.withFont(base: regular, bold: bold));

  pw.Widget info(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 72, child: pw.Text(label, style: const pw.TextStyle(color: _grey, fontSize: 9.5))),
          pw.Expanded(child: pw.Text(value.isEmpty ? '-' : value, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
        ]),
      );

  pw.Widget totalBox(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(color: _grey, fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: _navy,
          padding: const pw.EdgeInsets.fromLTRB(32, 18, 32, 18),
          child: pw.Row(children: [
            pw.Image(logo, height: 54),
            pw.Spacer(),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('BELGETARA', style: pw.TextStyle(color: PdfColors.white, fontSize: 17, fontWeight: pw.FontWeight.bold)),
              pw.Text('TEKSTİL İŞ EMRİ', style: pw.TextStyle(color: _amber, fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
          ]),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(32, 20, 32, 28),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(o.number, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text(_date(o.createdAt), style: const pw.TextStyle(color: _grey, fontSize: 10)),
              ]),
              pw.SizedBox(height: 14),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  child: pw.Column(children: [
                    info('Firma', o.customer),
                    info('Stok', o.stock),
                    info('Renk', o.color),
                    info('İşlem', o.note),
                  ]),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(children: [
                    info('Kaynak belge', o.docName),
                    info('Belge no', o.docRef),
                    info('Belge tarihi', o.docDate),
                    info('Yapılacak', o.processes.join(', ')),
                  ]),
                ),
              ]),
              pw.SizedBox(height: 12),
              pw.Row(children: [
                totalBox('Toplam Giriş Metre', formatNumber(o.totalMeters)),
                totalBox('Toplam Giriş Kilo', formatNumber(o.totalKilos)),
                totalBox('Toplam Top', formatNumber(o.totalRolls, decimals: 0)),
              ]),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['Parti No', 'Parti İşlemi', 'En (cm)', 'Top', 'Giriş Metre', 'Giriş Kilo'],
                data: [
                  for (final l in o.lines)
                    [l.party, l.process, l.width, l.rolls, l.meters, l.kilos]
                ],
                headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: _navy),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .6), bottom: pw.BorderSide(color: _line, width: .6)),
                cellAlignments: {
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 18),
              pw.Text('Süreç', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 7),
              pw.Row(children: [
                for (var i = 0; i < o.stages.length; i++)
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(right: 6),
                      padding: const pw.EdgeInsets.symmetric(vertical: 8),
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: i <= o.stage ? _amber : _soft,
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: pw.Text(o.stages[i], style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: i <= o.stage ? _navy : _grey)),
                    ),
                  ),
              ]),
              pw.Spacer(),
              pw.Row(children: [
                for (final s in ['Teslim Alan', 'Kesim Sorumlusu', 'Sevk Eden'])
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(right: 10),
                      height: 62,
                      padding: const pw.EdgeInsets.all(7),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(5)),
                      child: pw.Text(s, style: const pw.TextStyle(color: _grey, fontSize: 9)),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ],
    ),
  ));
  return doc.save();
}
