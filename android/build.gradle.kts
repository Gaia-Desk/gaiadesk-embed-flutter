// gaiadesk_embed (Android): a thin plugin over net.gaiadesk:embed-android,
// which carries the Kotlin SDK and the prebuilt libgaiadesk_embed.so.
group = "net.gaiadesk.embed.flutter"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "net.gaiadesk.embed.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // The SDK's floor (PixelCopy of a window, MediaCodec request-sync).
        minSdk = 26
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// net.gaiadesk:embed-android: the published AAR from Maven Central by default.
// Overrides (the app's android/gradle.properties, -P, or env vars):
//   GaiaDeskEmbed_embedAndroidVersion=<v>        another published version
//   GaiaDeskEmbed_embedAndroidMavenLocal=true    (GAIADESK_EMBED_ANDROID_MAVEN_LOCAL=1)
//       resolve it from ~/.m2 too, after `./gradlew :embed:publishToMavenLocal`
//       in gaiadesk-embed-android (adds mavenLocal() to every project of the build)
//   GaiaDeskEmbed_embedAndroidAar=/path/to.aar   (GAIADESK_EMBED_ANDROID_AAR)
//       a local AAR file instead (app builds: `flutter build apk`/`flutter run`)
val embedAndroidVersion = (findProperty("GaiaDeskEmbed_embedAndroidVersion") as String?) ?: "0.1.0"
val embedAndroidAar = (findProperty("GaiaDeskEmbed_embedAndroidAar") as String?)
    ?: System.getenv("GAIADESK_EMBED_ANDROID_AAR")
val embedAndroidMavenLocal = ((findProperty("GaiaDeskEmbed_embedAndroidMavenLocal") as String?)
    ?: System.getenv("GAIADESK_EMBED_ANDROID_MAVEN_LOCAL") ?: "") in setOf("1", "true")

if (embedAndroidMavenLocal) {
    rootProject.allprojects { repositories { mavenLocal() } }
}

dependencies {
    if (!embedAndroidAar.isNullOrEmpty()) {
        implementation(files(embedAndroidAar))
    } else {
        implementation("net.gaiadesk:embed-android:$embedAndroidVersion")
    }
}
