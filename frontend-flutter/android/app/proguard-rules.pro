# ZapZap - R8 keep rules for the release build.
#
# android/app/build.gradle.kts sets, in the release build type, isMinifyEnabled,
# isShrinkResources and proguardFiles(proguard-android-optimize.txt, this file). The Flutter
# Gradle plugin adds its own rules for the engine; the ones below are belt and braces for
# what is reached by reflection or through the platform channels.
#
# A class R8 strips shows up at run time as ClassNotFoundException or NoSuchMethodError in
# logcat: add a -keep rule for it here. Check on a device with a release APK:
#   flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk

# --- Flutter engine and embedding, and every plugin's registrant -------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- google_sign_in (google_sign_in_android: Credential Manager + Play services) -----
# The plugin itself (io.flutter.plugins.googlesignin) is kept above.
# Credential Manager finds its Play services provider by reflection: without this rule a
# release build fails sign-in with "no provider dependencies found"
# (https://developer.android.com/identity/sign-in/credential-manager#proguard).
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keep class com.google.android.gms.auth.api.identity.** { *; }

# --- flutter_secure_storage (the session token) -------------------------------
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# --- General Android ----------------------------------------------------------
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
# Readable stack traces in crash reports.
-keepattributes SourceFile,LineNumberTable

# --- Warnings -----------------------------------------------------------------
# Flutter references Play Core (deferred components), which this app does not use.
-dontwarn com.google.android.play.core.**
# Compile-time annotations Tink (flutter_secure_storage) references.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
