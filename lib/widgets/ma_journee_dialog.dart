import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/historique_periode.dart';
import '../theme/app_theme.dart';

class ResultatVerificationJournee {
  final Map<String, dynamic>? employee;
  final String? messageErreur;

  const ResultatVerificationJournee.reussite(this.employee)
      : messageErreur = null;

  const ResultatVerificationJournee.echec(this.messageErreur) : employee = null;
}

/// Modale de consultation uniquement. La validation reste fournie par
/// l'appelant afin de réutiliser exactement le flux en ligne / hors-ligne.
class MaJourneeDialog extends StatefulWidget {
  final String prefixeEntreprise;
  final Future<ResultatVerificationJournee> Function(
      String matriculeComplet, String pin) verifier;

  const MaJourneeDialog({
    super.key,
    required this.prefixeEntreprise,
    required this.verifier,
  });

  @override
  State<MaJourneeDialog> createState() => _MaJourneeDialogState();
}

class _MaJourneeDialogState extends State<MaJourneeDialog> {
  final _matriculeController = TextEditingController();
  final _pinController = TextEditingController();
  final _matriculeFocus = FocusNode(debugLabel: 'Matricule Ma journée');
  final _pinFocus = FocusNode(debugLabel: 'PIN Ma journée');
  bool _verificationEnCours = false;
  String? _messageErreur;

  @override
  void dispose() {
    _matriculeController.clear();
    _pinController.clear();
    _matriculeController.dispose();
    _pinController.dispose();
    _matriculeFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _annuler() {
    _matriculeController.clear();
    _pinController.clear();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _consulter() async {
    final saisie = _matriculeController.text.trim();
    final pin = _pinController.text;
    if (saisie.isEmpty) {
      setState(() => _messageErreur = 'Saisissez votre matricule.');
      _matriculeFocus.requestFocus();
      return;
    }
    if (pin.length < 4) {
      setState(() => _messageErreur = 'Le PIN doit contenir au moins 4 chiffres.');
      _pinFocus.requestFocus();
      return;
    }

    setState(() {
      _verificationEnCours = true;
      _messageErreur = null;
    });
    try {
      final matricule = HistoriquePeriode.matriculeComplet(
        saisie,
        widget.prefixeEntreprise,
      );
      final resultat = await widget.verifier(matricule, pin);
      if (!mounted) return;
      if (resultat.employee != null) {
        Navigator.of(context).pop<Map<String, dynamic>>(resultat.employee);
        return;
      }
      setState(() {
        _verificationEnCours = false;
        _messageErreur = resultat.messageErreur ?? 'Identification impossible.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verificationEnCours = false;
        _messageErreur = 'Vérification impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sombre = theme.brightness == Brightness.dark;
    final couleurSurface = sombre
        ? const Color(0xFF1D1E1C)
        : EnCheckColors.carteClaire;
    final couleurChamp = sombre
        ? const Color(0xFF2A2A27)
        : EnCheckColors.blanc;
    final couleurTexte = sombre
        ? const Color(0xFFF5F1EA)
        : EnCheckColors.textePrincipal;
    final couleurSecondaire = sombre
        ? const Color(0xFFC2BEB5)
        : EnCheckColors.texteSecondaire;
    final couleurAccent = sombre
        ? const Color(0xFF9FCBC6)
        : EnCheckColors.vertAccent;
    final couleurBordure = sombre
        ? const Color(0xFF4A4842)
        : EnCheckColors.bordureClaire;
    final taille = MediaQuery.sizeOf(context);
    final clavier = MediaQuery.viewInsetsOf(context).bottom;
    final prefixe = widget.prefixeEntreprise
        .trim()
        .toUpperCase()
        .replaceFirst(RegExp(r'-+$'), '');

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: (taille.height - clavier - 40)
            .clamp(180.0, taille.height)
            .toDouble(),
      ),
      backgroundColor: couleurSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: couleurBordure),
      ),
      title: Row(
        children: [
          Icon(Icons.today_outlined, color: couleurAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'MA JOURNÉE',
              style: TextStyle(
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: couleurTexte,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saisissez votre matricule et votre PIN pour consulter vos pointages du jour. Aucun pointage ne sera enregistré.',
            style: TextStyle(
              color: couleurSecondaire,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('ma-journee-matricule'),
            controller: _matriculeController,
            focusNode: _matriculeFocus,
            style: TextStyle(color: couleurTexte),
            cursorColor: couleurAccent,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
            ],
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_verificationEnCours,
            onSubmitted: (_) => _pinFocus.requestFocus(),
            decoration: InputDecoration(
              labelText: 'Matricule',
              labelStyle: TextStyle(color: couleurSecondaire),
              hintText: 'Ex. 0002',
              hintStyle: TextStyle(color: couleurSecondaire.withOpacity(0.8)),
              prefixIconColor: couleurSecondaire,
              prefixIcon: Row(
                key: const Key('ma-journee-prefixe'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.badge_outlined),
                  if (prefixe.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$prefixe-',
                      style: TextStyle(
                        color: couleurTexte,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else
                    const SizedBox(width: 14),
                ],
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              filled: true,
              fillColor: couleurChamp,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurBordure),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurBordure),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('ma-journee-pin'),
            controller: _pinController,
            focusNode: _pinFocus,
            style: TextStyle(color: couleurTexte),
            cursorColor: couleurAccent,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_verificationEnCours,
            onSubmitted: (_) => _consulter(),
            decoration: InputDecoration(
              labelText: 'PIN',
              labelStyle: TextStyle(color: couleurSecondaire),
              hintText: 'Ex. 1234',
              hintStyle: TextStyle(color: couleurSecondaire.withOpacity(0.8)),
              prefixIcon: const Icon(Icons.lock_outline),
              prefixIconColor: couleurSecondaire,
              filled: true,
              fillColor: couleurChamp,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurBordure),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurBordure),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: couleurAccent, width: 1.5),
              ),
            ),
          ),
          if (_messageErreur != null) ...[
            const SizedBox(height: 12),
            Text(
              _messageErreur!,
              style: const TextStyle(color: EnCheckColors.erreur, fontSize: 13),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: _verificationEnCours ? null : _annuler,
          style: TextButton.styleFrom(foregroundColor: couleurAccent),
          child: const Text('ANNULER'),
        ),
        ElevatedButton(
          key: const Key('ma-journee-consulter'),
          onPressed: _verificationEnCours ? null : _consulter,
          style: ElevatedButton.styleFrom(
            backgroundColor: sombre
                ? const Color(0xFF3D6F74)
                : EnCheckColors.vertBouton,
            foregroundColor: EnCheckColors.blanc,
            minimumSize: const Size(120, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _verificationEnCours
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EnCheckColors.blanc,
                  ),
                )
              : const Text('CONSULTER'),
        ),
      ],
    );
  }
}
