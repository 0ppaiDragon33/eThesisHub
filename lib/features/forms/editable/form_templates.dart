import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';

/// Every form that can be edited in the app, by id. Phase 1 has Form 1 only;
/// the other eight join as their builders are converted (spec §11, Phase 3).
final Map<String, FormTemplate> formTemplates = {
  form1Template.formId: form1Template,
};

/// The template for [formId], or null for a form that cannot be edited
/// (never shipped, or removed in an update).
FormTemplate? templateFor(String formId) => formTemplates[formId];
