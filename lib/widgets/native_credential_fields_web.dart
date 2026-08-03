// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

var _viewCounter = 0;
var _styleInjected = false;

const _sharedCss = '''
.ncf-field { position: relative; margin: 0; }
.ncf-field input {
  width: 100%;
  box-sizing: border-box;
  height: 56px;
  padding: 20px 12px 4px 12px;
  font-size: 16px;
  font-family: Roboto, "Segoe UI", Arial, sans-serif;
  border: 1px solid var(--ncf-border, #767676);
  border-radius: var(--ncf-radius, 4px);
  background: var(--ncf-fill, transparent);
  color: var(--ncf-text, #000);
  outline: none;
}
.ncf-field input:focus {
  border: 2px solid var(--ncf-focus, #1976d2);
  padding: 19px 11px 3px 11px;
}
.ncf-field label {
  position: absolute;
  left: 13px;
  top: 18px;
  font-size: 16px;
  color: var(--ncf-label, #666);
  transition: all 0.15s ease;
  pointer-events: none;
  background: var(--ncf-fill, transparent);
  padding: 0 4px;
}
.ncf-field input:focus + label,
.ncf-field input:not(:placeholder-shown) + label {
  top: -9px;
  left: 9px;
  font-size: 12px;
  color: var(--ncf-focus, #1976d2);
}
''';

void _ensureStyleInjected() {
  if (_styleInjected) return;
  _styleInjected = true;
  html.document.head!.append(html.StyleElement()..text = _sharedCss);
}

String _cssColor(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'rgba($r,$g,$b,${c.a})';
}

/// Email + password fields for the sign-in/sign-up form, on web.
///
/// Flutter web draws [TextField]s on a <canvas> and only gives the *currently
/// focused* field's backing DOM <input> real screen dimensions - every other
/// field in the same AutofillGroup collapses to a 0x0 placeholder the moment
/// it loses focus (this is a long-standing, unresolved Flutter engine
/// limitation: flutter/flutter#127694, #61301, #174773). Extensions like
/// Bitwarden scan the page for a fillable username+password *pair* and
/// refuse to autofill at all when one of the two is a zero-size element,
/// which is exactly what was reported ("Impossible de remplir
/// automatiquement le site sélectionné sur cette page").
///
/// The fix here is to stop asking Flutter to draw these two fields at all.
/// Instead this embeds genuine, always-real-size HTML <input> elements
/// (via a platform view) inside a real <form>, identical to what a plain
/// website would render - so the browser and any extension sees an
/// ordinary, fully detectable login form. Colors are pulled from the
/// current [Theme] and kept in sync via CSS custom properties so the
/// fields still follow the app's light/dark/pink theme switch.
class NativeCredentialFields extends StatefulWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isSignUp;
  final VoidCallback? onSubmit;

  const NativeCredentialFields({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.isSignUp,
    this.onSubmit,
  });

  @override
  State<NativeCredentialFields> createState() =>
      _NativeCredentialFieldsState();
}

class _NativeCredentialFieldsState extends State<NativeCredentialFields> {
  late final String _viewType = 'native-credential-fields-${_viewCounter++}';
  html.InputElement? _passwordInput;
  html.DivElement? _emailField;
  html.DivElement? _passwordField;

  @override
  void initState() {
    super.initState();
    _ensureStyleInjected();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final form = html.FormElement()
        ..setAttribute('autocomplete', 'on')
        ..style.width = '100%'
        ..style.margin = '0'
        ..style.display = 'flex'
        ..style.flexDirection = 'column'
        ..style.gap = '12px';
      form.onSubmit.listen((e) => e.preventDefault());

      final emailField = _buildField(
        type: 'email',
        name: 'username',
        autocomplete: 'username',
        label: 'Email',
        initialValue: widget.emailController.text,
        onInput: (value) => widget.emailController.text = value,
      );
      final emailInput = emailField.querySelector('input') as html.InputElement;
      emailInput.autofocus = true;
      _emailField = emailField;

      final passwordField = _buildField(
        type: 'password',
        name: 'password',
        autocomplete: widget.isSignUp ? 'new-password' : 'current-password',
        label: 'Password',
        initialValue: widget.passwordController.text,
        onInput: (value) => widget.passwordController.text = value,
      );
      final passwordInput =
          passwordField.querySelector('input') as html.InputElement;
      passwordInput.onKeyDown.listen((e) {
        if (e.key == 'Enter') {
          e.preventDefault();
          widget.onSubmit?.call();
        }
      });
      _passwordInput = passwordInput;
      _passwordField = passwordField;

      form.append(emailField);
      form.append(passwordField);
      _applyTheme();
      return form;
    });
  }

  html.DivElement _buildField({
    required String type,
    required String name,
    required String autocomplete,
    required String label,
    required String initialValue,
    required void Function(String value) onInput,
  }) {
    final input = html.InputElement(type: type)
      ..name = name
      ..id = name
      ..setAttribute('autocomplete', autocomplete)
      ..placeholder = ' '
      ..value = initialValue;
    input.onInput.listen((_) => onInput(input.value ?? ''));

    final field = html.DivElement()..className = 'ncf-field';
    field.append(input);
    field.append(html.LabelElement()..text = label);
    return field;
  }

  void _applyTheme() {
    if (!mounted) return;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final decTheme = theme.inputDecorationTheme;

    final cardColor = theme.cardTheme.color ?? scheme.surface;
    final fill = decTheme.filled == true
        ? (decTheme.fillColor ?? scheme.surfaceContainerHighest)
        : cardColor;

    final enabledBorder = decTheme.enabledBorder ?? decTheme.border;
    final focusedBorder = decTheme.focusedBorder ?? decTheme.border;
    final borderColor = enabledBorder is OutlineInputBorder
        ? enabledBorder.borderSide.color
        : scheme.outline;
    final focusColor = focusedBorder is OutlineInputBorder
        ? focusedBorder.borderSide.color
        : scheme.primary;
    final radius = enabledBorder is OutlineInputBorder
        ? enabledBorder.borderRadius.resolve(TextDirection.ltr).topLeft.x
        : 4.0;

    for (final field in [_emailField, _passwordField]) {
      if (field == null) continue;
      field.style
        ..setProperty('--ncf-border', _cssColor(borderColor))
        ..setProperty('--ncf-focus', _cssColor(focusColor))
        ..setProperty('--ncf-fill', _cssColor(fill))
        ..setProperty('--ncf-text', _cssColor(scheme.onSurface))
        ..setProperty('--ncf-label', _cssColor(scheme.onSurfaceVariant))
        ..setProperty('--ncf-radius', '${radius}px');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyTheme();
  }

  @override
  void didUpdateWidget(covariant NativeCredentialFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSignUp != widget.isSignUp) {
      _passwordInput?.setAttribute(
        'autocomplete',
        widget.isSignUp ? 'new-password' : 'current-password',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
