import 'package:apuntes/editor/wheel_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wheelZoomFactor: arriba agranda, abajo achica, quieta no cambia y es simétrico', () {
    expect(wheelZoomFactor(-53), greaterThan(1));
    expect(wheelZoomFactor(53), lessThan(1));
    expect(wheelZoomFactor(0), 1);
    expect(wheelZoomFactor(53) * wheelZoomFactor(-53), closeTo(1, 1e-9));
  });
}
