import 'dart:async';

import 'package:apuntes/editor/handwriting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SingleFlight: llamadas simultáneas comparten una sola ejecución', () async {
    final sf = SingleFlight<bool>();
    final c = Completer<bool>();
    var calls = 0;
    Future<bool> task() {
      calls++;
      return c.future;
    }

    final a = sf.run(task), b = sf.run(task);
    expect(identical(a, b), isTrue);
    expect(sf.running, isTrue);
    expect(calls, 1);
    c.complete(true);
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(sf.running, isFalse);
  });

  test('SingleFlight: si terminó en false se puede reintentar; también si falló', () async {
    final sf = SingleFlight<bool>();
    var calls = 0;
    expect(await sf.run(() async => ++calls < 0), isFalse);
    expect(sf.running, isFalse);
    expect(await sf.run(() async => ++calls > 0), isTrue);
    expect(calls, 2);
    await expectLater(sf.run(() async => throw StateError('x')), throwsStateError);
    expect(sf.running, isFalse);
    expect(await sf.run(() async => true), isTrue);
  });
}
