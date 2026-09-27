import 'package:flutter_test/flutter_test.dart';
import 'package:wheel_gallery/main.dart';

void main() {
  testWidgets('Gallery page builds', (tester) async {
    await tester.pumpWidget(const WheelGalleryApp());
    expect(find.text('1/${kSampleImages.length}'), findsOneWidget);
  });
}
