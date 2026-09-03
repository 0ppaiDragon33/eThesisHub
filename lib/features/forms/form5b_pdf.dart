import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form5b_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// The whole printed page, shared by a real profile and the blank
/// template — the identical header block Form 5c already renders,
/// standing on its own. `formField` rules a blank for a null or empty
/// value on both, so a template is provably the same layout as a filled
/// profile with nothing filled in.
pw.Widget _page({Form5bData? data}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(
        rdCode: 'RD-37-06/24-04',
        formTitle: 'Res. Form 5b. Presenter and Evaluator Profile',
      ),
      pw.SizedBox(height: 16),
      formField(
        'Name of Presenter',
        data == null || data.presenterNames.isEmpty
            ? null
            : data.presenterNames.join(', '),
      ),
      formField('Degree and Field of Specialization', null),
      formField(
        'Date of Presentation',
        data?.presentedOn == null
            ? null
            : '${data!.presentedOn!.day} '
                  '${monthName(data.presentedOn!.month)} '
                  '${data.presentedOn!.year}',
      ),
      formField(
        'Time of Presentation',
        data?.presentedOn == null
            ? null
            : '${data!.presentedOn!.hour.toString().padLeft(2, '0')}:'
                  '${data.presentedOn!.minute.toString().padLeft(2, '0')}',
      ),
      formField('Venue', data?.venue),
      formField('Title of the Study', data?.title),
      pw.SizedBox(height: 12),
      formField('Evaluator', data?.evaluatorName),
      formField('Academic Rank', null),
      formField('Field of Specialization', data?.evaluatorField),
    ],
  );
}

/// Generates Form 5b — Presenter and Evaluator Profile — as a PDF.
/// `compress: false` keeps the content streams text-greppable.
Future<Uint8List> buildForm5bPdf(Form5bData data) async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5b: the same chrome and fields as [buildForm5bPdf], every
/// one of them a ruled line.
Future<Uint8List> buildForm5bBlank() async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(),
    ),
  );
  return doc.save();
}
