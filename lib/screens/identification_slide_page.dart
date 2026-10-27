// lib/screens/identification_slide_page.dart
// ═══════════════════════════════════════════════════════════
// 🪪 PAGE D'IDENTIFICATION — identifiant + mot de passe + slide
// ═══════════════════════════════════════════════════════════
//
//  MAQUETTE VALIDÉE le 27/10 (page Pause) : scène chaleureuse en haut,
//  frise raphia, carte « IDENTIFIEZ-VOUS » (identifiant + mot de passe),
//  puis « Glisser pour valider ». Utilisée par la PAUSE et par le
//  POINTAGE (le même écran, titre et scène adaptés).
//
//  Vérification : SupabaseService.verifierEmployee (en ligne) ou
//  LocalDatabase.verifierEmployeeCache (hors-ligne) — identique à
//  l'ancien parcours matricule + PIN.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, FilteringTextInputFormatter;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/local_database.dart';
import '../services/motif_service.dart';
import '../services/supabase_service.dart';
import '../services/theme_service.dart';
import '../widgets/frise_motif.dart';
import '../widgets/logo_empreinte.dart';
import '../widgets/slide_valider.dart';

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

  /// Appelée après identification réussie : true = succès (la page se ferme).
  final Future<bool> Function(Map<String, dynamic> employe) onValide;

  const IdentificationSlidePage({
    super.key,
    required this.titre,
    required this.sceneAsset,
    required this.aide,
    required this.entrepriseId,
    this.matriculePrefix = '',
    this.matriculeInitial,
    this.statut,
    required this.onValide,
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
    _identifiantCtrl = TextEditingController(text: widget.matriculeInitial ?? '');
  }

  @override
  void dispose() {
    _identifiantCtrl.dispose();
    _motDePasseCtrl.dispose();
    super.dispose();
  }

  Future<bool> _valider() async {
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
      setState(() => _erreur = "Renseignez l'identifiant et le mot de passe.");
      return false;
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
              ? 'Identifiant ou mot de passe incorrect.'
              : 'Employé introuvable dans le cache local (hors-ligne).';
        });
        return false;
      }
      return await widget.onValide(employe);
    } catch (e) {
      setState(() => _erreur = 'Erreur : $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final couleurTexte = Theme.of(context).textTheme.bodyLarge?.color ??
        EnCheckColors.brunProfond;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scrollDeSecours = constraints.maxHeight < 700;
              final contenu = Column(
                mainAxisSize:
                    scrollDeSecours ? MainAxisSize.min : MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScene(context, themeService),
                  ValueListenableBuilder<MotifCulturel>(
                    valueListenable: MotifService.actif,
                    builder: (context, motif, _) =>
                        FriseMotif(motif: motif, hauteur: 26),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 16),
                    child: _buildCarteIdentification(
                        context, themeService, couleurTexte),
                  ),
                  if (!scrollDeSecours) const Spacer(),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back,
                          size: 16, color: EnCheckColors.gris),
                      label: const Text(
                        'Retour au pointage',
                        style: TextStyle(
                            fontSize: 13, color: EnCheckColors.gris),
                      ),
                    ),
                  ),
                  Text(
                    'v1.0.0 • Chiffrement AES-256 • Serveur UE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: EnCheckColors.gris.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
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

  Widget _buildScene(BuildContext context, ThemeService themeService) {
    return SizedBox(
      height: 235,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.sceneAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: EnCheckColors.brunProfond),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.25),
                  Colors.transparent,
                  Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: Row(
              children: [
                _rondScene(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
                const Spacer(),
                _rondScene(
                  icon: Icons.light_mode,
                  actif: !themeService.isDarkMode,
                  onTap: () => themeService.setDarkMode(false),
                ),
                const SizedBox(width: 8),
                _rondScene(
                  icon: Icons.dark_mode,
                  actif: themeService.isDarkMode,
                  onTap: () => themeService.setDarkMode(true),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            bottom: 14,
            child: Row(
              children: [
                const LogoEmpreinte(taille: 40),
                const SizedBox(width: 12),
                Text(
                  widget.titre,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: EnCheckColors.blanc,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: actif
              ? EnCheckColors.orDoux
              : Colors.white.withOpacity(0.82),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color:
              actif ? EnCheckColors.brunProfond : EnCheckColors.brunProfond,
        ),
      ),
    );
  }

  Widget _buildCarteIdentification(BuildContext context,
      ThemeService themeService, Color couleurTexte) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'IDENTIFIEZ-VOUS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: couleurTexte,
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
          ),
          const SizedBox(height: 12),
          _champ(
            label: 'Mot de passe',
            controller: _motDePasseCtrl,
            obscure: true,
            couleurTexte: couleurTexte,
            action: TextInputAction.done,
            onSubmis: (_) => _valider(),
          ),
          const SizedBox(height: 10),
          Text(
            widget.aide,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: EnCheckColors.gris),
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
          const SizedBox(height: 16),
          SlideValider(onGlisse: _valider),
          if (widget.statut != null) ...[
            const SizedBox(height: 14),
            widget.statut!,
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: EnCheckColors.gris,
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
          textCapitalization: TextCapitalization.characters,
          onSubmitted: onSubmis,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: obscure ? 6 : 1.5,
            color: couleurTexte,
          ),
          decoration: InputDecoration(
            counterText: chiffresSeuls ? '' : null,
            prefixText: chiffresSeuls && widget.matriculePrefix.isNotEmpty
                ? '${widget.matriculePrefix}-'
                : null,
            prefixStyle: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: couleurTexte,
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.07)
                : const Color(0xFFF3EADA),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
