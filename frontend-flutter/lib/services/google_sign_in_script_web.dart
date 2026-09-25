import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Lets Google's GIS script (`accounts.google.com/gsi/client`) load. The
/// `google_sign_in_web` plugin inserts it when it registers, before `main`,
/// in every build; `web/index.html` holds it back until this call, which
/// the first use of Google sign-in makes. Idempotent.
void loadGoogleScript() {
  if (globalContext.has('zapzapLoadGoogleScript')) {
    globalContext.callMethod('zapzapLoadGoogleScript'.toJS);
  }
}
