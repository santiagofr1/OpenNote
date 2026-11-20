// Escritura a mano para las capturas del README: texto real dibujado con trazos de una sola línea.
//
// Fuente: Hershey "Script Simplex" (scripts.jhf), de Dr. A. V. Hershey (Naval Weapons Laboratory, 1967).
// Dominio público / uso libre; copia usada: github.com/kamalmostafa/hershey-fonts.
// Archivo generado por un script a partir de scripts.jhf (solo los glifos necesarios); la lógica de abajo es a mano.
//
// Formato de cada glifo: (x izquierdo, x derecho, trazos). Los trazos son pares de letras (x, y) respecto de 'R'
// y se separan con " R" (levantar la lapicera). La línea de base está en y = 9, y crece hacia abajo.

import 'dart:math';
import 'dart:ui';

import 'package:apuntes/domain/domain.dart';

const Map<String, (int, int, String)> _glyphs = {
  'a': (-6, 10, r"UUTSRRPRNSMTLVLXMZO[Q[SZTXVRUWUZV[W[YZZY\V"),
  'b': (-5, 9, r"MVOSRNSLTITGSFQGPIOMNTNZO[P[RZTXUUURVVWWYW[V"),
  'c': (-5, 6, r"TTTSSRQROSNTMVMXNZP[S[VYXV"),
  'd': (-6, 10, r"UUTSRRPRNSMTLVLXMZO[Q[SZTXZF RVRUWUZV[W[YZZY\V"),
  'e': (-4, 6, r"OYQXRWSUSSRRQROSNUNXOZQ[S[UZVYXV"),
  'f': (-3, 5, r"OVSQUNVLWIWGVFTGSIQQNZKaJdJfKgMfNcOZP[R[TZUYWV"),
  'g': (-6, 9, r"UUTSRRPRNSMTLVLXMZO[Q[SZTY RVRTYPdOfMgLfLdMaP^S\U[XY[V"),
  'h': (-5, 10, r"MVOSRNSLTITGSFQGPIOMNSM[ RM[NXOVQSSRURVSVUUXUZV[W[YZZY\V"),
  'i': (-2, 5, r"SMSNTNTMSM RPVRRPXPZQ[R[TZUYWV"),
  'j': (-2, 5, r"SMSNTNTMSM RPVRRLdKfIgHfHdIaL^O\Q[TYWV"),
  'k': (-5, 9, r"MVOSRNSLTITGSFQGPIOMNSM[ RM[NXOVQSSRURVSVUTVQV RQVSWTZU[V[XZYY[V"),
  'l': (-3, 5, r"OVQSTNULVIVGUFSGRIQMPTPZQ[R[TZUYWV"),
  'm': (-13, 12, r"EVGSIRJSJTIXH[ RIXJVLSNRPRQSQTPXO[ RPXQVSSURWRXSXUWXWZX[Y[[Z\Y^V"),
  'n': (-8, 10, r"JVLSNROSOTNXM[ RNXOVQSSRURVSVUUXUZV[W[YZZY\V"),
  'o': (-6, 8, r"RRPRNSMTLVLXMZO[Q[SZTYUWUUTSRRQSQURWTXWXYWZV"),
  'p': (-7, 8, r"KVMSNQMUGg RMUNSPRRRTSUUUWTYSZQ[ RMZO[R[UZWYZV"),
  'q': (-6, 9, r"UUTSRRPRNSMTLVLXMZO[Q[SZ RVRUUSZPaOdOfPgRfScS\U[XY[V"),
  'r': (-5, 8, r"MVOSPQPSSSTTTVSYSZT[U[WZXYZV"),
  's': (-4, 7, r"NVPSQQQSSVTXTZR[ RNZP[T[VZWYYV"),
  't': (-3, 6, r"OVQSSO RVFPXPZQ[S[UZVYXV RPNWN"),
  'u': (-6, 9, r"LVNRLXLZM[O[QZSXUU RVRTXTZU[V[XZYY[V"),
  'v': (-6, 9, r"LVNRMWMZN[O[RZTXUUUR RURVVWWYW[V"),
  'w': (-9, 12, r"LRJTIWIYJ[L[NZPX RRRPXPZQ[S[UZWXXUXR RXRYVZW\W^V"),
  'x': (-8, 8, r"JVLSNRPRQSQZR[U[XYZV RWSVRTRSSOZN[L[KZ"),
  'y': (-6, 9, r"LVNRLXLZM[O[QZSXUU RVRPdOfMgLfLdMaP^S\U[XY[V"),
  'z': (-6, 8, r"LVNSPRRRTTTVSXQZN[P\Q^QaPdOfMgLfLdMaP^S\WYZV"),
  'A': (-11, 9, r"G[IZLWOSSLVFV[UXSUQSNQLQKRKTLVNXQZT[Y["),
  'B': (-12, 11, r"SHTITLSPRSQUOXMZK[J[IZIWJRKOLMNJPHRGUFXFZG[I[KZMYNWOTP RSPTPWQXRYTYWXYWZU[R[PZOX"),
  'C': (-10, 10, r"TLTMUNWNYMZKZIYGWFTFQGOIMLLNKRKVLYMZO[Q[TZVXWV"),
  'D': (-11, 12, r"TFRGQIPMOSNVMXKZI[G[FZFXGWIWKXMZP[S[VZXXZT[O[KZHYGWFTFRHRJSMUPWRZT\U"),
  'E': (-10, 10, r"VJVKWLYLZKZIYGVFRFOGNINLONPOSPPPMQLRKTKWLYMZP[S[VZXXYV"),
  'F': (-10, 10, r"RLPLNKMINGQFTFXG[G]F RXGVNTTRXPZN[L[JZIXIVJULUNV RQPZP"),
  'G': (-11, 12, r"G[IZMVPQQNRJRGQFPFOGNINLONQOUOXNYMZKZQYVXXVZS[O[LZJXIVIT"),
  'H': (-12, 12, r"MMKLJJJIKGMFNFPGQIQKPONULYJ[H[GZGX RMRVOXN[L]J^H^G]F\FZHXLVRUWUZV[W[YZZY\V"),
  'I': (-9, 8, r"WVUTSQROQLQIRGSFUFVGWIWLVQTVSXQZO[M[KZJXJVKUMUOV"),
  'J': (-8, 7, r"T^R[PVOPOJPGRFTFUGVJVMURR[PaOdNfLgKfKdLaN^P\SZWX"),
  'K': (-12, 12, r"MMKLJJJIKGMFNFPGQIQKPONULYJ[H[GZGX R^I^G]F\FZGXIVLTNROPO RROSQSXTZU[V[XZYY[V"),
  'L': (-9, 10, r"MRORSQVOXMYKYHXFVFUGTISNRSQVPXNZL[J[IZIXJWLWNXQZT[V[YZ[X"),
  'M': (-18, 15, r"EMCLBJBICGEFFFHGIIIKHPGTE[ RGTJLLHMGOFPFRGSISKRPQTO[ RQTTLVHWGYFZF\G]I]K\PZWZZ[[\[^Z_YaV"),
  'N': (-13, 11, r"JMHLGJGIHGJFKFMGNINKMPLTJ[ RLTOLQHRGTFVFXGYIYKXPVWVZW[X[ZZ[Y]V"),
  'O': (-10, 11, r"TFQGOIMLLNKRKVLYMZO[Q[TZVXXUYSZOZKYHXGVFTFRHRKSNUQWSZU\V"),
  'P': (-12, 13, r"SHTITLSPRSQUOXMZK[J[IZIWJRKOLMNJPHRGUFZF\G]H^J^M]O\PZQWQUPTO"),
  'Q': (-10, 12, r"ULTNSOQPOPNNNLOIQGTFWFYGZIZMYPWSSWPYNZK[I[HZHXIWKWMXPZS[V[YZ[X"),
  'R': (-12, 13, r"SHTITLSPRSQUOXMZK[J[IZIWJRKOLMNJPHRGUFYF[G\H]J]M\O[PYQVQSPTQUSUXVZX[ZZ[Y]V"),
  'S': (-10, 10, r"H[JZLXOTQQSMTJTGSFRFQGPIPKQMSOVQXSYUYWXYWZT[P[MZKXJVJT"),
  'T': (-10, 9, r"RLPLNKMINGQFTFXG[G]F RXGVNTTRXPZN[L[JZIXIVJULUNV"),
  'U': (-13, 11, r"JMHLGJGIHGJFKFMGNINKMOLRKVKXLZN[P[RZSYUUXMZF RXMWQVWVZW[X[ZZ[Y]V"),
  'V': (-12, 11, r"KMILHJHIIGKFLFNGOIOKNOMRLVLYM[O[QZTWVTXPYMZIZGYFXFWGVIVKWNYP[Q"),
  'W': (-15, 13, r"HMFLEJEIFGHFIFKGLILLK[ RUFK[ RUFS[ RaF_G\JYNVTS["),
  'X': (-12, 12, r"NLLLKKKILGNFPFRGSISLQUQXRZT[V[XZYXYVXUVU R]I]G\FZFXGVITLPUNXLZJ[H[GZGX"),
  'Y': (-12, 11, r"KMILHJHIIGKFLFNGOIOKNOMRLVLXMZN[P[RZTXVUWSYM R[FYMVWT]RbPfNgMfMdNaP^S[VY[V"),
  'Z': (-10, 11, r"ULTNSOQPOPNNNLOIQGTFWFYGZIZMYPWTTWPZN[K[JZJXKWNWPXQYR[R^QaPcNfLgKfKdLaN^Q[TYZV"),
  '0': (-10, 11, r"TFQGOIMLLOKSKVLYMZO[Q[TZVXXUYRZNZKYHXGVFTF RTFRGPINLMOLSLVMYO[ RQ[SZUXWUXRYNYKXHVF"),
  '1': (-10, 11, r"TJO[ RVFP[ RVFSIPKNL RUIQKNL"),
  '2': (-10, 11, r"OJPKOLNKNJOHPGSFVFYGZIZKYMWOTQPSMUKWI[ RVFXGYIYKXMVOPS RJYKXMXRZUZWYXW RMXR[U[WZXW"),
  '3': (-10, 11, r"OJPKOLNKNJOHPGSFVFYGZIZKYMVOSP RVFXGYIYKXMVO RQPSPVQWRXTXWWYVZS[O[LZKYJWJVKULVKW RSPUQVRWTWWVYUZS["),
  '4': (-10, 11, r"XGR[ RYFS[ RYFJUZU"),
  '5': (-10, 11, r"QFLP RQF[F RQGVG[F RLPMOPNSNVOWPXRXUWXUZR[O[LZKYJWJVKULVKW RSNUOVPWRWUVXTZR["),
  '6': (-10, 11, r"YIXJYKZJZIYGWFTFQGOIMLLOKSKWLYMZO[R[UZWXXVXSWQVPTOQOOPMRLT RTFRGPINLMOLSLXMZ RR[TZVXWVWRVP"),
  '7': (-10, 11, r"NFLL R[FZIXLSRQUPWO[ RXLRRPUOWN[ RMIPFRFWI RNHPGRGWIYIZH[F"),
  '8': (-10, 11, r"SFPGOHNJNMOOQPTPXOYNZLZIYGVFSF RSFQGPHOJOMPOQP RTPWOXNYLYIXGVF RQPMQKSJUJXKZN[R[VZWYXWXTWRVQTP RQPNQLSKUKXLZN[ RR[UZVYWWWSVQ"),
  '9': (-10, 11, r"YMXOVQTRQROQNPMNMKNIPGSFVFXGYHZJZNYRXUVXTZQ[N[LZKXKWLVMWLX ROQNONKOIQGSF RXGYIYNXRWUUXSZQ["),
  '.': (-5, 5, r"RYQZR[SZRY"),
  ',': (-5, 6, r"P[OZPYQZQ[P]N_"),
  ':': (-5, 6, r"SMRNSOTNSM RPYOZP[QZ"),
  ';': (-5, 6, r"SMRNSOTNSM RP[OZPYQZQ[P]N_"),
  '-': (-13, 13, r"IR[R"),
  '(': (-7, 8, r"ZBVESHQKOONTNXO]P`Qb RVESIQMPPOUOZP_Qb"),
  ')': (-8, 7, r"SBTDUGVLVPUUSYQ\N_Jb RSBTEUJUOTTSWQ[N_"),
  '=': (-13, 13, r"IO[O RIU[U"),
  '+': (-13, 13, r"RIR[ RIR[R"),
  '/': (-11, 11, r"_BEb"),
  '?': (-10, 11, r"OJPKOLNKNJOHPGSFWFZG[I[KZMYNSPQQQSRTTT RWFYGZIZKYMXNVO RPYOZP[QZPY"),
  '<': (-12, 12, r"ZIJRZ["),
  '>': (-12, 12, r"JIZRJ["),
  '!': (-5, 6, r"UFTGRS RUGRS RUFVGRS RPYOZP[QZPY"),
  '\'': (-5, 6, r"UHTGUFVGVHUJSL"),
  '%': (-12, 12, r"[FI[ RNFPHPJOLMMKMIKIIJGLFNFPGSHVHYG[F RWTUUTWTYV[X[ZZ[X[VYTWT"),
  '_': (-8, 8, r"J]Z]"),
  ' ': (-8, 8, r""),
  '|': (-4, 4, r"RBRb"),
  '[': (-7, 7, r"OBOb RPBPb ROBVB RObVb"),
  ']': (-7, 7, r"TBTb RUBUb RNBUB RNbUb"),
};

const double _baseY = 9; // y de la línea de base en las unidades de la fuente

typedef _Pt = (double, double); // x, y en unidades de la fuente (y hacia abajo, base en 0)

class _Glyph {
  final double adv;
  final List<List<_Pt>> strokes;
  _Glyph(this.adv, this.strokes);
}

final Map<String, _Glyph> _cache = {};

_Glyph _glyph(String ch) => _cache.putIfAbsent(ch, () {
      final g = _glyphs[ch] ?? _glyphs['?']!;
      final strokes = <List<_Pt>>[];
      for (final part in g.$3.split(' R')) {
        final s = <_Pt>[];
        for (var i = 0; i + 1 < part.length; i += 2) {
          s.add((part.codeUnitAt(i) - 82 - g.$1.toDouble(), part.codeUnitAt(i + 1) - 82 - _baseY));
        }
        if (s.isNotEmpty) strokes.add(s);
      }
      return _Glyph((g.$2 - g.$1).toDouble(), strokes);
    });

/// Letra con tilde, ñ, ü, o la theta, armadas con un glifo base más un trazo corto. Null si no hay nada especial.
_Glyph? _special(String ch) {
  const marks = {
    'á': ('a', 'ac'), 'é': ('e', 'ac'), 'í': ('i', 'ac'), 'ó': ('o', 'ac'), 'ú': ('u', 'ac'),
    'Á': ('A', 'AC'), 'É': ('E', 'AC'), 'Í': ('I', 'AC'), 'Ó': ('O', 'AC'), 'Ú': ('U', 'AC'),
    'ñ': ('n', 'ti'), 'Ñ': ('N', 'TI'), 'ü': ('u', 'di'),
  };
  if (ch == 'θ') {
    final oval = <_Pt>[for (var i = 0; i <= 24; i++) (5.2 + 4.6 * cos(2 * pi * i / 24 + pi / 2), -9 - 9.2 * sin(2 * pi * i / 24 + pi / 2))];
    return _Glyph(12, [oval, [(1.0, -9.0), (9.4, -9.0)]]);
  }
  final m = marks[ch];
  if (m == null) return null;
  final base = _glyph(m.$1);
  final cx = base.adv / 2 + 1;
  // y de arriba de la letra: -10 minúsculas con ascendente (i va más alto por el punto), -13 mayúsculas
  final cap = m.$2 == m.$2.toUpperCase();
  final top = cap ? -23.0 : (m.$1 == 'i' ? -16.5 : -10.5);
  final List<_Pt> mark;
  switch (m.$2.toLowerCase()) {
    case 'ac':
      mark = [(cx - 1.8, top + 0.5), (cx + 2.2, top - 3.8)];
    case 'ti':
      mark = [for (var i = 0; i <= 8; i++) (cx - 4 + i, top - 2.2 - 1.6 * sin(pi * (i / 8 * 2 - .1)))];
    default:
      mark = [(cx - 2.5, top - 2), (cx - 2.3, top - 2.2)];
  }
  final strokes = [...base.strokes, mark];
  if (m.$2.toLowerCase() == 'di') strokes.add([(cx + 2.5, top - 2), (cx + 2.7, top - 2.2)]);
  return _Glyph(base.adv, strokes);
}

_Glyph _glyphOf(String ch) => _special(ch) ?? _glyph(ch == '–' || ch == '−' ? '-' : ch);

/// Catmull-Rom entre los puntos, con unos [step] de separación: para que no se vea poligonal.
List<_Pt> _smooth(List<_Pt> p, double step) {
  if (p.length < 3) return p;
  final out = <_Pt>[p.first];
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.length - 1, i + 2)];
    final len = sqrt(pow(p2.$1 - p1.$1, 2) + pow(p2.$2 - p1.$2, 2));
    final n = max(1, (len / step).ceil());
    for (var s = 1; s <= n; s++) {
      final t = s / n, t2 = t * t, t3 = t2 * t;
      double c(double a, double b, double cc, double d) =>
          .5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3);
      out.add((c(p0.$1, p1.$1, p2.$1, p3.$1), c(p0.$2, p1.$2, p2.$2, p3.$2)));
    }
  }
  return out;
}

class _Tok {
  final String ch;
  final bool sub;
  _Tok(this.ch, this.sub);
}

/// Texto a mano alzada: devuelve los trazos de [text] con la línea de base del primer renglón en [origin].
///
/// [size] es la altura de la x en unidades lógicas por unidad de fuente (1 = ~9 unidades de letra minúscula);
/// con 1.5 la minúscula mide ~13 y la mayúscula ~31, bien para un renglón de 8 mm (38 unidades).
/// Los renglones nuevos bajan [lineHeight]; se corta al pasar [maxWidth]. `\n` fuerza un corte.
/// `_x` escribe el próximo carácter como subíndice.
List<Stroke> handwrite(
  String text,
  Offset origin, {
  double size = 1.5,
  String color = '#22211e',
  double width = 2.2,
  Random? rnd,
  double maxWidth = 780,
  double lineHeight = 38.1,
  double slantDeg = 8,
  double wobble = 1,
}) {
  final r = rnd ?? Random(1);
  final tan = tanOfDeg(slantDeg);
  final out = <Stroke>[];
  // 1) palabras de la línea
  final words = <List<_Tok>>[];
  for (final line in text.split('\n')) {
    final toks = <_Tok>[];
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '_' && i + 1 < line.length) {
        toks.add(_Tok(line[++i], true));
      } else if (ch == ' ') {
        if (toks.isNotEmpty) words.add(toks.toList());
        toks.clear();
      } else {
        toks.add(_Tok(ch, false));
      }
    }
    if (toks.isNotEmpty) words.add(toks);
    words.add([]); // marca de fin de renglón
  }
  double wordWidth(List<_Tok> w) => w.fold<double>(0, (a, t) => a + _glyphOf(t.ch).adv * (t.sub ? .65 : 1) * size);

  var x = 0.0, row = 0;
  double drift = (r.nextDouble() - .5) * 3;
  for (final w in words) {
    if (w.isEmpty) {
      x = 0;
      row++;
      drift = (r.nextDouble() - .5) * 3;
      continue;
    }
    final ww = wordWidth(w);
    if (x > 0 && x + ww > maxWidth) {
      x = 0;
      row++;
    }
    final k = size * (.94 + r.nextDouble() * .12); // tamaño propio de cada palabra
    final base = origin.dy + row * lineHeight + (r.nextDouble() - .5) * 1.6 * wobble + drift * (x / maxWidth);
    final lean = tan + (r.nextDouble() - .5) * .05;
    var pen = origin.dx + x;
    List<_Pt>? open; // trazo en curso, en coordenadas de hoja
    void flush() {
      if (open != null && open!.length > 1) out.add(_inkStroke(open!, color, width, r));
      open = null;
    }

    for (final t in w) {
      final g = _glyphOf(t.ch);
      final gk = k * (t.sub ? .65 : 1), dy = t.sub ? 4.5 * k : 0.0;
      List<_Pt> place(List<_Pt> s) => [
            for (final p in s)
              (pen + p.$1 * gk - p.$2 * gk * lean + (r.nextDouble() - .5) * .25 * wobble,
                  base + p.$2 * gk + dy + (r.nextDouble() - .5) * .25 * wobble),
          ];
      // el trazo más largo es el cuerpo de la letra: es el que se une con la anterior
      var main = 0, best = -1.0;
      for (var i = 0; i < g.strokes.length; i++) {
        final s = g.strokes[i];
        var len = 0.0;
        for (var j = 1; j < s.length; j++) {
          len += sqrt(pow(s[j].$1 - s[j - 1].$1, 2) + pow(s[j].$2 - s[j - 1].$2, 2));
        }
        if (len > best) {
          best = len;
          main = i;
        }
      }
      for (var i = 0; i < g.strokes.length; i++) {
        if (i == main) continue;
        out.add(_inkStroke(place(g.strokes[i]), color, width, r));
      }
      final body = place(g.strokes[main]);
      final o = open;
      if (o != null && (o.last.$1 - body.first.$1).abs() < 5 * k && (o.last.$2 - body.first.$2).abs() < 5 * k) {
        o.addAll(body.skip(1)); // se une con la letra anterior
      } else {
        flush();
        open = body;
      }
      pen += g.adv * gk * (.96 + r.nextDouble() * .08);
    }
    flush();
    x = pen - origin.dx + _glyph(' ').adv * size * (.55 + r.nextDouble() * .3);
  }
  return out;
}

double tanOfDeg(double d) => tan(d * pi / 180);

/// Trazo con puntos suavizados y presión: más fuerte en las bajadas, suave al entrar y al salir.
Stroke _inkStroke(List<_Pt> raw, String color, double w, Random r) {
  final p = _smooth(raw, 1.4);
  final pts = <double>[];
  final n = p.length;
  var pr = .55;
  for (var i = 0; i < n; i++) {
    final a = p[max(0, i - 1)], b = p[min(n - 1, i + 1)];
    final dy = b.$2 - a.$2, len = sqrt(pow(b.$1 - a.$1, 2) + dy * dy) + 1e-6;
    final target = .5 + .3 * (dy / len).clamp(-1, 1) + (r.nextDouble() - .5) * .08;
    pr = pr * .75 + target * .25;
    final edge = n < 4 ? 1.0 : min(1.0, .6 + .4 * min(i, n - 1 - i) / 3);
    pts.addAll([p[i].$1, p[i].$2, (pr * edge).clamp(.2, 1)]);
  }
  return Stroke(newId('s'), 'pen', color, w, pts);
}
