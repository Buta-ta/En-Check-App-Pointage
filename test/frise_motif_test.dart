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

  test('Le vrai symbole En-Check est bien embarqué', () async {
    final asset = await rootBundle.load('assets/logo_encheck.png');
    expect(asset.lengthInBytes, greaterThan(1000));
  });

  testWidgets('La frise d’accueil utilise le vrai motif, mat et élargi',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 372,
          child: FriseMotif(
            motif: MotifCulturel.adinkra,
            hauteur: 14,
            agrandissementHorizontal: 1.22,
            opacite: 0.90,
          ),
        ),
      ),
    );
    await tester.pump();

    final frise = tester.widget<FriseMotif>(find.byType(FriseMotif));
    expect(frise.hauteur, 14);
    final image = tester.widget<Image>(find.byType(Image));
    expect(_sourceAsset(image).assetName, MotifCulturel.adinkra.asset);
    expect(image.fit, BoxFit.fill);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.90);
    final transform = tester.widget<Transform>(find.byType(Transform));
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.22, 0.0001));
  });

  testWidgets('Le motif secondaire reste issu de la famille choisie',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MotifSecondaire(motif: MotifCulturel.bogolan),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(_sourceAsset(image).assetName, MotifCulturel.bogolan.asset);
    expect(image.fit, BoxFit.cover);
    expect(find.byType(Icon), findsNothing);
  });
}
