import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/utils/performance_policy.dart';

void main() {
  testWidgets('disables tickers for inactive surfaces', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: withActiveSurfaceTickers(
          active: false,
          child: Builder(
            builder: (context) => Text('${TickerMode.of(context)}'),
          ),
        ),
      ),
    );

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets('keeps tickers enabled for the active surface', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: withActiveSurfaceTickers(
          active: true,
          child: Builder(
            builder: (context) => Text('${TickerMode.of(context)}'),
          ),
        ),
      ),
    );

    expect(find.text('true'), findsOneWidget);
  });
}
