import 'package:en_check/widgets/qr_scanner_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reprend les éléments de la maquette et expose le repli PIN',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var pinTapped = false;
    var closeTapped = false;
    await tester.pumpWidget(MaterialApp(
      home: QrScannerChrome(
        cameraPreview: const ColoredBox(color: Color(0xFF292824)),
        onClose: () => closeTapped = true,
        onPinFallback: () => pinTapped = true,
        instruction: 'Placez le QR code du badge dans le cadre',
        statusLabel: 'Recherche du QR code…',
        cameraLabel: 'Caméra arrière',
        torchAvailable: true,
        torchEnabled: false,
        showSwitchButton: true,
        onToggleTorch: () {},
        onSwitchCamera: () {},
      ),
    ));

    expect(find.text('Scanner le badge'), findsOneWidget);
    expect(find.text('Recherche du QR code…'), findsOneWidget);
    expect(find.text('Placez le QR code du badge dans le cadre'), findsOneWidget);
    expect(find.text('Caméra arrière'), findsOneWidget);
    expect(find.text('Utiliser le code PIN'), findsOneWidget);

    await tester.tap(find.text('Utiliser le code PIN'));
    await tester.pump();
    expect(pinTapped, isTrue);

    await tester.tap(find.byTooltip('Fermer le lecteur QR'));
    await tester.pump();
    expect(closeTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('état caméra indisponible propose une reprise sans viseur',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var retryTapped = false;
    await tester.pumpWidget(MaterialApp(
      home: QrScannerChrome(
        cameraPreview: const ColoredBox(color: Color(0xFF292824)),
        onClose: () {},
        instruction: 'Placez le QR code du badge dans le cadre',
        statusLabel: 'Recherche du QR code…',
        cameraLabel: 'Caméra arrière',
        cameraErrorTitle: 'Autorisez l’accès à la caméra',
        cameraErrorMessage: 'Autorisez l’accès dans les réglages.',
        onRetryCamera: () => retryTapped = true,
      ),
    ));

    expect(find.text('Autorisez l’accès à la caméra'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(retryTapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
