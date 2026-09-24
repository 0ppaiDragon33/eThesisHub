import 'package:pdf/widgets.dart' as pw;

/// Whether a block is ordinary wording or a line left for someone to fill.
enum BlockKind {
  /// Printed as its text. Emptied, it prints nothing.
  text,

  /// Printed as a ruled line while empty, and as its text once filled.
  blank,
}

/// One editable piece of a form's text.
class FormBlock {
  const FormBlock({
    required this.id,
    required this.label,
    this.defaultText = '',
    this.kind = BlockKind.text,
    this.multiline = false,
  });

  /// Stable once shipped: saved copies refer to blocks by this id.
  final String id;

  /// What the editor shows above the field.
  final String label;

  /// The form's own wording; empty for a blank.
  final String defaultText;
  final BlockKind kind;

  /// A paragraph rather than a single line.
  final bool multiline;
}

/// A form's editable text, in page order, and the layout that prints it.
class FormTemplate {
  const FormTemplate({
    required this.formId,
    required this.title,
    required this.blocks,
    required this.layout,
  });

  /// Also the `formId` stored on a saved copy, e.g. 'form1'.
  final String formId;

  /// The form's name as the app shows it.
  final String title;
  final List<FormBlock> blocks;

  /// The page content. Every string must come through [FormText]. Returned as
  /// a flat list so a long form can continue onto a second sheet.
  final List<pw.Widget> Function(FormText text) layout;

  FormBlock? block(String id) {
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// What a copy stores for [values]: only known blocks whose text differs
  /// from the default, so an untouched block keeps following the template.
  Map<String, String> overridesFrom(Map<String, String> values) => {
        for (final b in blocks)
          if (values.containsKey(b.id) && values[b.id] != b.defaultText)
            b.id: values[b.id]!,
      };
}

/// A template's text with one copy's overrides applied.
class FormText {
  FormText(this.template, [Map<String, String> overrides = const {}])
      : _overrides = overrides;

  final FormTemplate template;
  final Map<String, String> _overrides;

  /// Every block id the layout asked for, so a test can prove each block
  /// actually reaches the page.
  final Set<String> read = {};

  /// The block's text: the copy's override if it has one, else the default.
  /// An override for a block the template no longer has is simply never
  /// looked up. Asking for a block the template does not have is a bug in
  /// the layout and throws.
  String of(String id) {
    final block = template.block(id);
    if (block == null) {
      throw ArgumentError.value(
          id, 'id', 'no such block in ${template.formId}');
    }
    read.add(id);
    return _overrides[id] ?? block.defaultText;
  }

  /// True for a blank block with nothing typed in it (spaces count as
  /// nothing), which prints as a ruled line.
  bool isBlank(String id) =>
      template.block(id)?.kind == BlockKind.blank && of(id).trim().isEmpty;
}
