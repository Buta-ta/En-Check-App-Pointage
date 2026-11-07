import 'package:en_check/services/motif_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaque motif expose son peuple, son pays et son inspiration', () {
    expect(MotifCulturel.tous, hasLength(4));
    for (final motif in MotifCulturel.tous) {
      expect(motif.nom, isNotEmpty);
      expect(motif.peuple, isNotEmpty);
      expect(motif.pays, isNotEmpty);
      expect(motif.inspiration, isNotEmpty);
      expect(motif.nom, isNot(contains('Motif textile')));
    }

    expect(MotifCulturel.raphia.pays, 'République démocratique du Congo');
    expect(MotifCulturel.raphia.peuple, 'Kuba');
    expect(MotifCulturel.adinkra.pays, 'Ghana');
    expect(MotifCulturel.adinkra.peuple, contains('Akan'));
    expect(MotifCulturel.bogolan.pays, 'Mali');
    expect(MotifCulturel.bogolan.peuple, contains('Bamana'));
    expect(MotifCulturel.zoulou.pays, 'Afrique du Sud');
    expect(MotifCulturel.zoulou.peuple, 'Zoulou');
  });
}
