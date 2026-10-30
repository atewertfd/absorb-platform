import 'dart:ui' as ui;

import 'package:absorb/utils/smooth_wheel_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(microseconds: 16667);

ui.PointerData _wheel(double dy, {double x = 100, double y = 100}) =>
    ui.PointerData(
      change: ui.PointerChange.hover,
      kind: ui.PointerDeviceKind.mouse,
      signalKind: ui.PointerSignalKind.scroll,
      physicalX: x,
      physicalY: y,
      scrollDeltaY: dy,
    );

ui.PointerDataPacket _packet(List<ui.PointerData> data) =>
    ui.PointerDataPacket(data: data);

void main() {
  late List<ui.PointerDataPacket> sent;
  late int activations;
  late SmoothWheelScroll smoother;

  setUp(() {
    sent = [];
    activations = 0;
    smoother = SmoothWheelScroll(
      emit: sent.add,
      onActive: () => activations++,
    );
  });

  double sentY() => sent
      .expand((p) => p.data)
      .where(SmoothWheelScroll.isMouseWheel)
      .fold(0.0, (sum, d) => sum + d.scrollDeltaY);

  test('non-wheel input passes through untouched', () {
    final move = _packet(const [
      ui.PointerData(
        change: ui.PointerChange.hover,
        kind: ui.PointerDeviceKind.mouse,
      ),
    ]);
    final trackpad = _packet(const [
      ui.PointerData(
        change: ui.PointerChange.panZoomUpdate,
        kind: ui.PointerDeviceKind.trackpad,
        panDeltaY: 20,
      ),
    ]);
    smoother.handlePacket(move);
    smoother.handlePacket(trackpad);
    expect(sent, [move, trackpad]);
    expect(activations, 0);
  });

  test('wheel events it is told not to smooth pass through as plain jumps',
      () {
    var enabled = false;
    final s = SmoothWheelScroll(
      emit: sent.add,
      onActive: () => activations++,
      shouldSmooth: (_) => enabled,
    );
    final notch = _packet([_wheel(120)]);
    s.handlePacket(notch);
    expect(sent, [notch]);
    expect(s.isActive, isFalse);

    enabled = true;
    s.handlePacket(_packet([_wheel(120)]));
    expect(sent, hasLength(1));
    expect(s.isActive, isTrue);
  });

  test('a wheel notch is spread over frames and adds up exactly', () {
    smoother.handlePacket(_packet([_wheel(120)]));
    expect(sent, isEmpty);
    expect(activations, 1);

    smoother.tick(_frame);
    final first = sentY();
    expect(first, greaterThan(0));
    expect(first, lessThan(120));

    var frames = 1;
    while (smoother.tick(_frame)) {
      frames++;
    }
    expect(sentY(), closeTo(120, 1e-9));
    expect(frames, inInclusiveRange(5, 30));
  });

  test('a steadily turning wheel scrolls at an even speed', () {
    // A real mouse measured on a 165 Hz monitor: 100 px notches every 65 ms.
    const frame = Duration(microseconds: 6061);
    final steps = <double>[];
    var sinceNotch = const Duration(milliseconds: 65);
    for (var i = 0; i < 165; i++) {
      if (sinceNotch >= const Duration(milliseconds: 65) && i < 120) {
        smoother.handlePacket(_packet([_wheel(100)]));
        sinceNotch = Duration.zero;
      }
      final before = sentY();
      smoother.tick(frame);
      steps.add(sentY() - before);
      sinceNotch += frame;
    }
    final spinning = steps.sublist(60, 115);
    final fastest = spinning.reduce((a, b) => a > b ? a : b);
    final slowest = spinning.reduce((a, b) => a < b ? a : b);
    // The old ease-out pulsed 4.7x per notch; the spring stays near even.
    expect(fastest / slowest, lessThan(1.6));
  });

  test('other input in the same packet keeps its place', () {
    const click = ui.PointerData(
      change: ui.PointerChange.down,
      kind: ui.PointerDeviceKind.mouse,
      buttons: 1,
    );
    smoother.handlePacket(_packet([click, _wheel(60)]));
    expect(sent, hasLength(1));
    expect(sent.single.data.single.change, ui.PointerChange.down);
  });

  test('turning the wheel back cancels the old motion', () {
    smoother.handlePacket(_packet([_wheel(120)]));
    smoother.tick(_frame);
    final before = sentY();
    smoother.handlePacket(_packet([_wheel(-120)]));
    while (smoother.tick(_frame)) {}
    expect(sentY(), closeTo(before - 120, 1e-9));
  });

  test('moving the pointer away finishes the old motion where it was', () {
    smoother.handlePacket(_packet([_wheel(120, x: 100, y: 100)]));
    smoother.tick(_frame);
    smoother.handlePacket(_packet([_wheel(40, x: 600, y: 600)]));
    final atOld = sent
        .expand((p) => p.data)
        .where((d) => d.physicalX == 100)
        .fold(0.0, (sum, d) => sum + d.scrollDeltaY);
    expect(atOld, closeTo(120, 1e-9));
    while (smoother.tick(_frame)) {}
    expect(sentY(), closeTo(160, 1e-9));
  });

  testWidgets('wheel input over a native texture (WebView) is detected',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        SizedBox(width: 200, height: 200, child: Texture(textureId: 1)),
        SizedBox(width: 200, height: 200, child: Text('list')),
      ]),
    ));
    final ratio = tester.view.devicePixelRatio;
    ui.PointerData at(Offset p) => ui.PointerData(
          viewId: tester.view.viewId,
          kind: ui.PointerDeviceKind.mouse,
          signalKind: ui.PointerSignalKind.scroll,
          physicalX: p.dx * ratio,
          physicalY: p.dy * ratio,
          scrollDeltaY: 120,
        );
    expect(isOverTexture(at(tester.getCenter(find.byType(Texture)))), isTrue);
    expect(isOverTexture(at(tester.getCenter(find.text('list')))), isFalse);
  });

  testWidgets('a list glides to the same place a plain wheel jump reaches',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView.builder(
        controller: controller,
        itemExtent: 50,
        itemCount: 200,
        itemBuilder: (_, i) => Text('item $i'),
      ),
    ));
    final dispatch = tester.binding.platformDispatcher.onPointerDataPacket!;
    final view = tester.view;
    final center = tester.getCenter(find.byType(ListView));
    final s = SmoothWheelScroll(emit: dispatch, onActive: () {});

    // 300 physical px is 100 logical px at the test view's pixel ratio.
    final physical = 100 * view.devicePixelRatio;
    s.handlePacket(_packet([
      ui.PointerData(
        viewId: view.viewId,
        change: ui.PointerChange.hover,
        kind: ui.PointerDeviceKind.mouse,
        signalKind: ui.PointerSignalKind.scroll,
        physicalX: center.dx * view.devicePixelRatio,
        physicalY: center.dy * view.devicePixelRatio,
        scrollDeltaY: physical,
      ),
    ]));
    await tester.pump();
    expect(controller.offset, 0);

    s.tick(_frame);
    await tester.pump(_frame);
    final firstFrame = controller.offset;
    expect(firstFrame, greaterThan(0));
    expect(firstFrame, lessThan(100));

    while (s.tick(_frame)) {
      await tester.pump(_frame);
    }
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(100, 0.01));
  });
}
