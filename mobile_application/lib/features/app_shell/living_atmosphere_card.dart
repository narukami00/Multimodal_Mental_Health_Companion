import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/ambient_audio_service.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The 8 Therapeutic Emotional Biomes
enum SanctuaryBiome {
  dunes('Golden Dunes', 'Grounding Sunset · Calm Focus'),
  lake('Lavender Lake', 'Tender Dusk · Vulnerable Softness'),
  meadow('Sunlit Meadow', 'Quiet Peace · Fresh Clarity'),
  hearth('Starlit Hearth', 'Deep Night · Sacred Rest'),
  pines('Emerald Pines', 'Forest Solitude · Deep Breath'),
  frost('Alpine Frost', 'Glacier Clarity · Silent Horizon'),
  sakura('Sakura Garden', 'Gentle Renewal · Tender Hope'),
  aurora('Cosmic Aurora', 'Celestial Wonder · Vast Mystery');

  const SanctuaryBiome(this.name, this.sub);

  final String name;
  final String sub;
}

class LivingAtmosphereCard extends StatefulWidget {
  const LivingAtmosphereCard({
    this.initialBiome = SanctuaryBiome.dunes,
    this.onBiomeChanged,
    super.key,
  });

  final SanctuaryBiome initialBiome;
  final ValueChanged<SanctuaryBiome>? onBiomeChanged;

  @override
  State<LivingAtmosphereCard> createState() => _LivingAtmosphereCardState();
}

class _LivingAtmosphereCardState extends State<LivingAtmosphereCard>
    with TickerProviderStateMixin {
  late SanctuaryBiome _currentBiome;
  late SanctuaryBiome _targetBiome;
  SoundscapeMode get _currentSound => AmbientAudioService.instance.currentMode;

  late final AnimationController _tickerController;
  late final AnimationController _transitionController;
  late final Animation<double> _transitionCurve;

  double _animTime = 0.0;
  final List<_SplashParticle> _splashes = [];
  final List<_RippleEffect> _ripples = [];
  final List<_EmberParticle> _embers = [];
  final List<_WindParticle> _windParticles = [];
  final List<_CraneEntity> _cranes = [
    _CraneEntity(x: 40, y: 55, vx: 0.60, size: 0.85, phase: 0.0),
    _CraneEntity(x: 75, y: 72, vx: 0.60, size: 0.70, phase: 0.9),
  ];

  @override
  void initState() {
    super.initState();
    _currentBiome = widget.initialBiome;
    _targetBiome = widget.initialBiome;

    AmbientAudioService.instance.currentModeNotifier.addListener(_onAudioModeChanged);

    // Infinite 60 FPS continuous ambient physics ticker
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(_onTick);
    if (!_isTestEnvironment) {
      _tickerController.repeat();
    }

    // 1.2s smooth state transition controller
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _currentBiome = _targetBiome;
          });
        }
      });
    _transitionCurve = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeInOutCubic,
    );
  }

  void _onAudioModeChanged() {
    if (mounted) setState(() {});
  }

  void _onTick() {
    setState(() {
      _animTime += 0.016;
      _updateParticles();
    });
  }

  void _updateParticles() {
    // Update cranes
    for (final crane in _cranes) {
      crane.x += crane.vx;
      if (crane.x > 420) {
        crane.x = -40;
      }
    }

    // Update weather particles based on active soundscape
    if (_currentSound == SoundscapeMode.hearth) {
      if (_embers.length < 24) {
        final spawnX = _targetBiome == SanctuaryBiome.hearth ? 100.0 : 190.0;
        final rng = math.Random();
        _embers.add(_EmberParticle(
          x: spawnX + (rng.nextDouble() - 0.5) * 28,
          y: 200.0,
          vx: (rng.nextDouble() - 0.5) * 1.3,
          vy: -(1.1 + rng.nextDouble() * 1.4),
          r: 1.2 + rng.nextDouble() * 2.0,
          life: 1.0,
          eddyPhase: rng.nextDouble() * math.pi * 2,
        ));
      }
      for (var i = _embers.length - 1; i >= 0; i--) {
        final p = _embers[i];
        p.life -= 0.012;
        p.x += p.vx + math.sin(_animTime * 5 + p.eddyPhase + p.y * 0.04) * 0.8;
        p.y += p.vy;
        p.vy -= 0.01; // thermal upward buoyancy
        if (p.life <= 0 || p.y < 0) {
          _embers.removeAt(i);
        }
      }
    } else {
      _embers.clear();
    }

    // Update rain splashes & ripples
    for (var i = _splashes.length - 1; i >= 0; i--) {
      final s = _splashes[i];
      s.x += s.vx;
      s.y += s.vy;
      s.vy += 0.18; // gravity
      s.alpha -= 0.035;
      if (s.alpha <= 0 || s.y > 240) {
        _splashes.removeAt(i);
      }
    }

    for (var i = _ripples.length - 1; i >= 0; i--) {
      final r = _ripples[i];
      r.radius += 0.38;
      r.alpha -= 0.018;
      if (r.alpha <= 0 || r.radius >= r.maxRadius) {
        _ripples.removeAt(i);
      }
    }

    // Update wind streamlines & dust
    if (_currentSound == SoundscapeMode.wind) {
      final rng = math.Random();
      if (_windParticles.length < 14) {
        _windParticles.add(_WindParticle(
          x: -50,
          y: 50 + rng.nextDouble() * 130,
          vx: 3.2 + rng.nextDouble() * 2.8,
          length: 35 + rng.nextDouble() * 55,
          curvature: (rng.nextDouble() - 0.5) * 14,
          alpha: 0.22 + rng.nextDouble() * 0.28,
        ));
      }
      for (var i = _windParticles.length - 1; i >= 0; i--) {
        final p = _windParticles[i];
        p.x += p.vx;
        if (p.x > 440) {
          _windParticles.removeAt(i);
        }
      }
    } else {
      _windParticles.clear();
    }
  }

  void _cycleBiome(int delta) {
    final values = SanctuaryBiome.values;
    final currentIndex = values.indexOf(_targetBiome);
    final nextIndex = (currentIndex + delta + values.length) % values.length;
    _setBiome(values[nextIndex]);
  }

  void _setBiome(SanctuaryBiome biome) {
    if (biome == _targetBiome && !_transitionController.isAnimating) return;
    setState(() {
      _currentBiome = _targetBiome;
      _targetBiome = biome;
    });
    _transitionController.forward(from: 0.0);
    widget.onBiomeChanged?.call(biome);
  }

  void _toggleSound(SoundscapeMode mode) {
    AmbientAudioService.instance.toggleSound(mode);
  }

  @override
  void dispose() {
    AmbientAudioService.instance.currentModeNotifier.removeListener(_onAudioModeChanged);
    _tickerController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _transitionCurve.value;

    return Container(
      height: 236,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0x4DFFB534),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x385A2D0A),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
          BoxShadow(
            color: Color(0x145A2D0A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // 1. Living Diorama Canvas Viewport (Tap left/right half to cycle biomes)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  final width = box?.size.width ?? 374;
                  if (details.localPosition.dx < width * 0.5) {
                    _cycleBiome(-1);
                  } else {
                    _cycleBiome(1);
                  }
                },
                child: CustomPaint(
                  painter: _SanctuaryDioramaPainter(
                    fromBiome: _currentBiome,
                    toBiome: _targetBiome,
                    progress: t,
                    animTime: _animTime,
                    soundMode: _currentSound,
                    cranes: _cranes,
                    embers: _embers,
                    windParticles: _windParticles,
                    splashes: _splashes,
                    ripples: _ripples,
                  ),
                ),
              ),
            ),

            // 2. Top Vignette Scrim (Guarantees Text Legibility)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 64,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8100C0A),
                      Color(0x59100C0A),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 3. Top Scene Metadata & Carousel Dots
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _targetBiome.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _targetBiome.sub,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xD9FFF5E6),
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Carousel Dots
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: SanctuaryBiome.values.map((b) {
                        final isActive = b == _targetBiome;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(left: 3),
                          width: isActive ? 12 : 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFFFFB534) : const Color(0x66FFFFFF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // 4. Floating Frosted Soundscape Shelf (Elevated 10px from bottom)
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              height: 44,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xB816120E),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x38FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildSoundChip(SoundscapeMode.rain),
                    const SizedBox(width: 4),
                    _buildSoundChip(SoundscapeMode.hearth),
                    const SizedBox(width: 4),
                    _buildSoundChip(SoundscapeMode.wind),
                    const SizedBox(width: 4),
                    _buildSoundChip(SoundscapeMode.solfeggio),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundChip(SoundscapeMode mode) {
    final isActive = _currentSound == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () => _toggleSound(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive ? const Color(0x66FFFFFF) : const Color(0x22FFFFFF),
            ),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x8CFF7F50),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: isActive ? Colors.white : const Color(0xFFFFF2DD),
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 3),
                _MicroEqualizer(animTime: _animTime),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Live 3-Bar Dancing Micro-Equalizer
class _MicroEqualizer extends StatelessWidget {
  const _MicroEqualizer({required this.animTime});
  final double animTime;

  @override
  Widget build(BuildContext context) {
    final h1 = 3.0 + (math.sin(animTime * 10) + 1.0) * 3.0;
    final h2 = 4.0 + (math.sin(animTime * 12 + 1.2) + 1.0) * 3.5;
    final h3 = 3.0 + (math.sin(animTime * 8 + 2.4) + 1.0) * 2.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(width: 2, height: h1, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 1.5),
        Container(width: 2, height: h2, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 1.5),
        Container(width: 2, height: h3, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
      ],
    );
  }
}

/// CustomPainter executing procedural landscape, 360° crepuscular rays, and natural physics
class _SanctuaryDioramaPainter extends CustomPainter {
  const _SanctuaryDioramaPainter({
    required this.fromBiome,
    required this.toBiome,
    required this.progress,
    required this.animTime,
    required this.soundMode,
    required this.cranes,
    required this.embers,
    required this.windParticles,
    required this.splashes,
    required this.ripples,
  });

  final SanctuaryBiome fromBiome;
  final SanctuaryBiome toBiome;
  final double progress;
  final double animTime;
  final SoundscapeMode soundMode;
  final List<_CraneEntity> cranes;
  final List<_EmberParticle> embers;
  final List<_WindParticle> windParticles;
  final List<_SplashParticle> splashes;
  final List<_RippleEffect> ripples;

  static Color _lerp(Color a, Color b, double t) {
    return Color.lerp(a, b, t) ?? a;
  }

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final width = size.width;
      final height = size.height;
      final t = progress;

      final fromConfig = _BiomeConfig.of(fromBiome);
      final toConfig = _BiomeConfig.of(toBiome);

      // 1. Sky Gradient Interpolation
      final skyTop = _lerp(fromConfig.skyTop, toConfig.skyTop, t);
      final skyMid = _lerp(fromConfig.skyMid, toConfig.skyMid, t);
      final skyBottom = _lerp(fromConfig.skyBottom, toConfig.skyBottom, t);

      final skyRect = Rect.fromLTWH(0, 0, width, height);
      final skyPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyMid, skyBottom],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(skyRect);
      canvas.drawRect(skyRect, skyPaint);

      // 2. Cosmic Aurora Ribbons (for Aurora biome)
      final auroraWeight = (fromConfig.hasAurora ? 1 - t : 0.0) + (toConfig.hasAurora ? t : 0.0);
      if (auroraWeight > 0.02) {
        final auroraPaint = Paint()..blendMode = BlendMode.screen;
        for (var a = 0; a < 3; a++) {
          final aY = height * (0.18 + a * 0.12);
          final path = Path()..moveTo(0, aY);
          for (var x = 0.0; x <= width; x += 8) {
            final wave = math.sin(x * 0.02 + animTime * 0.9 + a * 1.5) * 12 +
                math.cos(x * 0.01 - animTime * 0.5) * 8;
            path.lineTo(x, aY + wave);
          }
          path.lineTo(width, aY + 35);
          path.lineTo(0, aY + 35);
          path.close();

          auroraPaint.shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Color(0xFF64FFDA).withValues(alpha: 0.32 * auroraWeight),
              Color(0xFF9D4EDD).withValues(alpha: 0.22 * auroraWeight),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, aY - 25, width, 60));
          canvas.drawPath(path, auroraPaint);
        }
      }

      // 3. Starlight Depth Layer (Hearth & Aurora)
      final nightWeight = math.max(
        (toConfig.isNight ? t : 0.0),
        (fromConfig.isNight ? 1 - t : 0.0),
      );
      if (nightWeight > 0.02) {
        final starPaint = Paint();
        for (var i = 0; i < 48; i++) {
          final sx = (i * 43 + 17) % width;
          final sy = (i * 29 + 11) % (height * 0.52);
          final twinkle = math.sin(animTime * 2.5 + i * 1.3) * 0.5 + 0.5;
          starPaint.color = Colors.white.withValues(alpha: (0.4 + twinkle * 0.6) * nightWeight);
          canvas.drawCircle(Offset(sx, sy), 0.7 + (i % 3 == 0 ? 0.6 : 0.2), starPaint);
        }
      }

      // 4. Sun / Moon Celestial Body Interpolation
      final sunX = (fromConfig.sunX + (toConfig.sunX - fromConfig.sunX) * t) * width;
      final sunY = (fromConfig.sunY + (toConfig.sunY - fromConfig.sunY) * t) * height;
      final sunR = math.max(1.0, fromConfig.sunR + (toConfig.sunR - fromConfig.sunR) * t);
      final sunColor = _lerp(fromConfig.sunColor, toConfig.sunColor, t);
      final sunGlow = _lerp(fromConfig.sunGlow, toConfig.sunGlow, t);

      // Corona Glow
      final coronaPaint = Paint()
        ..shader = RadialGradient(
          colors: [sunGlow, sunGlow.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: sunR * 3.4));
      canvas.drawCircle(Offset(sunX, sunY), sunR * 3.4, coronaPaint);

      // 5. 360-Degree Radial Crepuscular Sun Rays
      // Smooth interpolation of ray intensity (faint/damped for Lavender Lake)
      final godRayAlpha = (fromConfig.rayIntensity * (1 - t)) + (toConfig.rayIntensity * t);
      if (godRayAlpha > 0.02) {
        final maxDist = math.max(width, height) * 0.95;
        final rayPaint = Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF1BD).withValues(alpha: 0.24 * godRayAlpha),
              const Color(0xFFFFB96E).withValues(alpha: 0.08 * godRayAlpha),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: maxDist));

        const rayCount = 20;
        const step = (math.pi * 2) / rayCount;
        for (var i = 0; i < rayCount; i++) {
          final baseAngle = i * step;
          final drift = baseAngle + math.sin(animTime * 0.25 + i * 1.7) * 0.035;
          final halfWidth = 0.045 + (i % 2 == 0 ? 0.02 : 0.005);

          final path = Path()..moveTo(sunX, sunY);
          path.arcTo(
            Rect.fromCircle(center: Offset(sunX, sunY), radius: maxDist),
            drift - halfWidth,
            halfWidth * 2,
            false,
          );
          path.close();
          canvas.drawPath(path, rayPaint);
        }
      }

      // Sun Sphere
      final sunPaint = Paint()..color = sunColor;
      canvas.drawCircle(Offset(sunX, sunY), sunR, sunPaint);

      // Moon Crescent Cutout (Smooth fade, zero pop-in)
      final moonWeight = (fromConfig.isMoon ? 1 - t : 0.0) + (toConfig.isMoon ? t : 0.0);
      if (moonWeight > 0.02) {
        final moonShadowPaint = Paint()..color = skyTop.withValues(alpha: moonWeight);
        canvas.drawCircle(
          Offset(sunX - sunR * 0.42, sunY - sunR * 0.22),
          math.max(1.0, sunR * 0.85),
          moonShadowPaint,
        );
      }

      // 6. SVG Soaring Cranes (Smooth cross-fade)
      final craneWeight = (fromConfig.hasCranes ? 1 - t : 0.0) + (toConfig.hasCranes ? t : 0.0);
      if (craneWeight > 0.02) {
        final cranePaint = Paint()
          ..color = const Color(0xFF3A2E20).withValues(alpha: 0.45 * craneWeight)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;

        for (final crane in cranes) {
          final wingFlap = math.sin(animTime * 4.5 + crane.phase) * 4 * crane.size;
          final cx = crane.x;
          final cy = crane.y;
          final s = crane.size;

          final path = Path()
            ..moveTo(cx - 8 * s, cy + wingFlap)
            ..quadraticBezierTo(cx - 3 * s, cy - 2 * s, cx, cy)
            ..quadraticBezierTo(cx + 3 * s, cy - 2 * s, cx + 8 * s, cy + wingFlap);
          canvas.drawPath(path, cranePaint);
        }
      }

      // 7. Procedural Stationary Landscape Layers (3 Layers)
      for (var layerIdx = 0; layerIdx < 3; layerIdx++) {
        final fromLayer = fromConfig.layers[layerIdx];
        final toLayer = toConfig.layers[layerIdx];

        final path = Path()..moveTo(0, height);
        for (var x = 0.0; x <= width; x += 6) {
          final yFrom = fromLayer.getY(x, width, height, layerIdx == 2);
          final yTo = toLayer.getY(x, width, height, layerIdx == 2);
          var y = yFrom + (yTo - yFrom) * t;

          if ((fromLayer.isWater || toLayer.isWater) && layerIdx == 2) {
            final waterFactor = toLayer.isWater ? t : (1 - t);
            y += math.sin(x * 0.045 - animTime * 1.4) * (2.2 * waterFactor);
          }
          path.lineTo(x, y);
        }
        path.lineTo(width, height);
        path.close();

        // Atmospheric Depth Gradient
        final baseColor = _lerp(fromLayer.color, toLayer.color, t);
        final layerPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [baseColor, _lerp(baseColor, const Color(0xFF0C0A08), 0.6)],
          ).createShader(Rect.fromLTWH(0, height * 0.4, width, height * 0.6));
        canvas.drawPath(path, layerPaint);

        // Snow-Capped Peaks (Alpine Frost)
        final snowWeight = (fromLayer.isSnowPeak ? 1 - t : 0.0) + (toLayer.isSnowPeak ? t : 0.0);
        if (snowWeight > 0.02 && layerIdx == 0) {
          final snowPath = Path();
          for (var x = 0.0; x <= width; x += 6) {
            final yFrom = fromLayer.getY(x, width, height, false);
            final yTo = toLayer.getY(x, width, height, false);
            final y = yFrom + (yTo - yFrom) * t;
            if (x == 0) {
              snowPath.moveTo(x, y);
            } else {
              snowPath.lineTo(x, y);
            }
          }
          snowPath.lineTo(width, height * 0.56);
          snowPath.lineTo(0, height * 0.56);
          snowPath.close();

          final snowPaint = Paint()..color = const Color(0xFFF0F8FF).withValues(alpha: 0.82 * snowWeight);
          canvas.drawPath(snowPath, snowPaint);
        }

        // Two-Tone Dune Shading (Dunes)
        final duneWeight = (fromLayer.isDune ? 1 - t : 0.0) + (toLayer.isDune ? t : 0.0);
        if (duneWeight > 0.02) {
          final rimPaint = Paint()
            ..color = const Color(0xFFFFE3A8).withValues(alpha: 0.35 * duneWeight)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          final rimPath = Path();
          for (var x = 0.0; x <= width; x += 6) {
            final yFrom = fromLayer.getY(x, width, height, layerIdx == 2);
            final yTo = toLayer.getY(x, width, height, layerIdx == 2);
            final y = yFrom + (yTo - yFrom) * t;
            if (x == 0) {
              rimPath.moveTo(x, y);
            } else {
              rimPath.lineTo(x, y);
            }
          }
          canvas.drawPath(rimPath, rimPaint);
        }

        // Specular Water Reflection (Lake)
        final waterWeight = (fromLayer.isWater ? 1 - t : 0.0) + (toLayer.isWater ? t : 0.0);
        if (waterWeight > 0.02 && layerIdx == 2) {
          final refPaint = Paint()..color = const Color(0xFFFFE6F2).withValues(alpha: 0.28 * waterWeight);
          for (var r = 0; r < 7; r++) {
            final rx = sunX + math.sin(animTime * 1.2 + r) * 14;
            final ry = height * 0.78 + r * 7;
            final w = 24.0 + r * 10 + math.sin(animTime * 2 + r) * 6;
            canvas.drawRect(Rect.fromCenter(center: Offset(rx, ry), width: w, height: 1.8), refPaint);
          }
        }

        // Valley Fog Sheet (Between mid and foreground layer)
        final mistWeight = (fromConfig.hasMist ? 1 - t : 0.0) + (toConfig.hasMist ? t : 0.0);
        if (layerIdx == 1 && mistWeight > 0.02) {
          final mistY = height * 0.63;
          final mistPath = Path()..moveTo(0, mistY);
          for (var x = 0.0; x <= width; x += 10) {
            final wave = math.sin(x * 0.016 + animTime * 0.45) * 5;
            mistPath.lineTo(x, mistY + wave);
          }
          mistPath.lineTo(width, mistY + 18);
          mistPath.lineTo(0, mistY + 18);
          mistPath.close();

          final mistPaint = Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0xFFFFF6E6).withValues(alpha: (0.14 * mistWeight + math.sin(animTime * 0.8) * 0.03).clamp(0.0, 1.0)),
                Colors.transparent,
              ],
            ).createShader(Rect.fromLTWH(0, mistY - 14, width, 32));
          canvas.drawPath(mistPath, mistPaint);
        }

        // Pine Tree Silhouettes (Hearth / Pines - Layer 1 Only, disappears FIRST before mountain moves)
        if (layerIdx == 1 && (fromLayer.hasPineTrees || toLayer.hasPineTrees)) {
          double pineAlpha;
          double Function(double x) getTreeY;

          if (fromLayer.hasPineTrees && !toLayer.hasPineTrees) {
            // Disappear FIRST before mountain moves!
            pineAlpha = (1.0 - (t / 0.25)).clamp(0.0, 1.0);
            getTreeY = (x) => fromLayer.getY(x, width, height, false);
          } else if (!fromLayer.hasPineTrees && toLayer.hasPineTrees) {
            // Appear LAST after new mountain has formed!
            pineAlpha = ((t - 0.70) / 0.30).clamp(0.0, 1.0);
            getTreeY = (x) => toLayer.getY(x, width, height, false);
          } else {
            // Both biomes have pine trees
            pineAlpha = 1.0;
            getTreeY = (x) {
              final yFrom = fromLayer.getY(x, width, height, false);
              final yTo = toLayer.getY(x, width, height, false);
              return yFrom + (yTo - yFrom) * t;
            };
          }

          if (pineAlpha > 0.01) {
            final treePaint = Paint()
              ..color = const Color(0xFF0F1412).withValues(alpha: 0.94 * pineAlpha)
              ..style = PaintingStyle.fill;

            for (var treeX = 14.0; treeX < width; treeX += 24) {
              final treeBaseY = getTreeY(treeX);
              final treeH = 14.0 + (treeX % 5) * 2.6;
              _drawPineTree(canvas, treeX, treeBaseY, treeH, treePaint);
            }
          }
        }

        // Foreground Campfire with Wood Logs (Hearth Scene)
        final fireWeight = (fromLayer.hasCampfire ? 1 - t : 0.0) + (toLayer.hasCampfire ? t : 0.0);
        if (fireWeight > 0.02 && layerIdx == 2) {
          final fireX = width * 0.26;
          final fireY = height * 0.86;

          // Wood logs
          final logPaint = Paint()..color = const Color(0xFF2E190E).withValues(alpha: fireWeight);
          canvas.drawOval(Rect.fromCenter(center: Offset(fireX, fireY + 4), width: 24, height: 6), logPaint);

          // Fire radial warm glow
          final pulse = math.sin(animTime * 10) * 4;
          final fireR = math.max(1.0, 36.0 + pulse);
          final fireGlowPaint = Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFFFA52D).withValues(alpha: 0.8 * fireWeight),
                const Color(0xFFFF5A19).withValues(alpha: 0.35 * fireWeight),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(Rect.fromCircle(center: Offset(fireX, fireY), radius: fireR));
          canvas.drawCircle(Offset(fireX, fireY), fireR, fireGlowPaint);

          // Molten flame core
          final corePaint = Paint()..color = const Color(0xFFFFE680).withValues(alpha: fireWeight);
          canvas.drawCircle(Offset(fireX, fireY), math.max(1.0, 5.0 + math.sin(animTime * 14) * 1.5), corePaint);
        }

        // Foreground Grassy Knolls with Dynamic Swaying Grass (Meadow / Pines / Sakura)
        final grassWeight = (fromLayer.isGrass ? 1 - t : 0.0) + (toLayer.isGrass ? t : 0.0);
        if (grassWeight > 0.02 && layerIdx == 2) {
          final grassPaint = Paint()
            ..color = const Color(0xFFB4D26E).withValues(alpha: 0.85 * grassWeight)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;

          final windBoost = soundMode == SoundscapeMode.wind ? 2.4 : 1.0;
          for (var i = 0; i < 45; i++) {
            final gx = (i / 45) * width + ((i % 5) - 2) * 3;
            final baseY = toLayer.getY(gx, width, height, true);
            final sway = math.sin(animTime * 3.2 * windBoost + gx * 0.03) * 6;
            final gPath = Path()
              ..moveTo(gx, baseY)
              ..quadraticBezierTo(gx + sway * 0.5, baseY - 8, gx + sway, baseY - 14);
            canvas.drawPath(gPath, grassPaint);
          }
        }
      }

      // 8. Soundscape & Weather Particles
      // A. Rain with Ridge Collision & Water Surface Ripples
      if (soundMode == SoundscapeMode.rain) {
        final rainPaint = Paint()
          ..color = const Color(0xFFD7EBFF).withValues(alpha: 0.45)
          ..strokeWidth = 1.1;

        final foregroundLayer = toConfig.layers[2];
        for (var i = 0; i < 35; i++) {
          final rx = (i * 37 + (animTime * 180).toInt()) % (width.toInt() + 60) - 20.0;
          final ry = ((i * 53 + (animTime * 320).toInt()) % (height.toInt() + 40)) - 10.0;
          final terrainY = foregroundLayer.getY(rx, width, height, true);

          if (ry < terrainY) {
            canvas.drawLine(Offset(rx, ry), Offset(rx - 3, ry + 14), rainPaint);
          }
        }

        // Draw Splashes
        final splashPaint = Paint()..color = const Color(0xFFDCF0FF).withValues(alpha: 0.6);
        for (final sp in splashes) {
          canvas.drawCircle(Offset(sp.x, sp.y), math.max(0.1, sp.r), splashPaint);
        }

        // Draw Ripples on water
        final ripPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
        for (final rip in ripples) {
          ripPaint.color = const Color(0xFFE6D7F5).withValues(alpha: math.max(0.0, rip.alpha));
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(rip.x, rip.y),
              width: math.max(0.1, rip.radius * 4.8),
              height: math.max(0.1, rip.radius * 1.4),
            ),
            ripPaint,
          );
        }
      }

      // B. Warm Hearth Embers with Strictly Clamped Radius
      if (soundMode == SoundscapeMode.hearth) {
        for (final p in embers) {
          Color emberColor;
          if (p.life > 0.7) {
            emberColor = const Color(0xFFFFF5C2);
          } else if (p.life > 0.35) {
            emberColor = const Color(0xFFFFB534);
          } else {
            emberColor = const Color(0xFFFF5233);
          }

          final safeRadius = math.max(0.1, p.r * math.max(0.0, p.life));
          final emberPaint = Paint()..color = emberColor.withValues(alpha: math.max(0.0, p.life * 0.85));
          canvas.drawCircle(Offset(p.x, p.y), safeRadius, emberPaint);
        }
      }

      // C. Wind Streamlines
      if (soundMode == SoundscapeMode.wind) {
        final windPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;

        for (final p in windParticles) {
          windPaint.color = Colors.white.withValues(alpha: p.alpha);
          final wPath = Path()
            ..moveTo(p.x, p.y)
            ..quadraticBezierTo(p.x + p.length * 0.5, p.y + p.curvature, p.x + p.length, p.y);
          canvas.drawPath(wPath, windPaint);
        }
      }

      // D. 432Hz Stillness: Gaussian Standing Resonance Waves
      if (soundMode == SoundscapeMode.solfeggio) {
        final wavePaint = Paint()..blendMode = BlendMode.screen;
        for (var ring = 0; ring < 3; ring++) {
          final prog = ((animTime * 0.2 + ring / 3) % 1.0);
          final rad = prog * (width * 0.65);
          final alpha = math.sin(prog * math.pi) * 0.32;

          wavePaint.shader = RadialGradient(
            colors: [
              Colors.transparent,
              Color(0xFFFFE6A0).withValues(alpha: alpha),
              Colors.transparent,
            ],
            stops: const [0.75, 0.9, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: rad + 15));

          canvas.drawCircle(Offset(sunX, sunY), rad + 15, wavePaint);
        }
      }

    } catch (e) {
      // Defensive guard ensures animation never permanently terminates
      debugPrint('Sanctuary diorama paint error handled: $e');
    }
  }

  void _drawPineTree(Canvas canvas, double x, double baseY, double treeH, Paint paint) {
    final trunkW = math.max(1.0, treeH * 0.12);
    final trunkH = treeH * 0.22;
    // Trunk
    canvas.drawRect(Rect.fromLTWH(x - trunkW / 2, baseY - trunkH, trunkW, trunkH), paint);

    // 3 tiered conifer boughs
    for (var tier = 0; tier < 3; tier++) {
      final tierBaseY = baseY - trunkH * 0.4 - (tier * (treeH * 0.26));
      final tierTopY = tierBaseY - (treeH * 0.38);
      final tierW = (treeH * 0.52) * (1.0 - tier * 0.22);
      final p = Path()
        ..moveTo(x, tierTopY)
        ..lineTo(x - tierW / 2, tierBaseY)
        ..lineTo(x + tierW / 2, tierBaseY)
        ..close();
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SanctuaryDioramaPainter oldDelegate) => true;
}

// --- Data Structures for Biomes, Layers, and Particles ---

class _LayerConfig {
  const _LayerConfig({
    required this.base,
    required this.amp1,
    required this.freq1,
    required this.phase1,
    required this.color,
    this.amp2 = 0,
    this.freq2 = 0,
    this.phase2 = 0,
    this.isDune = false,
    this.isAlpine = false,
    this.isWater = false,
    this.isGrass = false,
    this.isSnowPeak = false,
    this.hasPineTrees = false,
    this.hasCampfire = false,
  });

  final double base;
  final double amp1;
  final double freq1;
  final double phase1;
  final double amp2;
  final double freq2;
  final double phase2;
  final Color color;
  final bool isDune;
  final bool isAlpine;
  final bool isWater;
  final bool isGrass;
  final bool isSnowPeak;
  final bool hasPineTrees;
  final bool hasCampfire;

  double getY(double x, double width, double height, bool isForeground) {
    final nx = x / width;
    final h1 = math.sin(nx * freq1 * math.pi * 2 + phase1) * amp1;
    final h2 = math.sin(nx * freq2 * math.pi * 2 + phase2) * amp2;
    var combined = h1 + h2;

    if (isDune) {
      combined = combined.sign * math.pow(combined.abs(), 0.86);
    } else if (isAlpine) {
      final fold = (math.sin(nx * 4.5 * math.pi + phase1)).abs() * 14;
      combined = combined * 0.7 - fold;
    }
    return height * base + combined;
  }
}

class _BiomeConfig {
  const _BiomeConfig({
    required this.skyTop,
    required this.skyMid,
    required this.skyBottom,
    required this.sunX,
    required this.sunY,
    required this.sunR,
    required this.sunColor,
    required this.sunGlow,
    required this.rayIntensity,
    required this.isMoon,
    required this.isNight,
    required this.hasGodRays,
    required this.hasCranes,
    required this.hasMist,
    required this.hasAurora,
    required this.layers,
  });

  final Color skyTop;
  final Color skyMid;
  final Color skyBottom;
  final double sunX;
  final double sunY;
  final double sunR;
  final Color sunColor;
  final Color sunGlow;
  final double rayIntensity;
  final bool isMoon;
  final bool isNight;
  final bool hasGodRays;
  final bool hasCranes;
  final bool hasMist;
  final bool hasAurora;
  final List<_LayerConfig> layers;

  static _BiomeConfig of(SanctuaryBiome b) {
    switch (b) {
      case SanctuaryBiome.dunes:
        return const _BiomeConfig(
          skyTop: Color(0xFFFFE5B4),
          skyMid: Color(0xFFFF9E64),
          skyBottom: Color(0xFFE86640),
          sunX: 0.78,
          sunY: 0.30,
          sunR: 26,
          sunColor: Color(0xFFFFF8E7),
          sunGlow: Color(0x73FFC86E),
          rayIntensity: 1.0,
          isMoon: false,
          isNight: false,
          hasGodRays: true,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.54, amp1: 14, freq1: 1.2, phase1: 0.2, amp2: 6, freq2: 2.8, phase2: 1.5, color: Color(0xFFD47A46), isDune: true),
            _LayerConfig(base: 0.68, amp1: 20, freq1: 1.8, phase1: 2.1, amp2: 8, freq2: 3.4, phase2: 0.7, color: Color(0xFFBA5328), isDune: true),
            _LayerConfig(base: 0.82, amp1: 22, freq1: 1.4, phase1: 4.0, amp2: 10, freq2: 3.0, phase2: 2.2, color: Color(0xFF7A2C10), isDune: true),
          ],
        );
      case SanctuaryBiome.lake:
        return const _BiomeConfig(
          skyTop: Color(0xFFD6B4E6),
          skyMid: Color(0xFF9F7596),
          skyBottom: Color(0xFF523C59),
          sunX: 0.32,
          sunY: 0.34,
          sunR: 20,
          sunColor: Color(0xFFFFE6F2),
          sunGlow: Color(0x66D8B4E6),
          rayIntensity: 0.12, // Damped rays as sun sits low behind alpine mountains
          isMoon: false,
          isNight: false,
          hasGodRays: false,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.46, amp1: 28, freq1: 2.0, phase1: 0.5, amp2: 16, freq2: 4.8, phase2: 2.0, color: Color(0xFF3E2A4A), isAlpine: true),
            _LayerConfig(base: 0.62, amp1: 18, freq1: 1.5, phase1: 3.2, amp2: 10, freq2: 3.5, phase2: 1.1, color: Color(0xFF2C1B36), isAlpine: true),
            _LayerConfig(base: 0.76, amp1: 4, freq1: 0.8, phase1: 0.0, amp2: 2, freq2: 2.2, phase2: 0.5, color: Color(0xFF180E21), isWater: true),
          ],
        );
      case SanctuaryBiome.meadow:
        return const _BiomeConfig(
          skyTop: Color(0xFFFFF8E0),
          skyMid: Color(0xFFFFE199),
          skyBottom: Color(0xFFE8CB72),
          sunX: 0.50,
          sunY: 0.25,
          sunR: 28,
          sunColor: Color(0xFFFFFFF2),
          sunGlow: Color(0x8CFFE68C),
          rayIntensity: 0.95,
          isMoon: false,
          isNight: false,
          hasGodRays: true,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.50, amp1: 15, freq1: 1.1, phase1: 0.8, amp2: 7, freq2: 2.3, phase2: 1.8, color: Color(0xFF9BB56E)),
            _LayerConfig(base: 0.66, amp1: 18, freq1: 1.6, phase1: 2.5, amp2: 9, freq2: 3.1, phase2: 0.3, color: Color(0xFF708E3D)),
            _LayerConfig(base: 0.80, amp1: 16, freq1: 1.3, phase1: 4.5, amp2: 8, freq2: 2.6, phase2: 3.2, color: Color(0xFF445E1E), isGrass: true),
          ],
        );
      case SanctuaryBiome.hearth:
        return const _BiomeConfig(
          skyTop: Color(0xFF0D0B17),
          skyMid: Color(0xFF181329),
          skyBottom: Color(0xFF281B34),
          sunX: 0.82,
          sunY: 0.22,
          sunR: 15,
          sunColor: Color(0xFFFFF1D6),
          sunGlow: Color(0x4DFFECCC),
          rayIntensity: 0.0,
          isMoon: true,
          isNight: true,
          hasGodRays: false,
          hasCranes: false,
          hasMist: false,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.50, amp1: 22, freq1: 1.4, phase1: 1.1, amp2: 10, freq2: 3.0, phase2: 2.4, color: Color(0xFF1B152B), isAlpine: true),
            _LayerConfig(base: 0.66, amp1: 16, freq1: 1.8, phase1: 3.0, amp2: 8, freq2: 3.6, phase2: 1.2, color: Color(0xFF120D1F), hasPineTrees: true),
            _LayerConfig(base: 0.82, amp1: 12, freq1: 1.2, phase1: 4.8, amp2: 6, freq2: 2.4, phase2: 0.6, color: Color(0xFF090610), hasCampfire: true),
          ],
        );
      case SanctuaryBiome.pines:
        return const _BiomeConfig(
          skyTop: Color(0xFFD8ECE1),
          skyMid: Color(0xFF98BFA8),
          skyBottom: Color(0xFF486E5D),
          sunX: 0.40,
          sunY: 0.28,
          sunR: 24,
          sunColor: Color(0xFFFFFDF0),
          sunGlow: Color(0x73D8ECE1),
          rayIntensity: 0.75,
          isMoon: false,
          isNight: false,
          hasGodRays: true,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.48, amp1: 20, freq1: 1.3, phase1: 0.9, amp2: 8, freq2: 2.7, phase2: 1.4, color: Color(0xFF2F4F3E)),
            _LayerConfig(base: 0.64, amp1: 16, freq1: 1.7, phase1: 2.4, amp2: 7, freq2: 3.2, phase2: 0.8, color: Color(0xFF223C2F), hasPineTrees: true),
            _LayerConfig(base: 0.80, amp1: 14, freq1: 1.2, phase1: 4.2, amp2: 6, freq2: 2.2, phase2: 2.8, color: Color(0xFF15281E), isGrass: true),
          ],
        );
      case SanctuaryBiome.frost:
        return const _BiomeConfig(
          skyTop: Color(0xFFE6F4FA),
          skyMid: Color(0xFFA9D1E6),
          skyBottom: Color(0xFF6A9CB5),
          sunX: 0.68,
          sunY: 0.26,
          sunR: 22,
          sunColor: Colors.white,
          sunGlow: Color(0x80E6F4FA),
          rayIntensity: 0.85,
          isMoon: false,
          isNight: false,
          hasGodRays: true,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.44, amp1: 30, freq1: 2.1, phase1: 0.3, amp2: 14, freq2: 4.2, phase2: 1.9, color: Color(0xFF4B6B7C), isAlpine: true, isSnowPeak: true),
            _LayerConfig(base: 0.62, amp1: 20, freq1: 1.5, phase1: 2.8, amp2: 10, freq2: 3.1, phase2: 0.5, color: Color(0xFF2F4856), isAlpine: true),
            _LayerConfig(base: 0.78, amp1: 12, freq1: 1.1, phase1: 4.6, amp2: 5, freq2: 2.5, phase2: 3.1, color: Color(0xFF1A2C37)),
          ],
        );
      case SanctuaryBiome.sakura:
        return const _BiomeConfig(
          skyTop: Color(0xFFFFEBF1),
          skyMid: Color(0xFFFFCAD4),
          skyBottom: Color(0xFFD896A8),
          sunX: 0.35,
          sunY: 0.32,
          sunR: 22,
          sunColor: Color(0xFFFFF5F8),
          sunGlow: Color(0x73FFCAD4),
          rayIntensity: 0.70,
          isMoon: false,
          isNight: false,
          hasGodRays: true,
          hasCranes: true,
          hasMist: true,
          hasAurora: false,
          layers: [
            _LayerConfig(base: 0.48, amp1: 18, freq1: 1.2, phase1: 0.6, amp2: 8, freq2: 2.6, phase2: 1.7, color: Color(0xFF684551)),
            _LayerConfig(base: 0.65, amp1: 16, freq1: 1.5, phase1: 2.7, amp2: 7, freq2: 3.0, phase2: 0.9, color: Color(0xFF4C2D38)),
            _LayerConfig(base: 0.81, amp1: 14, freq1: 1.3, phase1: 4.1, amp2: 6, freq2: 2.4, phase2: 3.3, color: Color(0xFF2E1720), isGrass: true),
          ],
        );
      case SanctuaryBiome.aurora:
        return const _BiomeConfig(
          skyTop: Color(0xFF080514),
          skyMid: Color(0xFF12102B),
          skyBottom: Color(0xFF1B263B),
          sunX: 0.75,
          sunY: 0.20,
          sunR: 12,
          sunColor: Color(0xFFE8F5E9),
          sunGlow: Color(0x5964FFDA),
          rayIntensity: 0.0,
          isMoon: true,
          isNight: true,
          hasGodRays: false,
          hasCranes: false,
          hasMist: false,
          hasAurora: true,
          layers: [
            _LayerConfig(base: 0.48, amp1: 24, freq1: 1.6, phase1: 0.7, amp2: 11, freq2: 3.4, phase2: 2.1, color: Color(0xFF0C1322), isAlpine: true),
            _LayerConfig(base: 0.65, amp1: 17, freq1: 1.4, phase1: 3.1, amp2: 8, freq2: 2.9, phase2: 1.0, color: Color(0xFF070D19), isAlpine: true),
            _LayerConfig(base: 0.82, amp1: 12, freq1: 1.1, phase1: 4.9, amp2: 5, freq2: 2.1, phase2: 0.4, color: Color(0xFF04070E)),
          ],
        );
    }
  }
}

class _CraneEntity {
  _CraneEntity({
    required this.x,
    required this.y,
    required this.vx,
    required this.size,
    required this.phase,
  });

  double x;
  double y;
  final double vx;
  final double size;
  final double phase;
}

class _EmberParticle {
  _EmberParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.life,
    required this.eddyPhase,
  });

  double x;
  double y;
  double vx;
  double vy;
  double r;
  double life;
  double eddyPhase;
}

class _WindParticle {
  _WindParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.length,
    required this.curvature,
    required this.alpha,
  });

  double x;
  double y;
  double vx;
  double length;
  double curvature;
  double alpha;
}

class _SplashParticle {
  _SplashParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.alpha,
  });

  double x;
  double y;
  double vx;
  double vy;
  double r;
  double alpha;
}

class _RippleEffect {
  _RippleEffect({
    required this.x,
    required this.y,
    required this.radius,
    required this.maxRadius,
    required this.alpha,
  });

  double x;
  double y;
  double radius;
  double maxRadius;
  double alpha;
}
