import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form3_pdf.dart';
import 'package:ethesishub/features/forms/form4a_pdf.dart';
import 'package:ethesishub/features/forms/form4b_pdf.dart';
import 'package:ethesishub/features/forms/form5a_pdf.dart';
import 'package:ethesishub/features/forms/form5b_pdf.dart';
import 'package:ethesishub/features/forms/form5c_pdf.dart';
import 'package:ethesishub/features/forms/form7_pdf.dart';
import 'package:ethesishub/features/forms/form8_pdf.dart';

/// Every form that can be edited in the app, by id.
final Map<String, FormTemplate> formTemplates = {
  form1Template.formId: form1Template,
  form3Template.formId: form3Template,
  form4aTemplate.formId: form4aTemplate,
  form4bTemplate.formId: form4bTemplate,
  form5aTemplate.formId: form5aTemplate,
  form5bTemplate.formId: form5bTemplate,
  form5cTemplate.formId: form5cTemplate,
  form7Template.formId: form7Template,
  form8Template.formId: form8Template,
};

/// The template for [formId], or null for a form that cannot be edited
/// (never shipped, or removed in an update).
FormTemplate? templateFor(String formId) => formTemplates[formId];
