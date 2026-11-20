// Los tests de selección con arrastre (test/editor/selection_drag_test.dart), corriendo en la tablet.
//
//   flutter test integration_test/selection_drag_test.dart -d <id de la tablet>

import 'package:integration_test/integration_test.dart';

import '../test/editor/selection_drag_test.dart' as drag;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  drag.main();
}
