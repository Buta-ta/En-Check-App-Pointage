import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/annonces_accueil_service.dart';

/// Média publicitaire de l'accueil : conserve le cadre 16:9 et ne charge que
/// l'annonce courante (avec préchargement image facultatif de la suivante).
class CarrouselAnnoncesAccueil extends StatefulWidget {
  const CarrouselAnnoncesAccueil({
    super.key,
    required this.entrepriseId,
    required this.annonces,
    this.imageParDefaut = 'assets/scenes/scene_pointage.jpg',
    this.fondParDefaut = const Color(0xFF233A37),
  });

  final String entrepriseId;
  final List<AnnonceAccueil> annonces;
  final String imageParDefaut;
  final Color fondParDefaut;

  @override
  State<CarrouselAnnoncesAccueil> createState() =>
      _CarrouselAnnoncesAccueilState();
}

class _CarrouselAnnoncesAccueilState extends State<CarrouselAnnoncesAccueil> {
  Timer? _rotation;
  int _index = 0;

  String get _signature => widget.annonces
      .map((annonce) => annonce.signature)
      .join('\u001f');

  int _largeurCache(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(480, 1600)
          .toInt();

  @override
  void initState() {
    super.initState();
    _programmerRotation();
  }

  @override
  void didUpdateWidget(covariant CarrouselAnnoncesAccueil oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ancienneSignature = oldWidget.annonces
        .map((annonce) => annonce.signature)
        .join('\u001f');
    if (oldWidget.entrepriseId != widget.entrepriseId ||
        ancienneSignature != _signature) {
      _rotation?.cancel();
      _index = 0;
      _programmerRotation();
    }
  }

  @override
  void dispose() {
    _rotation?.cancel();
    super.dispose();
  }

  void _programmerRotation() {
    _rotation?.cancel();
    if (widget.annonces.length <= 1) return;
    final duration = widget.annonces[_index].dureeAffichageMs;
    _rotation = Timer(Duration(milliseconds: duration), _passerAuSuivant);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prechargerAnnonceSuivante();
    });
  }

  void _passerAuSuivant() {
    if (!mounted || widget.annonces.length <= 1) return;
    setState(() => _index = (_index + 1) % widget.annonces.length);
    _programmerRotation();
  }

  void _prechargerAnnonceSuivante() {
    if (!mounted || widget.annonces.length <= 1) return;
    final suivante = widget.annonces[(_index + 1) % widget.annonces.length];
    if (suivante.type == 'video') return;
    final cacheWidth = _largeurCache(context);
    unawaited(
      precacheImage(
        ResizeImage(NetworkImage(suivante.urlVersionnee), width: cacheWidth),
        context,
      ).catchError((Object _) {}),
    );
  }

  Widget _mediaCourant(BuildContext context) {
    if (widget.annonces.isEmpty) return _imageLocale(context);
    final annonce = widget.annonces[_index];
    final cle = ValueKey('${widget.entrepriseId}:${annonce.signature}');
    if (annonce.type == 'video') {
      return _VideoAnnonce(
        key: cle,
        url: annonce.urlVersionnee,
        fallback: _imageLocale(context),
      );
    }
    return _ImageAnnonce(
      key: cle,
      url: annonce.urlVersionnee,
      fallback: _imageLocale(context),
      cacheWidth: _largeurCache(context),
    );
  }

  Widget _imageLocale(BuildContext context) {
    return Image.asset(
      widget.imageParDefaut,
      key: const ValueKey('photo-locale-accueil'),
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.20),
      cacheWidth: _largeurCache(context),
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => ColoredBox(color: widget.fondParDefaut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);
    final label = widget.annonces.isEmpty
        ? 'Photo d’accueil En-Check'
        : 'Annonce ${_index + 1} sur ${widget.annonces.length}';

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Semantics(
        image: true,
        label: label,
        child: ClipRect(
          child: ColoredBox(
            color: widget.fondParDefaut,
            child: AnimatedSwitcher(
              key: ValueKey('campagne-${widget.entrepriseId}'),
              duration: duration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: SizedBox.expand(
                key: ValueKey(
                  widget.annonces.isEmpty
                      ? 'media-slot-photo-locale'
                      : 'media-slot-${widget.entrepriseId}:${widget.annonces[_index].signature}',
                ),
                child: _mediaCourant(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageAnnonce extends StatelessWidget {
  const _ImageAnnonce({
    super.key,
    required this.url,
    required this.fallback,
    required this.cacheWidth,
  });

  final String url;
  final Widget fallback;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _VideoAnnonce extends StatefulWidget {
  const _VideoAnnonce({
    super.key,
    required this.url,
    required this.fallback,
  });

  final String url;
  final Widget fallback;

  @override
  State<_VideoAnnonce> createState() => _VideoAnnonceState();
}

class _VideoAnnonceState extends State<_VideoAnnonce> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    unawaited(_initialiserVideo());
  }

  Future<void> _initialiserVideo() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      await _controller.setLooping(true);
      if (!mounted) return;
      setState(() {}); // remplace le visuel de secours par le lecteur prêt
      await _controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_controller.value.isInitialized) return widget.fallback;
    final size = _controller.value.size;
    if (size.width <= 0 || size.height <= 0) return widget.fallback;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
