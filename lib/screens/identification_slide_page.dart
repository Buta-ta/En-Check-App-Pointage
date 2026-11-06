// lib/screens/identification_slide_page.dart
// ═══════════════════════════════════════════════════════════
// 🪪 PAGE D'IDENTIFICATION — une action = une page
// ═══════════════════════════════════════════════════════════
//
//  Identifiant (numéro seul, le préfixe est affiché) + code, puis
//  « Glisser pour valider ». Utilisée par la PAUSE et par le POINTAGE
//  (arrivée / départ) — même écran, titre et scène adaptés.
//
//  Résultat : la page RENVOIE l'employé identifié (Navigator.pop) —
//  l'appelant enregistre le pointage ou la pause, puis l'écran principal
//  affiche le succès (« retour automatique vers la page principale »).
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, FilteringTextInputFormatter;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/accueil_palette.dart';
import '../services/connectivity_service.dart';
import '../services/local_database.dart';
import '../services/motif_service.dart';
import '../services/supabase_service.dart';
import '../services/theme_service.dart';
import '../widgets/frise_motif.dart';
import '../widgets/logo_empreinte.dart';
import '../widgets/slide_valider.dart';
import '../widgets/sans_etirement.dart';

class IdentificationSlidePage extends StatefulWidget {
  final String titre;
  final String sceneAsset;
  final String aide;
  final String entrepriseId;
  final String? matriculeInitial;

  /// Préfixe du matricule (ex. ENN) : affiché devant le champ, l'employé
  /// ne tape que son numéro.
  final String matriculePrefix;

  /// Ligne d'état facultative (ex. pause en cours).
  final Widget? statut;

  /// Maquette validée pour Pause. Le pointage partage la logique mais garde
  /// son apparence actuelle tant que sa propre maquette n'est pas validée.
  final bool maquettePause;

  const IdentificationSlidePage({
    super.key,
    required this.titre,
    required this.sceneAsset,
    required this.aide,
    required this.entrepriseId,
    this.matriculePrefix = '',
    this.matriculeInitial,
    this.statut,
    this.maquettePause = false,
  });

  @override
  State<IdentificationSlidePage> createState() =>
      _IdentificationSlidePageState();
}

class _IdentificationSlidePageState extends State<IdentificationSlidePage> {
  late final TextEditingController _identifiantCtrl;
  final _motDePasseCtrl = TextEditingController();
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _identifiantCtrl =
        TextEditingController(text: widget.matriculeInitial ?? '');
  }

  @override
  void dispose() {
    _identifiantCtrl.dispose();
    _motDePasseCtrl.dispose();
    super.dispose();
  }

  /// Vérifie les identifiants : renvoie l'employé, ou null (erreur affichée).
  Future<Map<String, dynamic>?> _verifierEmploye() async {
    FocusScope.of(context).unfocus();
    final numero = _identifiantCtrl.text.trim().toUpperCase();
    final motDePasse = _motDePasseCtrl.text.trim();

    // Le champ contient le numéro seul : le préfixe est ajouté ici.
    String identifiant = numero;
    if (identifiant.isNotEmpty && !identifiant.contains('-')) {
      identifiant = widget.matriculePrefix.isEmpty
          ? identifiant
          : '${widget.matriculePrefix}-$identifiant';
    }

    if (numero.isEmpty || motDePasse.length < 4) {
      setState(() => _erreur = "Renseignez l'identifiant et le code.");
      return null;
    }
    setState(() => _erreur = null);

    try {
      Map<String, dynamic>? employe;
      if (ConnectivityService.isOnline) {
        employe = await SupabaseService.verifierEmployee(
            widget.entrepriseId, identifiant, motDePasse);
      } else {
        employe = await LocalDatabase.verifierEmployeeCache(
            widget.entrepriseId, identifiant, motDePasse);
      }
      if (employe == null) {
        setState(() {
          _erreur = ConnectivityService.isOnline
              ? 'Identifiant ou code incorrect.'
              : 'Employé introuvable dans le cache local (hors-ligne).';
        });
      }
      return employe;
    } catch (e) {
      setState(() => _erreur = 'Erreur : $e');
      return null;
    }
  }

  Future<bool> _valider() async {
    final employe = await _verifierEmploye();
    if (employe == null) return false;
    await Future.delayed(const Duration(milliseconds: 850));
    if (mounted) Navigator.pop(context, employe);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final palettePause = widget.maquettePause
        ? AccueilPalette.pour(
            MotifService.actif.value,
            Theme.of(context).brightness == Brightness.dark,
          )
        : null;
    final couleurTexte = palettePause?.texte ??
        Theme.of(context).textTheme.bodyLarge?.color ??
        EnCheckColors.brunProfond;
    // 📱 TÉLÉPHONE (fiche « Affichage mobile ») : petit appareil = largeur
    // étroite OU fenêtre très courte (paysage).
    final tailleFenetre = MediaQuery.sizeOf(context);
    final bool estTelephone =
        tailleFenetre.width < 620 || tailleFenetre.height < 520;

    return Scaffold(
      // Pause masque la scène et le pied quand le clavier apparaît. Le
      // Scaffold ne retire donc pas l'inset avant notre propre adaptation.
      resizeToAvoidBottomInset: !widget.maquettePause,
      backgroundColor:
          palettePause?.fond ?? Theme.of(context).scaffoldBackgroundColor,
      body: Focus(
        autofocus: true,
        onKeyEvent: (noeud, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          // En téléphone, la photo passe derrière la barre d'état (le texte
          // reste sous l'encoche : zones réservées respectées).
          top: !estTelephone,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 📱 TÉLÉPHONE : photo pleine largeur, champs toujours
              // utilisables avec le clavier.
              if (estTelephone) {
                return SansEtirement(
                  child: _corpsTelephone(context, themeService, couleurTexte,
                      constraints, MediaQuery.of(context), palettePause),
                );
              }
              final scrollDeSecours = constraints.maxHeight < 700 ||
                  constraints.maxWidth < 620;
              final contenu = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    mainAxisSize:
                        scrollDeSecours ? MainAxisSize.min : MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildScene(
                        context,
                        themeService,
                        hauteur: widget.maquettePause ? 220 : 195,
                      ),
                      ValueListenableBuilder<MotifCulturel>(
                        valueListenable: MotifService.actif,
                        builder: (context, motif, _) => FriseMotif(
                          key: widget.maquettePause
                              ? const Key('pause-frise')
                              : null,
                          motif: motif,
                          hauteur: widget.maquettePause ? 40 : 10,
                          tuilee: widget.maquettePause,
                          opacite: widget.maquettePause ? 0.96 : 1,
                          fond: palettePause?.carteDouce,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 18),
                        child: _buildCarteIdentification(
                          context,
                          couleurTexte,
                          paddingV: widget.maquettePause ? 14 : 20,
                          palette: palettePause,
                        ),
                      ),
                      if (!scrollDeSecours) const Spacer(),
                      Center(
                        child: TextButton.icon(
                          key: widget.maquettePause
                              ? const Key('pause-retour')
                              : null,
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.arrow_back,
                              size: 16,
                              color: palettePause?.texteSecondaire ??
                                  EnCheckColors.gris),
                          label: Text(
                            'Retour',
                            style: TextStyle(
                                fontSize: widget.maquettePause ? 14 : 13,
                                color: palettePause?.texteSecondaire ??
                                    EnCheckColors.gris),
                          ),
                        ),
                      ),
                      Text(
                        'v1.0.0 • Chiffrement AES-256 • Serveur UE',
                        key: widget.maquettePause
                            ? const Key('pause-pied')
                            : null,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          color: palettePause?.texteSecondaire ??
                              EnCheckColors.gris.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
              if (scrollDeSecours) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: contenu,
                );
              }
              return contenu;
            },
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 CORPS EN TÉLÉPHONE — fiche « Affichage mobile »
  // ═══════════════════════════════════════════════════════════
  //
  //  Photo pleine largeur (derrière la barre d'état), tout tient sans
  //  défilement, et les champs + « Glisser pour valider » restent
  //  utilisables quand le clavier apparaît : la photo et les éléments
  //  secondaires se retirent le temps de la frappe.
  // ═══════════════════════════════════════════════════════════

  Widget _corpsTelephone(
    BuildContext context,
    ThemeService themeService,
    Color couleurTexte,
    BoxConstraints constraints,
    MediaQueryData media,
    AccueilPalette? palette,
  ) {
    final clavierOuvert = media.viewInsets.bottom > 0;
    final double echelleTexte = media.textScaler.scale(1.0);
    final double hauteurTotale = constraints.maxHeight;
    final proportionScene = echelleTexte > 1.3
        ? 0.15
        : widget.maquettePause
            ? 0.26
            : 0.21;
    final hauteurMaxScene = !widget.maquettePause
        ? 150.0
        : hauteurTotale >= 760
            ? 230.0
            : hauteurTotale < 700
                ? 130.0
                : 150.0;
    final double hauteurScene = clavierOuvert
        ? 0.0
        : (hauteurTotale * proportionScene)
            .clamp(0.0, hauteurMaxScene)
            .toDouble();
    final bool tropPetit = hauteurTotale < 560 || echelleTexte > 1.45;

    final carte = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        clavierOuvert
            ? 6
            : widget.maquettePause
                ? (hauteurTotale < 700 ? 22 : 30)
                : 12,
        16,
        clavierOuvert ? 6 : widget.maquettePause ? 0 : 12,
      ),
      child: _buildCarteIdentification(
        context,
        couleurTexte,
        paddingV: clavierOuvert
            ? 12
            : widget.maquettePause
                ? 14
                : 20,
        palette: palette,
      ),
    );
    final pied = Text(
      'v1.0.0 • Chiffrement AES-256 • Serveur UE',
      key: widget.maquettePause ? const Key('pause-pied') : null,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: widget.maquettePause ? 10 : 9,
        color: palette?.texteSecondaire ?? EnCheckColors.gris.withOpacity(0.9),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!clavierOuvert && hauteurScene > 0)
          _buildScene(context, themeService,
              hauteur: hauteurScene, margeHaut: media.viewPadding.top),
        if (!clavierOuvert)
          ValueListenableBuilder<MotifCulturel>(
            valueListenable: MotifService.actif,
            builder: (context, motif, _) => FriseMotif(
              key: widget.maquettePause ? const Key('pause-frise') : null,
              motif: motif,
              hauteur: widget.maquettePause ? 40 : 8,
              tuilee: widget.maquettePause,
              opacite: widget.maquettePause ? 0.96 : 1,
              fond: palette?.carteDouce,
            ),
          ),
        // Ne défile QUE si la configuration ne permet pas tout d'afficher
        // d'un coup (jamais en silence : la bande « faites défiler » le dit).
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [carte],
            ),
          ),
        ),
        if (tropPetit && !clavierOuvert) _bandeDefilementIdent(),
        if (!clavierOuvert) ...[
          Center(
            child: TextButton.icon(
              key: widget.maquettePause ? const Key('pause-retour') : null,
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back,
                  size: 16,
                  color: palette?.texteSecondaire ?? EnCheckColors.gris),
              label: Text(
                'Retour',
                style: TextStyle(
                    fontSize: widget.maquettePause ? 14 : 13,
                    color: palette?.texteSecondaire ?? EnCheckColors.gris),
              ),
            ),
          ),
          pied,
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _bandeDefilementIdent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.unfold_more, size: 14, color: EnCheckColors.terreChaude),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Contenu plus grand que l'écran : faites défiler.",
              style:
                  TextStyle(fontSize: 11.5, color: EnCheckColors.brunProfond),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScene(BuildContext context, ThemeService themeService,
      {double hauteur = 195, double margeHaut = 0}) {
    if (widget.maquettePause) {
      return _buildScenePause(context, themeService,
          hauteur: hauteur, margeHaut: margeHaut);
    }
    return SizedBox(
      height: hauteur,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.sceneAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.1),
            errorBuilder: (_, __, ___) =>
                Container(color: EnCheckColors.brunProfond),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.42),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5],
              ),
            ),
          ),
          Positioned(
            top: 12 + margeHaut,
            left: 14,
            right: 14,
            child: Row(
              children: [
                _rondScene(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
                const Spacer(),
                Text(
                  widget.titre,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: EnCheckColors.blanc,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                const Spacer(),
                _rondScene(
                  icon: Icons.light_mode,
                  actif: !themeService.isDarkMode,
                  onTap: () => themeService.setDarkMode(false),
                ),
                const SizedBox(width: 7),
                _rondScene(
                  icon: Icons.dark_mode,
                  actif: themeService.isDarkMode,
                  onTap: () => themeService.setDarkMode(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Scène de la maquette Pause : titre réellement centré, retour à gauche
  /// et UNE commande de thème à droite, comme sur l'accueil validé.
  Widget _buildScenePause(BuildContext context, ThemeService themeService,
      {required double hauteur, required double margeHaut}) {
    return SizedBox(
      key: const Key('pause-scene'),
      height: hauteur,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.sceneAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.1),
            errorBuilder: (_, __, ___) =>
                Container(color: EnCheckColors.brunProfond),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.32), Colors.transparent],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          Positioned(
            top: 12 + margeHaut,
            left: 14,
            child: Semantics(
              button: true,
              label: 'Retour',
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.90),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: EnCheckColors.brunProfond,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12 + margeHaut,
            left: 70,
            right: 70,
            child: SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  widget.titre,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: EnCheckColors.blanc,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 13 + margeHaut,
            right: 14,
            child: _boutonLunePause(themeService),
          ),
        ],
      ),
    );
  }

  Widget _boutonLunePause(ThemeService themeService) {
    final sombre = themeService.isDarkMode;
    return Semantics(
      button: true,
      label: sombre ? 'Activer le mode clair' : 'Activer le mode sombre',
      child: GestureDetector(
        key: const Key('pause-theme'),
        onTap: () => themeService.setDarkMode(!sombre),
        child: Container(
          width: 53,
          height: 33,
          decoration: BoxDecoration(
            color: sombre ? const Color(0xFF2A2A27) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            sombre ? Icons.light_mode : Icons.dark_mode,
            size: 20,
            color: sombre ? const Color(0xFFF5F1EA) : const Color(0xFF252525),
          ),
        ),
      ),
    );
  }

  Widget _rondScene({
    required IconData icon,
    required VoidCallback onTap,
    bool actif = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              actif ? EnCheckColors.orDoux : Colors.white.withOpacity(0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: EnCheckColors.brunProfond),
      ),
    );
  }

  Widget _buildCarteIdentification(
    BuildContext context,
    Color couleurTexte, {
    double paddingV = 20,
    AccueilPalette? palette,
  }) {
    final estPause = palette != null;
    return Container(
      key: estPause ? const Key('pause-carte-identification') : null,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: paddingV),
      decoration: BoxDecoration(
        color: palette?.surface ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(estPause ? 16 : 20),
        border: Border.all(
          color: palette?.texteTertiaire.withOpacity(0.62) ??
              Theme.of(context).dividerColor.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'IDENTIFIEZ-VOUS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12.5,
              fontWeight: estPause ? FontWeight.w500 : FontWeight.w700,
              letterSpacing: 2.2,
              color: palette?.texte ?? EnCheckColors.gris,
            ),
          ),
          const SizedBox(height: 16),
          _champ(
            label: 'Identifiant',
            controller: _identifiantCtrl,
            obscure: false,
            couleurTexte: couleurTexte,
            action: TextInputAction.next,
            chiffresSeuls: true,
            palette: palette,
          ),
          const SizedBox(height: 12),
          _champ(
            label: 'Code',
            controller: _motDePasseCtrl,
            obscure: true,
            couleurTexte: couleurTexte,
            action: TextInputAction.done,
            onSubmis: (_) => _valider(),
            palette: palette,
          ),
          SizedBox(height: estPause ? 8 : 10),
          Text(
            widget.aide,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: estPause ? 13 : 12.5,
              color: palette?.texteSecondaire ?? EnCheckColors.gris,
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 10),
            Text(
              _erreur!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: EnCheckColors.erreur,
                  fontWeight: FontWeight.w600),
            ),
          ],
          SizedBox(height: estPause ? 14 : 16),
          SlideValider(
            key: estPause ? const Key('pause-glisser-valider') : null,
            onGlisse: _valider,
            fond: palette?.primaire,
            bordure: palette?.primaire,
            texte: palette?.surPrimaire,
            bouton: palette?.cerclePrimaire,
            bordureBouton: palette?.primaire,
            icone: palette?.iconePrimaire,
          ),
          if (widget.statut != null) ...[
            const SizedBox(height: 14),
            widget.statut!,
          ],
          if (palette != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: MotifSymbole(
                key: const Key('pause-motif-symbole'),
                motif: MotifService.actif.value,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _champ({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required Color couleurTexte,
    required TextInputAction action,
    void Function(String)? onSubmis,
    bool chiffresSeuls = false,
    AccueilPalette? palette,
  }) {
    final textePrefixe = chiffresSeuls && widget.matriculePrefix.isNotEmpty
        ? '${widget.matriculePrefix}-'
        : null;
    final stylePrefixe = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: couleurTexte,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: palette != null ? 12.5 : 12,
            fontWeight: palette != null ? FontWeight.w600 : FontWeight.w700,
            color: palette?.texteSecondaire ?? EnCheckColors.gris,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          textInputAction: action,
          keyboardType: chiffresSeuls ? TextInputType.number : null,
          inputFormatters: chiffresSeuls
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          maxLength: chiffresSeuls ? 6 : null,
          onSubmitted: onSubmis,
          cursorColor: palette?.primaire,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: obscure ? 6 : 1.5,
            color: couleurTexte,
          ),
          decoration: InputDecoration(
            counterText: chiffresSeuls ? '' : null,
            // Pause affiche ENN- même sans focus et sans ouvrir le clavier.
            // L'ancien parcours conserve son prefixText d'origine.
            prefixText: palette == null ? textePrefixe : null,
            prefix: palette != null && textePrefixe != null
                ? Text(textePrefixe, style: stylePrefixe)
                : null,
            prefixStyle: stylePrefixe,
            filled: true,
            isDense: palette != null,
            fillColor: palette?.carteDouce ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.07)
                    : const Color(0xFFF6F1E8)),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: palette != null ? 8 : 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

}
