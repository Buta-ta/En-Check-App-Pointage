// lib/widgets/web_camera_widget_provider.dart
// Point d'entrée unique pour WebCameraWidget, avec conditional export :
// le vrai widget web (dart:html / package:web) dans le navigateur,
// le stub inoffensif partout ailleurs — sans cela, `flutter build apk`
// tente de compiler le code web et casse.

export 'web_camera_widget_stub.dart'
if (dart.library.js_interop) 'web_camera_widget.dart'
if (dart.library.html) 'web_camera_widget.dart';
