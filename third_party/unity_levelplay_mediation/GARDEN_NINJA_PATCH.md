# Local compatibility patch

Source: official unity_levelplay_mediation 9.2.0 pub.dev archive.
Archive SHA-256: 686432b705c701ded78a11bee54b63bacb18277d618afb54231925f91a1f8e27

Android Gradle configuration and the minimum Flutter/Dart constraints are changed.
Deprecated Color.value reads use the equivalent Color.toARGB32() conversion.
One documentation comment uses Dart doc syntax; public SDK names are preserved.
The Kotlin plugin classpath/application is removed and kotlinOptions is replaced
with kotlin.compilerOptions, following Flutter's built-in Kotlin migration guide.
The verified Android/iOS SDK versions stay unchanged.

The iOS sources and headers use Flutter's shared CocoaPods/SwiftPM layout.
Package.swift pins Unity's official native LevelPlay Swift package to 9.4.0,
matching the existing CocoaPods SDK. Native-ad templates use the resource bundle
provided by each package manager. The production app keeps its CocoaPods adapter
integration; a separate macOS CI fixture compiles and launches the SwiftPM bridge.

The official 9.5.0 release still applies KGP as of 2026-11-14. Remove this path
dependency when an upstream release includes the migration.

https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
