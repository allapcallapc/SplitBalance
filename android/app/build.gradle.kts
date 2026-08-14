import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    jacoco
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.splitbalance.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.splitbalance.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing if key.properties isn't present (e.g. a
            // fresh checkout before signing is configured locally). CI always
            // provides key.properties, so release builds there are always
            // signed with the real release key.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    // Local unit tests run against a stub android.jar whose org.json classes throw
    // "not mocked" - this pulls in the real upstream implementation so tests that
    // exercise the queue file's JSON (de)serialization work without Robolectric.
    testImplementation("org.json:json:20251224")
    // Mockito's default inline mock maker (5.x+) can mock/spy final Android stub
    // classes (StatusBarNotification, etc.) without Robolectric - used to exercise
    // handleNotification()'s Context-dependent branches in isolation.
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.4.0")
}

jacoco {
    toolVersion = "0.8.12"
}

// Codecov only ever saw Flutter/Dart coverage (from `flutter test --coverage`) - this
// module's Kotlin unit tests ran in CI but produced no coverage data anyone uploaded,
// so PRs that only touched Kotlin showed "no coverage data" on Codecov even with new
// tests. This generates an XML report from testDebugUnitTest's JaCoCo execution data
// (auto-collected once the `jacoco` plugin is applied - see the Jacoco Gradle plugin
// docs) that CI uploads to Codecov alongside the Dart lcov.info.
tasks.register<JacocoReport>("jacocoTestReport") {
    dependsOn("testDebugUnitTest")
    group = "verification"
    description = "Generates an XML coverage report for testDebugUnitTest, for Codecov."

    reports {
        xml.required.set(true)
        html.required.set(false)
        csv.required.set(false)
    }

    val excludes = listOf(
        "**/R.class", "**/R\$*.class", "**/BuildConfig.*", "**/Manifest*.*"
    )
    classDirectories.setFrom(
        files(
            fileTree(layout.buildDirectory.dir("tmp/kotlin-classes/debug")) { exclude(excludes) },
            fileTree(layout.buildDirectory.dir("intermediates/javac/debug/classes")) { exclude(excludes) }
        )
    )
    sourceDirectories.setFrom(files("src/main/kotlin", "src/main/java"))
    executionData.setFrom(
        fileTree(layout.buildDirectory) { include("jacoco/testDebugUnitTest.exec") }
    )
}
