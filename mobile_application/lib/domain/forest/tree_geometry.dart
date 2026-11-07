import 'dart:math' as math;

/// A deterministic random-number generator (mulberry32), the same one the forest prototype used, so a tree's shape is
/// the same everywhere and only how much of it is shown changes as it grows.
double Function() mulberry32(int seed) {
  const mask = 0xFFFFFFFF;
  var a = seed & mask;
  int imul(int x, int y) => ((x & mask) * (y & mask)) & mask;
  return () {
    a = (a + 0x6D2B79F5) & mask;
    var t = a;
    t = imul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & mask)) & mask;
    return ((t ^ (t >> 14)) & mask) / 4294967296;
  };
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double lerp(double a, double b, double t) => a + (b - a) * t;
double smooth(double a, double b, double v) {
  final t = clamp01((v - a) / (b - a));
  return t * t * (3 - 2 * t);
}

/// What makes one kind of tree different from another: its proportions, branching rule, bark and leaf colours.
class TreeSpecies {
  const TreeSpecies({
    required this.key,
    required this.name,
    required this.form,
    required this.height,
    required this.width,
    required this.bark,
    required this.barkHi,
    required this.barkLo,
    required this.barkStyle,
    required this.leaf,
    required this.leafEnd,
    required this.touch,
    this.depth = 0,
    this.trunkFrac = 0,
    this.trunkW = 0,
    this.spread = 0,
    this.jitter = 0,
    this.decay = 0,
    this.up = 0,
    this.clumpR = 0,
    this.side = 0,
    this.leaderDecay = 0,
    this.tiers = 0,
  });

  final String key;
  final String name;

  /// 'broad', 'leader', 'willow' or 'conifer'.
  final String form;
  final double height, width;
  final int depth;
  final double trunkFrac, trunkW, spread, jitter, decay, up, clumpR, leaderDecay;
  final int side, tiers;
  final String bark, barkHi, barkLo, barkStyle;
  final List<String> leaf, leafEnd;

  /// The species' finishing touch at the last stage: 'acorns', 'catkins', 'blossom', 'cones', 'fronds', 'autumn', 'fruit'.
  final String touch;
}

const treeSpecies = <TreeSpecies>[
  TreeSpecies(key: 'oak', name: 'Oak', form: 'broad', height: 232, width: 272, depth: 5, trunkFrac: 0.33, trunkW: 25, spread: 0.62, jitter: 0.3, decay: 0.76, up: 0.2, clumpR: 30,
      bark: '#5f4532', barkHi: '#8a6a4c', barkLo: '#3c2a1d', barkStyle: 'furrow', leaf: ['#33612d', '#4f8a3a', '#86b955'], leafEnd: ['#2f5a29', '#4a8436', '#93c25e'], touch: 'acorns'),
  TreeSpecies(key: 'birch', name: 'Birch', form: 'leader', height: 258, width: 160, depth: 5, trunkFrac: 0.3, trunkW: 13, spread: 0.75, jitter: 0.25, decay: 0.55, leaderDecay: 0.84, up: 0.35, clumpR: 15, side: 2,
      bark: '#e4ddd0', barkHi: '#fbf8f1', barkLo: '#a99f8f', barkStyle: 'birch', leaf: ['#64903a', '#8cb84b', '#c2de7c'], leafEnd: ['#6b9638', '#98c252', '#d6ea8e'], touch: 'catkins'),
  TreeSpecies(key: 'cherry', name: 'Cherry blossom', form: 'broad', height: 205, width: 278, depth: 5, trunkFrac: 0.3, trunkW: 19, spread: 0.78, jitter: 0.32, decay: 0.75, up: 0.0, clumpR: 24,
      bark: '#5a3934', barkHi: '#7f5650', barkLo: '#3a2320', barkStyle: 'bands', leaf: ['#557f41', '#78a454', '#a6c97a'], leafEnd: ['#cf7f99', '#eeaac0', '#fde0e9'], touch: 'blossom'),
  TreeSpecies(key: 'pine', name: 'Pine', form: 'conifer', height: 272, width: 150, tiers: 8, trunkW: 15,
      bark: '#5a3f2e', barkHi: '#7c5a42', barkLo: '#3a281c', barkStyle: 'furrow', leaf: ['#1d4433', '#2c5f44', '#4c8660'], leafEnd: ['#1b4231', '#2b5e43', '#5a956a'], touch: 'cones'),
  TreeSpecies(key: 'willow', name: 'Willow', form: 'willow', height: 214, width: 286, depth: 4, trunkFrac: 0.38, trunkW: 23, spread: 0.72, jitter: 0.3, decay: 0.72, up: 0.32, clumpR: 19,
      bark: '#5d4f39', barkHi: '#857257', barkLo: '#3b3123', barkStyle: 'furrow', leaf: ['#577f35', '#7ea548', '#b0cf6c'], leafEnd: ['#628b38', '#91b54f', '#cfe286'], touch: 'fronds'),
  TreeSpecies(key: 'maple', name: 'Maple', form: 'broad', height: 226, width: 238, depth: 5, trunkFrac: 0.36, trunkW: 20, spread: 0.55, jitter: 0.28, decay: 0.75, up: 0.3, clumpR: 27,
      bark: '#5a4636', barkHi: '#7d6450', barkLo: '#3a2c22', barkStyle: 'furrow', leaf: ['#456f33', '#659b43', '#97c25f'], leafEnd: ['#8a3322', '#c4612f', '#ecb45a'], touch: 'autumn'),
  TreeSpecies(key: 'apple', name: 'Apple', form: 'broad', height: 182, width: 236, depth: 4, trunkFrac: 0.34, trunkW: 19, spread: 0.85, jitter: 0.35, decay: 0.78, up: 0.08, clumpR: 31,
      bark: '#664834', barkHi: '#8b6a4f', barkLo: '#402d20', barkStyle: 'furrow', leaf: ['#3f7032', '#5e9a44', '#94c566'], leafEnd: ['#3d6d30', '#5b9742', '#9acb6a'], touch: 'fruit'),
];

/// A tapered limb drawn as a curve from (x0,y0) to (x1,y1) bending through (cx,cy); revealed between t0 and t1.
class TreeSeg {
  TreeSeg(this.x0, this.y0, this.cx, this.cy, this.x1, this.y1, this.w0, this.w1, this.d, this.t0, this.t1);
  double x0, y0, cx, cy, x1, y1, w0, w1, t0, t1;
  final int d;
}

class TreeBlob {
  TreeBlob(this.dx, this.dy, this.r);
  double dx, dy, r;
}

class TreeClump {
  TreeClump(this.x, this.y, this.r, this.t, this.blobs);
  double x, y, r, t;
  final List<TreeBlob> blobs;
}

class TreeTier {
  TreeTier(this.y, this.w, this.h, this.t, this.lean);
  double y, w, h, t;
  final double lean;
}

class TreeStrand {
  TreeStrand(this.x, this.y, this.len, this.dx, this.t);
  double x, y, len, t;
  final double dx;
}

class TreeBark {
  TreeBark(this.s, this.u, this.v0, this.v1);
  final int s;
  final double u, v0, v1;
}

class TreeRoot {
  TreeRoot(this.side, this.len, this.w);
  final int side;
  final double len, w;
}

class TreeTouch {
  TreeTouch(this.x, this.y, this.r, this.t, this.kind);
  final double x, y, r, t;
  final String kind;
}

/// One tree's whole shape, in local units with the trunk's base at (0,0) and up as negative y.
class TreeGeometry {
  final segs = <TreeSeg>[];
  final clumps = <TreeClump>[];
  final tiers = <TreeTier>[];
  final strands = <TreeStrand>[];
  final bark = <TreeBark>[];
  final roots = <TreeRoot>[];
  final touches = <TreeTouch>[];
  double height = 0, halfW = 0, crownTop = 0, crownBot = 1;
}

/// The same seed always gives the same tree.
TreeGeometry generateTree(int seed, TreeSpecies sp) {
  final r = mulberry32(seed);
  final g = TreeGeometry();
  if (sp.form == 'conifer') {
    _genConifer(r, sp, g);
  } else {
    _genBranching(r, sp, g);
  }
  // The loop bound is re-drawn on every pass, exactly as the prototype did, so the sequence stays identical.
  for (var i = 0; i < 2 + (r() * 2).floor(); i++) {
    g.roots.add(TreeRoot(i % 2 == 1 ? -1 : 1, 0.9 + r() * 0.8, 0.35 + r() * 0.25));
  }
  _normalise(g, sp);
  _addTouches(r, sp, g);
  return g;
}

TreeClump _makeClump(double Function() r, double x, double y, double radius, double t) {
  final blobs = <TreeBlob>[];
  final n = 4 + (r() * 3).floor();
  for (var i = 0; i < n; i++) {
    final a = (i / n) * math.pi * 2 + r() * 0.8;
    final d = i == 0 ? 0.0 : radius * (0.35 + r() * 0.3);
    final dx = math.cos(a) * d;
    final dy = math.sin(a) * d * 0.75 - radius * 0.05;
    final rr = radius * (i == 0 ? 0.62 : 0.4 + r() * 0.25);
    blobs.add(TreeBlob(dx, dy, rr));
  }
  return TreeClump(x, y, radius, t, blobs);
}

class _Kid {
  _Kid(this.a, this.len, this.w, this.leader, this.delay);
  final double a, len, w, delay;
  final bool leader;
}

void _genBranching(double Function() r, TreeSpecies sp, TreeGeometry g) {
  final maxD = sp.depth;
  void grow(double x, double y, double a, double len, double w, int d, double t0, bool leader) {
    final x1 = x + math.sin(a) * len, y1 = y - math.cos(a) * len;
    final bend = (r() - 0.5) * len * 0.22;
    final cx = (x + x1) / 2 + math.cos(a) * bend, cy = (y + y1) / 2 + math.sin(a) * bend;
    final t1 = t0 + 1;
    final w1 = w * (d == maxD ? 0.4 : 0.7);
    g.segs.add(TreeSeg(x, y, cx, cy, x1, y1, w, w1, d, t0, t1));
    final si = g.segs.length - 1;
    if (d <= 1 && w > 7) {
      for (var k = 0; k < (d == 0 ? 7 : 3); k++) {
        final v0 = r() * 0.8;
        final u = (r() - 0.5) * 0.7;
        final v1 = math.min(1.0, v0 + 0.12 + r() * 0.3);
        g.bark.add(TreeBark(si, u, v0, v1));
      }
    }
    if (d >= 1) {
      final radius = sp.clumpR * (d == 1 ? 0.62 : 0.72 + 0.28 * d / maxD) * (0.82 + r() * 0.36);
      g.clumps.add(_makeClump(r, x1 + math.sin(a) * radius * 0.25, y1 - math.cos(a) * radius * 0.25, radius, t1 - 0.25));
      if (d >= 2 && r() < 0.5) {
        const m = 0.55;
        final flip = r() < 0.5 ? -1.0 : 1.0;
        g.clumps.add(_makeClump(r, lerp(x, x1, m) + math.cos(a) * radius * 0.4 * flip, lerp(y, y1, m), radius * 0.75, t0 + 0.6));
      }
    }
    if (sp.form == 'willow' && d >= maxD - 1) {
      final n = d == maxD ? 3 : 2;
      for (var k = 0; k < n; k++) {
        final sx = x1 + (r() - 0.5) * 10;
        final sy = y1 + (r() - 0.5) * 6;
        final len2 = 0.55 + r() * 0.45;
        final dx = math.sin(a) * 0.5 + (r() - 0.5) * 0.4;
        g.strands.add(TreeStrand(sx, sy, len2, dx, t1 + 0.2));
      }
    }
    if (d == maxD) return;
    final kids = <_Kid>[];
    if (sp.form == 'leader' && leader) {
      kids.add(_Kid(a * 0.4 + (r() - 0.5) * sp.jitter * 0.4, len * sp.leaderDecay, w1 * 0.92, true, 0));
      for (var k = 0; k < sp.side; k++) {
        final s = (k + (d % 2)) % 2 == 1 ? -1.0 : 1.0;
        final na = s * (sp.spread + r() * 0.25);
        final nl = len * sp.decay * (0.85 + r() * 0.3);
        kids.add(_Kid(na, nl, w1 * 0.5, false, 0.2 + k * 0.35));
      }
    } else {
      final n = d <= 1 && r() < 0.45 ? 3 : 2;
      for (var k = 0; k < n; k++) {
        var na = a + lerp(-sp.spread, sp.spread, k / (n - 1)) + (r() - 0.5) * sp.jitter;
        na = na * (1 - sp.up);
        final nl = len * (sp.decay + (r() - 0.5) * 0.14);
        final delay = r() * 0.25;
        kids.add(_Kid(na, nl, w1 * (n == 2 ? 0.8 : 0.7), false, delay));
      }
    }
    for (final k in kids) {
      grow(x1, y1, k.a, k.len, k.w, d + 1, t1 + k.delay, k.leader);
    }
  }

  grow(0, 0, (r() - 0.5) * 0.1, sp.height * sp.trunkFrac, sp.trunkW, 0, 0, true);
}

void _genConifer(double Function() r, TreeSpecies sp, TreeGeometry g) {
  final h = sp.height;
  final cx = (r() - 0.5) * 4;
  final x1 = (r() - 0.5) * 4;
  g.segs.add(TreeSeg(0, 0, cx, -h * 0.5, x1, -h * 0.98, sp.trunkW, 2, 0, 0, 4));
  for (var k = 0; k < 8; k++) {
    final v0 = r() * 0.25;
    final u = (r() - 0.5) * 0.7;
    g.bark.add(TreeBark(0, u, v0, v0 + 0.05 + r() * 0.1));
  }
  final n = sp.tiers;
  for (var i = 0; i < n; i++) {
    final f = i / (n - 1);
    final y = -h * (0.2 + 0.72 * f);
    final w = sp.width * 0.5 * math.pow(1 - f * 0.88, 0.95) * (0.9 + r() * 0.18);
    g.tiers.add(TreeTier(y, w, h * (0.17 - 0.04 * f), 0.2 + f * 3.7, (r() - 0.5) * 6));
  }
}

void _normalise(TreeGeometry g, TreeSpecies sp) {
  double minX = 0, maxX = 0, minY = 0, maxT = 1;
  for (final s in g.segs) {
    minX = math.min(minX, s.x1);
    maxX = math.max(maxX, s.x1);
    minY = math.min(minY, s.y1);
    maxT = math.max(maxT, s.t1);
  }
  for (final c in g.clumps) {
    minX = math.min(minX, c.x - c.r);
    maxX = math.max(maxX, c.x + c.r);
    minY = math.min(minY, c.y - c.r);
    maxT = math.max(maxT, c.t + 0.5);
  }
  for (final t in g.tiers) {
    minX = math.min(minX, -t.w);
    maxX = math.max(maxX, t.w);
    minY = math.min(minY, t.y - t.h);
    maxT = math.max(maxT, t.t + 0.6);
  }
  for (final s in g.strands) {
    maxT = math.max(maxT, s.t + 0.6);
  }
  final halfW = math.max(-minX, maxX);
  final k = math.min(sp.height / -minY, (sp.width / 2) / halfW);
  final sq = math.sqrt(k);
  for (final s in g.segs) {
    s.x0 *= k;
    s.y0 *= k;
    s.cx *= k;
    s.cy *= k;
    s.x1 *= k;
    s.y1 *= k;
    s.w0 *= sq;
    s.w1 *= sq;
    s.t0 /= maxT;
    s.t1 /= maxT;
  }
  for (final c in g.clumps) {
    c.x *= k;
    c.y *= k;
    c.r *= k;
    for (final b in c.blobs) {
      b.dx *= k;
      b.dy *= k;
      b.r *= k;
    }
    c.t /= maxT;
  }
  for (final t in g.tiers) {
    t.y *= k;
    t.w *= k;
    t.h *= k;
    t.t /= maxT;
  }
  for (final s in g.strands) {
    s.x *= k;
    s.y *= k;
    s.len *= sp.height * 0.5;
    s.t /= maxT;
  }
  g.height = -minY * k;
  g.halfW = halfW * k;
  g.crownTop = g.clumps.isEmpty ? 0 : math.min(0.0, g.clumps.map((c) => c.y - c.r).reduce(math.min));
  g.crownBot = g.clumps.isEmpty ? g.crownTop + 1 : math.max(g.crownTop + 1, g.clumps.map((c) => c.y + c.r).reduce(math.max));
}

void _addTouches(double Function() r, TreeSpecies sp, TreeGeometry g) {
  TreeClump? pick() => g.clumps.isEmpty ? null : g.clumps[(r() * g.clumps.length).floor()];
  if (const ['fruit', 'acorns', 'blossom', 'catkins'].contains(sp.touch)) {
    final n = const {'fruit': 22, 'acorns': 12, 'blossom': 70, 'catkins': 26}[sp.touch]!;
    for (var i = 0; i < n; i++) {
      final c = pick();
      if (c == null) break;
      final b = c.blobs[(r() * c.blobs.length).floor()];
      final a = r() * math.pi * 2, d = r() * b.r * 0.85;
      final x = c.x + b.dx + math.cos(a) * d;
      final y = c.y + b.dy + math.sin(a) * d * 0.8 + (sp.touch == 'blossom' ? 0 : b.r * 0.2);
      final rr = sp.touch == 'fruit' ? 3.6 + r() * 1.2 : 1.6 + r() * 1.4;
      g.touches.add(TreeTouch(x, y, rr, c.t, sp.touch));
    }
  }
  if (sp.touch == 'cones') {
    final list = g.tiers.length > 3 ? g.tiers.sublist(1, g.tiers.length - 2) : <TreeTier>[];
    for (final t in list) {
      for (var i = 0; i < 2; i++) {
        if (r() < 0.6) {
          final side = r() < 0.5 ? -1.0 : 1.0;
          g.touches.add(TreeTouch(side * t.w * (0.35 + r() * 0.4), t.y + 2, 3, t.t, 'cones'));
        }
      }
    }
  }
}

/// How much of a tree to show at a stage value [s] in 0..7.
class TreeReveal {
  const TreeReveal({required this.r, required this.rr, required this.sc, required this.thick, required this.touch, required this.seedling, required this.tree});
  final double r, rr, sc, thick, touch, seedling, tree;
}

TreeReveal revealAt(double s) {
  final r = clamp01((s - 3) / 4);
  return TreeReveal(
    r: r,
    rr: s < 3 ? 0 : 0.12 + 0.88 * math.pow(r, 0.7),
    sc: lerp(0.34, 1, math.pow(r, 0.9).toDouble()),
    thick: 0.5 + 0.5 * r,
    touch: smooth(6, 7, s),
    seedling: s < 3.9 ? 1 - smooth(3.15, 3.9, s) : 0,
    tree: smooth(3.0, 3.55, s),
  );
}
