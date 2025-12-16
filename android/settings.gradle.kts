pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    
    // UPDATED: Fixes the "requires Android Gradle plugin 8.9.1" error
    id("com.android.application") version "8.9.1" apply false
    
    // UPDATED: Fixes the "Kotlin version will soon be dropped" warning
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")