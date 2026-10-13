import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../widgets/logo_empreinte.dart';
import 'pointage_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _verifierCode() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    final code = _codeController.text.trim().toUpperCase();

    try {
      final response =
      await SupabaseService.client
          .from('enterprises')
          .select()
          .eq('code', code)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        final prefs = await SharedPreferences.getInstance();

        // Infos de base
        await prefs.setString('enterprise_id', response['id']);
        await prefs.setString('enterprise_name', response['name']);

        if (response['logo_url'] != null) {
          await prefs.setString('enterprise_logo', response['logo_url']);
        }
        if (response['matricule_prefix'] != null) {
          await prefs.setString('matricule_prefix', response['matricule_prefix']);
        }

        // 🔐 SAUVEGARDER LES MODULES
        await prefs.setBool('module_qr_scanner', response['module_qr_scanner'] ?? false);
        await prefs.setBool('module_photo_pointage', response['module_photo_pointage'] ?? false);
        await prefs.setBool('module_planning', response['module_planning'] ?? false);
        await prefs.setBool('module_retards', response['module_retards'] ?? false);

        // 🌍 NOUVEAU - Module geofencing
        await prefs.setBool('module_geolocalisation', response['module_geolocalisation'] ?? false);

        // 📷 NOUVEAU - Modules futurs (préparation)
        await prefs.setBool('module_reconnaissance_faciale', response['module_reconnaissance_faciale'] ?? false);
        await prefs.setBool('module_carte_temps_reel', response['module_carte_temps_reel'] ?? false);

        await prefs.setString('license_type', response['license_type'] ?? 'basic');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PointageScreen()),
          );
        }
      } else {
        setState(() => _error = 'Code entreprise introuvable');
      }
    } catch (e) {
      // Dire « Erreur de connexion internet » pour un refus d'autorisation
      // envoyait l'administrateur vérifier sa connexion alors que le correctif
      // est un GRANT SQL côté Supabase. messageErreur() fait la distinction.
      setState(() => _error = SupabaseService.messageErreur(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EnCheckColors.sableClair,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),

                const LogoEmpreinte(taille: 140),

                const SizedBox(height: 20),

                const Text(
                  'EN-CHECK',
                  style: EnCheckTextStyles.titrePrincipal,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                const Text(
                  'Bienvenue',
                  style: TextStyle(
                    color: EnCheckColors.terreChaude,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  'Veuillez entrer le code de votre entreprise pour configurer l\'appareil.',
                  style: TextStyle(color: EnCheckColors.brunProfond, fontSize: 16, height: 1.5),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                    color: EnCheckColors.brunProfond,
                  ),
                  decoration: InputDecoration(
                    hintText: 'CODE',
                    hintStyle: TextStyle(
                      color: EnCheckColors.gris.withOpacity(0.5),
                      letterSpacing: 4,
                    ),
                    filled: true,
                    fillColor: EnCheckColors.blanc,
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _error,
                    prefixIcon: const Icon(Icons.vpn_key, color: EnCheckColors.sableDore),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _verifierCode(),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verifierCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EnCheckColors.terreChaude,
                      foregroundColor: EnCheckColors.blanc,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child:
                    _loading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'VALIDER',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}