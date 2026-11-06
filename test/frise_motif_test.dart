import 'package:en_check/services/motif_service.dart';
import 'package:en_check/widgets/frise_motif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AssetImage _sourceAsset(Image image) {
  final provider = image.image;
  if (provider is ResizeImage) return provider.imageProvider as AssetImage;
  return provider as AssetImage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Le vrai symbole et les quatre frises optimisées sont embarqués',
      () async {
    final logo = await rootBundle.load('assets/logo_encheck.png');
    expect(logo.lengthInBytes, greaterThan(1000));
    for (final motif in MotifCulturel.tous) {
      final asset = await rootBundle.load(motif.friseAsset);
      expect(asset.lengthInBytes, greaterThan(1000), reason: motif.id);
      expect(asset.lengthInBytes, lessThan(30000), reason: motif.id);
    }
  });

  testWidgets('La frise tuilée conserve les symboles sans défilement',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 372,
          child: FriseMotif(
            motif: MotifCulturel.adinkra,
            hauteur: 20,
            tuilee: true,
            opacite: 0.92,
          ),
        ),
      ),
    );
    await tester.pump();

    final frise = tester.widget<FriseMotif>(find.byType(FriseMotif));
    expect(frise.hauteur, 20);
    expect(frise.tuilee, isTrue);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, greaterThanOrEqualTo(5));
    for (final image in images) {
      expect(_sourceAsset(image).assetName, MotifCulturel.adinkra.friseAsset);
      expect(image.fit, BoxFit.fill);
    }
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.92);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Transform), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Le pictogramme UI est un crop visible de la famille choisie',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MotifUiIcon(
          motif: MotifCulturel.bogolan,
          fond: Colors.white,
          bordure: Colors.black12,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(_sourceAsset(image).assetName, MotifCulturel.bogolan.friseAsset);
    expect(image.fit, BoxFit.cover);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.68);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
