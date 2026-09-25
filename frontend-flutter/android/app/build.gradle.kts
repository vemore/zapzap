import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zapzap.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.zapzap.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The upload key: android/key.properties (never committed, see key.properties.template)
    // points at the keystore scripts/generate_keystore.sh wrote to $HOME. Without it -- CI, a
    // worktree -- a release APK falls back to the debug key, so it still builds; a release
    // bundle is refused (below the android block): a Play bundle is never debug-signed.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    }
    // Names the missing key, never a value: two of them are passwords.
    fun keystoreProperty(key: String): String =
        keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() }
            ?: error("android/key.properties: missing $key (see key.properties.template)")

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = file(keystoreProperty("storeFile"))
                storePassword = keystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }

            // R8: shrink code and resources; keep rules in proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Without key.properties: refuse a release bundle before any task runs, and say so when a
// release APK falls back to the debug key.
if (!rootProject.file("key.properties").exists()) {
    gradle.taskGraph.whenReady {
        val names = allTasks.map { it.name }
        if ("bundleRelease" in names) {
            throw GradleException(
                "No android/key.properties: a release bundle (flutter build appbundle) must be " +
                    "signed with the upload key, never the debug key. Copy " +
                    "android/key.properties.template to android/key.properties and fill it in " +
                    "(.llmwiki/FrontendFlutter.md, Android).",
            )
        }
        if (names.any { it.endsWith("Release") }) {
            // error, not warn: `flutter build` hides Gradle's stdout (warn) unless -v, and
            // shows its stderr. The build goes on.
            logger.error(
                "WARNING: no android/key.properties -- this release build is signed with the " +
                    "DEBUG key. Fine for a test APK; Play refuses it.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
