import 'package:flutter/material.dart';

/// Email + password fields for the sign-in/sign-up form.
///
/// This is the non-web implementation: plain Flutter [TextField]s inside an
/// [AutofillGroup], which is what lets the platform's native autofill
/// service (and password managers integrated with it, e.g. Bitwarden's
/// Android app) recognize and fill the fields. See
/// native_credential_fields_web.dart for why web needs a different approach.
class NativeCredentialFields extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        children: [
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [
              AutofillHints.email,
              AutofillHints.username,
            ],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: [
              isSignUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
