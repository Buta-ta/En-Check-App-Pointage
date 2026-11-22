import 'package:en_check/services/annonces_accueil_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('décode les annonces dans l’ordre serveur et borne la durée', () async {
    final service = AnnoncesAccueilService(
      rpc: (enterpriseId) async {
        expect(enterpriseId, 'enterprise-a');
        return {
          'ok': true,
          'entreprise_id': 'enterprise-a',
          'publicites': [
            {
              'id': 'image-1',
              'type': 'image',
              'url': 'https://cdn.example.test/1.png',
              'duree_affichage_ms': 5000,
              'ordre_publication': 3,
              'updated_at': '2026-11-08 10:07:30.424975+00',
            },
            {
              'id': 'clip-2',
              'type': 'video',
              'url': 'https://cdn.example.test/2.mp4',
              'duree_affichage_ms': 500,
              'ordre_publication': 1,
              'updated_at': '2026-11-08T10:08:30Z',
            },
          ],
        };
      },
    );

    final annonces = await service.charger('enterprise-a');
    expect(annonces, hasLength(2));
    expect(annonces![0].id, 'image-1');
    expect(annonces[0].ordrePublication, 3);
    expect(
      annonces[0].updatedAt,
      DateTime.utc(2026, 11, 8, 10, 7, 30, 424, 975),
    );
    expect(annonces[0].urlVersionnee, contains('?v='));
    expect(annonces[1].type, 'video');
    expect(annonces[1].dureeAffichageMs, 3000);
  });

  test('une réponse valide vide efface la campagne, une RPC en échec est distincte',
      () async {
    final emptyService = AnnoncesAccueilService(
      rpc: (_) async => {
        'ok': true,
        'entreprise_id': 'enterprise-a',
        'publicites': <Object>[],
      },
    );
    expect(await emptyService.charger('enterprise-a'), isEmpty);

    final failedService = AnnoncesAccueilService(
      rpc: (_) async => throw Exception('offline'),
    );
    expect(await failedService.charger('enterprise-a'), isNull);
  });

  test('ignore les formats non autorisés et les URL non HTTPS', () {
    expect(
      AnnonceAccueil.fromJson({
        'id': 'bad',
        'type': 'html',
        'url': 'https://cdn.example.test/ad.html',
        'duree_affichage_ms': 5000,
      }),
      isNull,
    );
    expect(
      AnnonceAccueil.fromJson({
        'id': 'unsafe',
        'type': 'image',
        'url': 'javascript:alert(1)',
        'duree_affichage_ms': 5000,
      }),
      isNull,
    );
    expect(
      AnnonceAccueil.fromJson({
        'id': 'ok',
        'type': 'gif',
        'url': 'https://cdn.example.test/ad.gif',
        'duree_affichage_ms': 16000,
      })!.dureeAffichageMs,
      15000,
    );
  });

  test('le cache de métadonnées est séparé par entreprise', () async {
    final service = AnnoncesAccueilService(rpc: (_) async => null);
    const annonce = AnnonceAccueil(
      id: 'campaign-a',
      type: 'image',
      url: 'https://cdn.example.test/a.jpg',
      dureeAffichageMs: 5000,
      ordrePublication: 1,
      updatedAt: null,
    );

    await service.enregistrerCache('enterprise-a', [annonce]);
    await service.enregistrerCache('enterprise-b', []);

    expect((await service.chargerCache('enterprise-a'))!.single.id, 'campaign-a');
    expect(await service.chargerCache('enterprise-b'), isEmpty);
    expect(await service.chargerCache('enterprise-c'), isNull);
  });
}
