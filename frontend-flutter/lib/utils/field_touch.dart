import 'package:flutter/widgets.dart';

/// When a form field may show its refusal: once the user edited it and then
/// left it, or tried to submit ([submitted]). Never before — an error on a
/// form nobody has touched yet reads as a mistake. From then on the screen
/// checks it live, so the message goes as soon as the value is fixed.
///
/// Give [focus] to the field and call [edited] from its `onChanged`.
class FieldTouch {
  FieldTouch(VoidCallback onTouched) {
    focus.addListener(() {
      if (!focus.hasFocus && _edited && !touched) {
        touched = true;
        onTouched();
      }
    });
  }

  final focus = FocusNode();
  bool _edited = false;

  /// The field's refusal, if any, may be shown.
  bool touched = false;

  void edited() => _edited = true;

  /// A submit was tried: show the refusal whatever the field went through.
  void submitted() => touched = true;

  void dispose() => focus.dispose();
}
