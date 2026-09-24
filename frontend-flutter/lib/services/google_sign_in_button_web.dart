import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// The Google Identity Services button: on the web the ID token only comes
/// out of Google's own button (`authenticate()` is not supported there). Its
/// look matches the React client's (`GoogleLoginButton.jsx`: filled black,
/// rectangular, "Continue with"), in the app's language.
Widget googleButton(BuildContext context) => SizedBox(
  height: 44,
  child: gsi.renderButton(
    configuration: gsi.GSIButtonConfiguration(
      theme: gsi.GSIButtonTheme.filledBlack,
      size: gsi.GSIButtonSize.large,
      text: gsi.GSIButtonText.continueWith,
      shape: gsi.GSIButtonShape.rectangular,
      locale: Localizations.localeOf(context).languageCode,
    ),
  ),
);
