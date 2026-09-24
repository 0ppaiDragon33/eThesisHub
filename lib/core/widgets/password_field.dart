import 'package:flutter/material.dart';

/// A password input with a show/hide toggle, shared by every screen that
/// takes a password so the behaviour cannot drift between them.
///
/// The icon reflects the CURRENT state, not the tap action: an open eye only
/// while the characters are actually visible, a slashed eye while they are
/// hidden. The tooltip names the action ("Show password" / "Hide password").
/// Each field owns its own visibility, so revealing one password on a screen
/// with two of them (register) does not reveal the other.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.fieldKey,
    required this.controller,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.helperText,
  });

  /// Applied to the inner [TextField] so existing finders — `Key('password')`,
  /// `Key('confirmPassword')` — keep resolving to a text field.
  final Key fieldKey;
  final TextEditingController controller;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        helperText: widget.helperText,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
