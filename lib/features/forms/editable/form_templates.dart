import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form3_pdf.dart';

/// Every form that can be edited in the app, by id.
final Map<String, FormTemplate> formTemplates = {
  form1Template.formId: form1Template,
  form3Template.formId: form3Template,
};

/// The template for [formId], or null for a form that cannot be edited
/// (never shipped, or removed in an update).
FormTemplate? templateFor(String formId) => formTemplates[formId];
