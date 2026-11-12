// test/invariants/system_breaks_test.dart
//
// A grand staff that wraps is laid out one system at a time, each system as
// its own sub-staff. The layout engine closes the last measure of whatever
// staff it is given with the final (thin-thick) barline, so every wrapped
// system used to end on one. Only the true end of the music may.
//
// `GrandStaffPainter.measuresPerSystem` fixes how many measures each system
// holds instead of packing by width.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_notemus/flutter_notemus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SmuflMetadata metadata;
  setUpAll(() async {
    metadata = SmuflMetadata();
    await metadata.load();
  });

  Measure bar({bool first = false, ClefType clef = ClefType.treble}) =>
      Measure()
        ..elements.addAll([
          if (first) Clef(clefType: clef),
          if (first) TimeSignature(numerator: 4, denominator: 4),
          for (var i = 0; i < 4; i++)
            Note(
              pitch: const Pitch(step: 'C', octave: 4),
              duration: const MusicDuration(DurationType.quarter),
            ),
        ]);

  GrandStaffPainter paint(int bars, {int? perSystem, double width = 1100}) =>
      GrandStaffPainter(
        staffGroup: StaffGroup(bracket: BracketType.brace, staves: [
          Staff(measures: [
            for (var i = 0; i < bars; i++) bar(first: i == 0),
          ]),
          Staff(measures: [
            for (var i = 0; i < bars; i++)
              bar(first: i == 0, clef: ClefType.bass),
          ]),
        ]),
        staffSpace: 12,
        metadata: metadata,
        availableWidth: width,
        theme: const MusicScoreTheme(),
        measuresPerSystem: perSystem,
      );

  /// Barline types of [staff] in [system], left to right.
  List<BarlineType> barlines(GrandStaffPainter p, int system, int staff) => [
        for (final e in p.alignedSystem(system)[staff])
          if (e.element is Barline) (e.element as Barline).type,
      ];

  /// Measures per system, counted from the top staff's barlines.
  List<int> shape(GrandStaffPainter p) => [
        for (var s = 0; s < p.systemCount; s++) barlines(p, s, 0).length,
      ];

  int finals(GrandStaffPainter p, int staff) => [
        for (var s = 0; s < p.systemCount; s++)
          ...barlines(p, s, staff).where((t) => t == BarlineType.final_),
      ].length;

  group('final barline', () {
    test('a width-wrapped piece ends only its last system on one', () {
      final p = paint(12, width: 500);
      expect(p.systemCount, greaterThan(1));
      for (var staff = 0; staff < 2; staff++) {
        expect(finals(p, staff), 1, reason: 'staff $staff');
        for (var s = 0; s < p.systemCount - 1; s++) {
          expect(barlines(p, s, staff).last, BarlineType.single,
              reason: 'system $s staff $staff closes on a plain barline');
        }
        expect(barlines(p, p.systemCount - 1, staff).last, BarlineType.final_);
      }
    });

    test('a one-system piece still ends on one', () {
      final p = paint(2);
      expect(p.systemCount, 1);
      expect(barlines(p, 0, 0).last, BarlineType.final_);
      expect(barlines(p, 0, 1).last, BarlineType.final_);
    });

    test('LayoutEngine keeps it by default and drops it when told to', () {
      final staff = Staff(measures: [bar(first: true), bar()]);
      List<BarlineType> types({bool? finalBarline}) => [
            for (final e in (finalBarline == null
                    ? LayoutEngine(staff,
                        availableWidth: 100000, metadata: metadata)
                    : LayoutEngine(staff,
                        availableWidth: 100000,
                        metadata: metadata,
                        finalBarline: finalBarline))
                .layout())
              if (e.element is Barline) (e.element as Barline).type,
          ];
      expect(types().last, BarlineType.final_);
      expect(types(finalBarline: false),
          [BarlineType.single, BarlineType.single]);
    });
  });

  group('measuresPerSystem', () {
    test('8 bars at 3 per system gives 3, 3, 2', () {
      final p = paint(8, perSystem: 3);
      expect(shape(p), [3, 3, 2]);
      expect(finals(p, 0), 1);
      expect(barlines(p, 2, 0).last, BarlineType.final_);
    });

    test('a count above the piece length gives one system', () {
      final p = paint(8, perSystem: 20, width: 300);
      expect(shape(p), [8]);
      expect(finals(p, 0), 1);
    });

    test('a fixed count ignores the available width', () {
      expect(shape(paint(8, perSystem: 4, width: 200)), [4, 4]);
    });

    test('null, zero and negative fall back to width packing', () {
      final byWidth = shape(paint(12, width: 500));
      expect(byWidth.length, greaterThan(1));
      expect(shape(paint(12, perSystem: 0, width: 500)), byWidth);
      expect(shape(paint(12, perSystem: -2, width: 500)), byWidth);
    });

    test('later systems keep absolute bar numbers and restate the clef', () {
      final p = paint(8, perSystem: 3);
      final second = p.alignedSystem(1)[1];
      expect(second.first.element, isA<Clef>());
      expect((second.first.element as Clef).actualClefType, ClefType.bass);
    });

    test('a changed count repaints', () {
      expect(paint(8, perSystem: 3).shouldRepaint(paint(8, perSystem: 4)),
          isTrue);
    });
  });
}
