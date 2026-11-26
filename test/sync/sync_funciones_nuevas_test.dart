import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/templates.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/e2e_crypto.dart';
import 'package:apuntes/sync/encrypted_remote_store.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las funciones nuevas (plantillas propias, fondos, títulos con zona sobre un PDF, marcadores, links, formas exactas,
/// lienzo infinito, páginas de PDF) viajan idénticas de un dispositivo a otro: con la nube a secas y con cifrado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  final realBgPicker = Pickers.bgImage;
  tearDown(() {
    Pickers.bgImage = realBgPicker;
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  // PNG de 1x1 válido
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  final pdfBytes = Uint8List.fromList(
    utf8.encode('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n') +
        List.generate(300, (i) => i % 256),
  );

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_nuevas');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<Notebook> create(
    Storage s,
    String name, {
    int n = 2,
    bool canvas = false,
  }) async {
    final nb = Notebook.create(name, canvas: canvas);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    d.texts['t0'] = TextBlock('t0', 90, 44, 800, 'base');
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  Future<Notebook> nbOf(Storage s, String id) async =>
      (await s.loadIndex()).notebooks.firstWhere((n) => n.id == id);

  /// Carga el cuaderno, deja que [f] lo toque y guarda como el editor (sube el `updated` de la hoja [k]).
  Future<void> change(
    Storage s,
    String id,
    int k,
    void Function(NotebookDoc d, SheetMeta m) f,
  ) async {
    final idx = await s.loadIndex();
    final nb = idx.notebooks.firstWhere((n) => n.id == id);
    final d = await s.loadNotebook(nb);
    final m = d.sheets[k];
    f(d, m);
    final now = DateTime.now().millisecondsSinceEpoch;
    m.updated = now > m.updated ? now : m.updated + 1;
    m.rev++;
    d.markDirtyAt(k * kSheetStep + 44);
    nb.touch();
    await s.saveNotebook(d);
    await s.saveIndex(idx);
  }

  Future<SheetContent> contentOf(Storage s, String id, int k) async {
    final nb = await nbOf(s, id);
    return s.readSheetContent(nb, nb.sheets[k]);
  }

  String metaJson(SheetMeta m) => jsonEncode(m.toJson()..remove('rev'));
  String itemsJson(SheetContent c) => jsonEncode(
    [for (final i in c.items) i.toJson()]
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
  );
  String strokesJson(SheetContent c) => jsonEncode([
    for (final s in c.strokes) [s.id, s.k, s.c, s.w, s.o, s.fill, s.pts],
  ]);

  for (final cifrado in [false, true]) {
    group(cifrado ? 'con cifrado' : 'sin cifrado', () {
      late FakeRemoteStore remote;
      late Vault vault;
      late VaultInfo info;
      final caches = <Storage, HashCache>{};
      setUp(() async {
        remote = FakeRemoteStore();
        (vault, info) = await Vault.create('una frase', kdf: KdfParams.fast);
        caches.clear();
      });

      Future<SyncReport> sync(Storage s) async {
        final store = cifrado
            ? EncryptedRemoteStore(
                remote,
                vault,
                info,
                cache: caches.putIfAbsent(s, HashCache.new),
              )
            : remote;
        final rep = await SyncEngine(
          s,
          store,
          busy: () => const {},
          account: 'a@b.c',
        ).sync();
        expect(rep.errors, isEmpty, reason: rep.toString());
        return rep;
      }

      /// A sube, B baja, B sube, A baja.
      Future<void> roundTrip(Storage x, Storage y) async {
        await sync(x);
        await sync(y);
        await sync(y);
        await sync(x);
      }

      Future<(String, String)> bgPickerTemplates(Storage s, String name) async {
        final f = File('${s.dir.path}/$name')..writeAsBytesSync(png);
        Pickers.bgImage = () async => f;
        final t = await templateFromImage(s);
        expect(t, isNotNull);
        return (t!.id, t.file);
      }

      group('plantillas propias', () {
        test('crear en A llega a B (con su imagen); editar en B vuelve a A; borrar en A se propaga', () async {
          final a = await device(), b = await device();
          final (id, file) = await bgPickerTemplates(a, 'fondo.png');
          await sync(a);
          expect(remote.has('templates/$id.json'), isTrue);
          expect(
            remote.has('media/$file'),
            isTrue,
            reason: 'la imagen de la plantilla tiene que viajar',
          );
          await sync(b);
          final tb = await readTemplates(b);
          expect([for (final t in tb) t.id], [id]);
          expect(tb.single.name, 'fondo');
          expect(tb.single.file, file);
          expect(
            b.media(file).readAsBytesSync(),
            a.media(file).readAsBytesSync(),
          );

          // B la renombra (reescribe el archivo, como haría la app)
          final j = jsonDecode(
            await b.syncFile('templates/$id.json').readAsString(),
          ) as Map;
          j['name'] = 'Cuadriculado B';
          await b.writeSyncFile(
            'templates/$id.json',
            utf8.encode(jsonEncode(j)),
          );
          await roundTrip(b, a);
          expect(
            [for (final t in await readTemplates(a)) t.name],
            ['Cuadriculado B'],
          );

          await deleteTemplate(a, id);
          await roundTrip(a, b);
          expect(await readTemplates(a), isEmpty);
          expect(await readTemplates(b), isEmpty);
          expect(remote.has('templates/$id.json'), isFalse);
        });

        test('la misma plantilla editada en los dos lados: queda una sola, sin romperse', () async {
          final a = await device(), b = await device();
          final (id, _) = await bgPickerTemplates(a, 'fondo.png');
          await roundTrip(a, b);
          Future<void> rename(Storage s, String n) async {
            final j = jsonDecode(
              await s.syncFile('templates/$id.json').readAsString(),
            ) as Map;
            j['name'] = n;
            await s.writeSyncFile(
              'templates/$id.json',
              utf8.encode(jsonEncode(j)),
            );
          }

          await rename(a, 'Nombre de A');
          await rename(b, 'Nombre de B');
          await roundTrip(a, b);
          await roundTrip(a, b);
          final ta = await readTemplates(a), tb = await readTemplates(b);
          // Comportamiento real: la plantilla no se duplica ni se rompe; ambos dispositivos terminan con el mismo nombre
          // (gana uno de los dos: es un archivo chico, un nombre por plantilla).
          expect(ta, hasLength(1));
          expect(tb, hasLength(1));
          expect(ta.single.name, tb.single.name);
          expect(['Nombre de A', 'Nombre de B'], contains(ta.single.name));
        });

        test(
          'una hoja con fondo de plantilla (bg image) lleva la imagen a B',
          () async {
            final a = await device(), b = await device();
            final (_, file) = await bgPickerTemplates(a, 'fondo.png');
            final nb = await create(a, 'Con plantilla', n: 1);
            await change(a, nb.id, 0, (d, m) {
              m.bg = 'image';
              m.image = file;
            });
            await roundTrip(a, b);
            final m = (await nbOf(b, nb.id)).sheets[0];
            expect(m.bg, 'image');
            expect(m.image, file);
            expect(b.media(file).readAsBytesSync(), png);
          },
        );
      });

      group('fondos de hoja', () {
        test(
          'mm, axes, spacing y size llegan idénticos; B cambia y vuelve a A',
          () async {
            final a = await device(), b = await device();
            final nb = await create(a, 'Fondos', n: 3);
            await change(a, nb.id, 0, (d, m) {
              m.bg = 'mm';
              m.spacing = 5;
              m.size = 'a3';
            });
            await change(a, nb.id, 1, (d, m) {
              m.bg = 'axes';
              m.spacing = 10;
              m.size = 'a5';
              m.paper = '#ffeecc';
            });
            await roundTrip(a, b);
            final na = await nbOf(a, nb.id), nbb = await nbOf(b, nb.id);
            for (var k = 0; k < 3; k++) {
              expect(
                metaJson(nbb.sheets[k]),
                metaJson(na.sheets[k]),
                reason: 'hoja $k',
              );
            }
            expect(
              [nbb.sheets[0].bg, nbb.sheets[0].spacing, nbb.sheets[0].size],
              ['mm', 5, 'a3'],
            );
            expect(
              [
                nbb.sheets[1].bg,
                nbb.sheets[1].spacing,
                nbb.sheets[1].size,
                nbb.sheets[1].paper,
              ],
              ['axes', 10, 'a5', '#ffeecc'],
            );

            await change(b, nb.id, 2, (d, m) {
              m.bg = 'mm';
              m.spacing = 2;
            });
            await roundTrip(b, a);
            final m = (await nbOf(a, nb.id)).sheets[2];
            expect([m.bg, m.spacing], ['mm', 2]);
          },
        );

        test('bg image con SheetMeta.image: la imagen viaja', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Imagen', n: 1);
          final name = await a.addMedia(png, 'png');
          await change(a, nb.id, 0, (d, m) {
            m.bg = 'image';
            m.image = name;
          });
          await roundTrip(a, b);
          final m = (await nbOf(b, nb.id)).sheets[0];
          expect([m.bg, m.image], ['image', name]);
          expect(b.media(name).readAsBytesSync(), png);
          // y si B la deja de usar, vuelve a A
          await change(b, nb.id, 0, (d, m) => m.setBg('grid'));
          await roundTrip(b, a);
          final ma = (await nbOf(a, nb.id)).sheets[0];
          expect([ma.bg, ma.image], ['grid', null]);
        });

        test('mismo fondo distinto en los dos lados: la hoja queda con uno de los dos y no se pierde el contenido', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Choque', n: 1);
          await roundTrip(a, b);
          await change(a, nb.id, 0, (d, m) => m.bg = 'mm');
          await change(b, nb.id, 0, (d, m) => m.bg = 'axes');
          await roundTrip(a, b);
          await roundTrip(a, b);
          final ma = await nbOf(a, nb.id), mb = await nbOf(b, nb.id);
          expect(
            ma.sheets.map(metaJson).toList(),
            mb.sheets.map(metaJson).toList(),
          );
          expect(['mm', 'axes'], contains(ma.sheets[0].bg));
          expect(
            [for (final t in (await contentOf(a, nb.id, 0)).texts) t.text],
            ['base'],
          );
        });
      });

      group('títulos con zona (Heading.box) sobre un PDF', () {
        test('box, nivel, título e ids llegan igual y el índice da la misma entrada', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Apunte PDF', n: 1);
          final pdf = await a.addMedia(pdfBytes, 'pdf');
          await change(a, nb.id, 0, (d, m) {
            d.items['p1'] = Item(
              'p1',
              'pdf',
              40,
              60,
              700,
              900,
              file: pdf,
              page: 3,
            );
            m.heads.add(
              Heading(
                'h1',
                level: 2,
                title: 'Teorema 1',
                y: 260,
                ids: ['p1'],
                box: const Rect.fromLTWH(12.5, 200, 400, 30.5),
              ),
            );
            m.heads.add(
              Heading(
                'h0',
                level: 1,
                title: 'Capítulo',
                y: 60,
                ids: ['p1'],
                box: const Rect.fromLTWH(0, 0, 100, 20),
              ),
            );
          });
          await roundTrip(a, b);
          final na = await nbOf(a, nb.id), nbb = await nbOf(b, nb.id);
          final h = nbb.sheets[0].heads.firstWhere((x) => x.id == 'h1');
          expect(h.box, const Rect.fromLTWH(12.5, 200, 400, 30.5));
          expect(
            [h.level, h.title, h.y, h.ids],
            [
              2,
              'Teorema 1',
              260.0,
              ['p1'],
            ],
          );
          expect(
            nbb.sheets[0].heads.firstWhere((x) => x.id == 'h0').box,
            const Rect.fromLTWH(0, 0, 100, 20),
          );
          String line(OutlineEntry e) =>
              '${e.number}|${e.title}|${e.sheetId}|${e.level}|${e.y}';
          final ob = buildOutline(nbb);
          expect(
            [for (final e in ob) line(e)],
            [for (final e in buildOutline(na)) line(e)],
          );
          expect(
            [for (final e in ob) '${e.number} ${e.title}'],
            ['1 Capítulo', '1.1 Teorema 1'],
          );
          // el PDF y el item
          final it = (await contentOf(b, nb.id, 0)).items.single;
          expect([it.type, it.file, it.page], ['pdf', pdf, 3]);
          expect(b.media(pdf).readAsBytesSync(), pdfBytes);
        });

        test(
          'B mueve la zona y la renombra: vuelve a A; sin box sigue sin box',
          () async {
            final a = await device(), b = await device();
            final nb = await create(a, 'Apunte PDF', n: 1);
            await change(a, nb.id, 0, (d, m) {
              m.heads.add(
                Heading(
                  'h1',
                  title: 'Con zona',
                  y: 100,
                  ids: ['x'],
                  box: const Rect.fromLTWH(1, 2, 3, 4),
                ),
              );
              m.heads.add(Heading('h2', title: 'Sin zona', y: 200, ids: ['x']));
            });
            await roundTrip(a, b);
            await change(
              b,
              nb.id,
              0,
              (d, m) => m.heads.firstWhere((x) => x.id == 'h1')
                ..box = const Rect.fromLTWH(10, 20, 30, 40)
                ..title = 'Zona nueva',
            );
            await roundTrip(b, a);
            final hs = (await nbOf(a, nb.id)).sheets[0].heads;
            expect(
              hs.firstWhere((x) => x.id == 'h1').box,
              const Rect.fromLTWH(10, 20, 30, 40),
            );
            expect(hs.firstWhere((x) => x.id == 'h1').title, 'Zona nueva');
            expect(hs.firstWhere((x) => x.id == 'h2').box, isNull);
          },
        );

        test('los dos agregan un título distinto a la misma hoja: quedan los dos, con su zona', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Choque', n: 1);
          await roundTrip(a, b);
          await change(
            a,
            nb.id,
            0,
            (d, m) => m.heads.add(
              Heading(
                'hA',
                title: 'De A',
                y: 10,
                ids: ['x'],
                box: const Rect.fromLTWH(1, 1, 5, 5),
              ),
            ),
          );
          await change(
            b,
            nb.id,
            0,
            (d, m) => m.heads.add(
              Heading(
                'hB',
                title: 'De B',
                y: 20,
                ids: ['x'],
                box: const Rect.fromLTWH(2, 2, 6, 6),
              ),
            ),
          );
          await roundTrip(a, b);
          await roundTrip(a, b);
          final na = await nbOf(a, nb.id), nbB = await nbOf(b, nb.id);
          Map<String, Rect?> boxes(Notebook n) => {for (final h in n.sheets[0].heads) h.title: h.box};
          expect(boxes(na), {'De A': const Rect.fromLTWH(1, 1, 5, 5), 'De B': const Rect.fromLTWH(2, 2, 6, 6)});
          expect(boxes(nbB), boxes(na));
          expect(na.sheets, hasLength(1));
        });
      });

      group('marcadores', () {
        test('bookmark y título de la hoja (nombre del marcador) llegan; B lo quita y vuelve', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Marcas', n: 3);
          await change(a, nb.id, 1, (d, m) {
            m.bookmark = true;
            m.title = 'Ejercicio ñandú 5';
          });
          await roundTrip(a, b);
          final s = (await nbOf(b, nb.id)).sheets;
          expect([s[1].bookmark, s[1].title], [true, 'Ejercicio ñandú 5']);
          expect([s[0].bookmark, s[2].bookmark], [false, false]);

          await change(b, nb.id, 1, (d, m) => m.bookmark = false);
          await change(b, nb.id, 2, (d, m) {
            m.bookmark = true;
            m.title = 'Fin';
          });
          await roundTrip(b, a);
          final t = (await nbOf(a, nb.id)).sheets;
          expect([t[1].bookmark, t[1].title], [false, 'Ejercicio ñandú 5']);
          expect([t[2].bookmark, t[2].title], [true, 'Fin']);
        });

        test(
          'marcadores en hojas distintas sin sincronizar: quedan los dos',
          () async {
            final a = await device(), b = await device();
            final nb = await create(a, 'Marcas', n: 2);
            await roundTrip(a, b);
            await change(a, nb.id, 0, (d, m) {
              m.bookmark = true;
              m.title = 'A';
            });
            await change(b, nb.id, 1, (d, m) {
              m.bookmark = true;
              m.title = 'B';
            });
            await roundTrip(a, b);
            await roundTrip(a, b);
            for (final s in [a, b]) {
              final sh = (await nbOf(s, nb.id)).sheets;
              expect(
                [
                  for (final m in sh)
                    if (m.bookmark) m.title,
                ],
                ['A', 'B'],
              );
            }
          },
        );
      });

      group('links', () {
        test('a web, a otra hoja y a otro cuaderno llegan iguales y siguen resolviendo', () async {
          final a = await device(), b = await device();
          final n1 = await create(a, 'Origen', n: 2);
          final n2 = await create(a, 'Destino', n: 1);
          final sheetId = n1.sheets[1].id;
          await change(a, n1.id, 0, (d, m) {
            d.items['l1'] = Item(
              'l1',
              'link',
              50,
              100,
              220,
              48,
              text: 'https://example.com/a?b=1&c=ñ',
            );
            d.items['l2'] = Item(
              'l2',
              'link',
              50,
              200,
              220,
              48,
              text: 'sheet:$sheetId',
            );
            d.items['l3'] = Item(
              'l3',
              'link',
              50,
              300,
              220,
              48,
              text: 'nb:${n2.id}',
            );
          });
          await roundTrip(a, b);
          final c = await contentOf(b, n1.id, 0);
          expect(itemsJson(c), itemsJson(await contentOf(a, n1.id, 0)));
          final byId = {for (final i in c.items) i.id: parseLink(i.text)};
          expect(
            byId['l1'],
            LinkWeb(Uri.parse('https://example.com/a?b=1&c=ñ')),
          );
          final nbB = await nbOf(b, n1.id);
          final ls = byId['l2'] as LinkSheet;
          expect(
            nbB.allSheets.any((m) => m.id == ls.id),
            isTrue,
            reason: 'la hoja destino existe en B',
          );
          final ln = byId['l3'] as LinkNotebook;
          expect(
            (await b.loadIndex()).notebooks.any((n) => n.id == ln.id),
            isTrue,
            reason: 'el cuaderno destino existe en B',
          );
        });

        test('B edita el destino de un link y vuelve a A; el mismo link editado en los dos lados no se pierde', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Links', n: 1);
          await change(
            a,
            nb.id,
            0,
            (d, m) => d.items['l1'] = Item(
              'l1',
              'link',
              50,
              100,
              220,
              48,
              text: 'https://uno.com',
            ),
          );
          await roundTrip(a, b);
          await change(
            b,
            nb.id,
            0,
            (d, m) => d.items['l1']!.text = 'https://dos.com',
          );
          await roundTrip(b, a);
          expect(
            (await contentOf(a, nb.id, 0)).items.single.text,
            'https://dos.com',
          );

          await change(
            a,
            nb.id,
            0,
            (d, m) => d.items['l1']!.text = 'https://de-a.com',
          );
          await change(
            b,
            nb.id,
            0,
            (d, m) => d.items['l1']!.text = 'https://de-b.com',
          );
          await roundTrip(a, b);
          await roundTrip(a, b);
          final all = <String>{};
          for (final s in [a, b]) {
            final nbS = await nbOf(s, nb.id);
            for (var k = 0; k < nbS.sheets.length; k++) {
              all.addAll([
                for (final i in (await contentOf(s, nb.id, k)).items) i.text,
              ]);
            }
          }
          expect(
            all,
            containsAll(['https://de-a.com', 'https://de-b.com']),
            reason: 'ninguna de las dos ediciones se puede perder',
          );
        });
      });

      group('formas exactas', () {
        test('una forma con relleno llega con los mismos puntos, color, grosor y relleno', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Formas', n: 1);
          final cuadrado = <double>[
            100.0,
            100,
            .5,
            300,
            100,
            .5,
            300,
            300,
            .5,
            100,
            300,
            .5,
            100,
            100,
            .5,
          ];
          await change(a, nb.id, 0, (d, m) {
            d.strokes['f1'] = Stroke(
              'f1',
              'pen',
              '#1d4ed8',
              3.2,
              cuadrado,
              1,
              null,
              '#fde68a',
            );
            d.strokes['f2'] = Stroke('f2', 'pen', '#b91c1c', 2.6, [
              400,
              100,
              .5,
              600,
              250,
              .5,
            ], 1);
          });
          await roundTrip(a, b);
          final ca = await contentOf(a, nb.id, 0),
              cb = await contentOf(b, nb.id, 0);
          expect(strokesJson(cb), strokesJson(ca));
          final f1 = cb.strokes.firstWhere((s) => s.id == 'f1');
          expect([f1.fill, f1.c, f1.w], ['#fde68a', '#1d4ed8', 3.2]);
          // (la presión se guarda en 1/255: se comparan las coordenadas)
          List<double> xy(List<double> p) => [
            for (var i = 0; i < p.length; i += 3) ...[p[i], p[i + 1]],
          ];
          expect(xy(f1.pts), xy(cuadrado));
          expect(cb.strokes.firstWhere((s) => s.id == 'f2').fill, isNull);
          // B le cambia el relleno (stroke inmutable: lo reemplaza)
          await change(
            b,
            nb.id,
            0,
            (d, m) => d.strokes['f1'] = Stroke(
              'f1',
              'pen',
              '#1d4ed8',
              3.2,
              cuadrado,
              1,
              null,
              '#bbf7d0',
            ),
          );
          await roundTrip(b, a);
          expect(
            (await contentOf(
              a,
              nb.id,
              0,
            )).strokes.firstWhere((s) => s.id == 'f1').fill,
            '#bbf7d0',
          );
        });

        test('dos formas distintas dibujadas en la misma hoja sin sincronizar: no se pierde ninguna', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'Formas', n: 1);
          await roundTrip(a, b);
          await change(
            a,
            nb.id,
            0,
            (d, m) => d.strokes['fa'] = Stroke(
              'fa',
              'pen',
              '#111111',
              2,
              [10, 10, .5, 50, 50, .5],
              1,
              null,
              '#ff0000',
            ),
          );
          await change(
            b,
            nb.id,
            0,
            (d, m) => d.strokes['fb'] = Stroke(
              'fb',
              'pen',
              '#222222',
              2,
              [70, 70, .5, 90, 90, .5],
              1,
              null,
              '#00ff00',
            ),
          );
          await roundTrip(a, b);
          await roundTrip(a, b);
          for (final s in [a, b]) {
            // la hoja "(conflicto)" tiene ids nuevos: se reconoce cada forma por su relleno
            final fills = <String?>[];
            final nbS = await nbOf(s, nb.id);
            for (var k = 0; k < nbS.sheets.length; k++) {
              fills.addAll([
                for (final x in (await contentOf(s, nb.id, k)).strokes) x.fill,
              ]);
            }
            expect(fills, containsAll(['#ff0000', '#00ff00']));
          }
        });
      });

      group('lienzo infinito', () {
        test(
          'sigue siendo lienzo, con su ancho, y el contenido lejos llega igual',
          () async {
            final a = await device(), b = await device();
            final nb = await create(a, 'Lienzo', n: 1, canvas: true);
            nb.canvasW = 4500;
            final idx = await a.loadIndex();
            idx.notebooks.firstWhere((n) => n.id == nb.id).canvasW = 4500;
            await a.saveIndex(idx);
            await change(a, nb.id, 0, (d, m) {
              d.texts['lejos'] = TextBlock(
                'lejos',
                4200,
                5200,
                300,
                'lejos a la derecha y abajo',
              );
              d.strokes['sl'] = Stroke('sl', 'pen', '#22211e', 2.6, [
                4000,
                6000,
                .5,
                4300,
                6100,
                .5,
              ]);
              d.items['il'] = Item(
                'il',
                'link',
                3900,
                7000,
                220,
                48,
                text: 'https://example.com',
              );
            });
            await roundTrip(a, b);
            final nbb = await nbOf(b, nb.id);
            expect(nbb.canvas, isTrue);
            expect(nbb.canvasW, 4500);
            expect(nbb.sheets, hasLength(1));
            final ca = await contentOf(a, nb.id, 0),
                cb = await contentOf(b, nb.id, 0);
            expect(strokesJson(cb), strokesJson(ca));
            expect(itemsJson(cb), itemsJson(ca));
            final t = cb.texts.firstWhere((t) => t.id == 'lejos');
            expect(
              [t.x, t.y, t.text],
              [4200, 5200, 'lejos a la derecha y abajo'],
            );
            // B lo agranda y vuelve
            final idxB = await b.loadIndex();
            idxB.notebooks.firstWhere((n) => n.id == nb.id).canvasW = 6000;
            await change(
              b,
              nb.id,
              0,
              (d, m) => d.texts['lejos2'] = TextBlock(
                'lejos2',
                5800,
                100,
                200,
                'otro',
              ),
            );
            await b.saveIndex(idxB);
            await roundTrip(b, a);
            final nba = await nbOf(a, nb.id);
            expect(nba.canvas, isTrue);
            expect(
              (await contentOf(a, nb.id, 0)).texts.map((e) => e.id),
              containsAll(['lejos', 'lejos2']),
            );
          },
        );
      });

      group('páginas de PDF importadas', () {
        test('el item pdf y su archivo llegan; sigue siendo pdf con la misma página', () async {
          final a = await device(), b = await device();
          final nb = await create(a, 'PDF', n: 2);
          final pdf = await a.addMedia(pdfBytes, 'pdf');
          for (var k = 0; k < 2; k++) {
            await change(
              a,
              nb.id,
              k,
              (d, m) => d.items['pg$k'] = Item(
                'pg$k',
                'pdf',
                0,
                k * kSheetStep.toDouble(),
                794,
                1123,
                file: pdf,
                page: k,
              ),
            );
          }
          await roundTrip(a, b);
          expect(remote.has('media/$pdf'), isTrue);
          for (var k = 0; k < 2; k++) {
            final it = (await contentOf(b, nb.id, k)).items.single;
            expect(
              [it.type, it.file, it.page, it.w, it.h],
              ['pdf', pdf, k, 794.0, 1123.0],
            );
          }
          expect(b.media(pdf).readAsBytesSync(), pdfBytes);
        });
      });
    });
  }
}
