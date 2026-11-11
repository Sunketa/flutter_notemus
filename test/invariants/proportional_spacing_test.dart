// test/invariants/proportional_spacing_test.dart
//
// `GrandStaffPainter.proportionalSpacing` spaces each system's notes in
// proportion to musical time, so that a playhead moving at one constant speed
// arrives at every note as it starts to sound. Engraved spacing grows
// sub-linearly with duration (a half gets far less than twice a quarter's
// room), so a playhead that follows engraved notes changes speed at every
// note of a different length.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_notemus/flutter_notemus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SmuflMetadata metadata;
  setUpAll(() async {
    metadata = SmuflMetadata();
    await metadata.load();
  });

  const ss = 12.0;

  Note n(String s, int o, DurationType d) =>
      Note(pitch: Pitch(step: s, octave: o), duration: MusicDuration(d));

  Measure bar(List<MusicalElement> body, {bool first = false, ClefType clef = ClefType.treble}) => Measure()
    ..elements.addAll([
      if (first) Clef(clefType: clef),
      if (first) TimeSignature(numerator: 4, denominator: 4),
      ...body,
    ]);

  GrandStaffPainter paint(List<Measure> treble, List<Measure> bass,
          {required bool proportional, double width = 1100}) =>
      GrandStaffPainter(
        staffGroup: StaffGroup(bracket: BracketType.brace, staves: [
          Staff(measures: treble),
          Staff(measures: bass),
        ]),
        staffSpace: ss,
        metadata: metadata,
        availableWidth: width,
        theme: const MusicScoreTheme(),
        proportionalSpacing: proportional,
      );

  List<double> noteXs(GrandStaffPainter p, int staff, {int system = 0}) => [
        for (final e in p.alignedSystem(system)[staff])
          if (e.element is Note) e.position.dx,
      ];

  List<double> barlineXs(GrandStaffPainter p, int staff) => [
        for (final e in p.alignedSystem(0)[staff])
          if (e.element is Barline) e.position.dx,
      ];

  // Treble: half, eighth, eighth, quarter | four quarters.
  // Bass: a whole | a half and two quarters.
  List<Measure> treble() => [
        bar(first: true, [
          n('C', 5, DurationType.half),
          n('D', 5, DurationType.eighth),
          n('E', 5, DurationType.eighth),
          n('F', 5, DurationType.quarter),
        ]),
        bar([
          n('G', 5, DurationType.quarter),
          n('A', 5, DurationType.quarter),
          n('B', 5, DurationType.quarter),
          n('C', 6, DurationType.quarter),
        ]),
      ];
  List<Measure> bass() => [
        bar(first: true, clef: ClefType.bass, [n('C', 3, DurationType.whole)]),
        bar([
          n('G', 2, DurationType.half),
          n('A', 2, DurationType.quarter),
          n('B', 2, DurationType.quarter),
        ]),
      ];

  test('notes sit at x proportional to onset, across the barline too', () {
    final p = paint(treble(), bass(), proportional: true);
    final xs = noteXs(p, 0);
    // Onsets in whole notes: 0, 1/2, 5/8, 3/4 | 1, 5/4, 3/2, 7/4.
    const onsets = [0.0, 0.5, 0.625, 0.75, 1.0, 1.25, 1.5, 1.75];
    expect(xs.length, onsets.length);
    final rate = (xs.last - xs.first) / (onsets.last - onsets.first);
    for (var i = 0; i < xs.length; i++) {
      expect(xs[i], closeTo(xs.first + onsets[i] * rate, 0.01), reason: 'note $i');
    }
  });

  test('the barline sits between the last note of its bar and the next note', () {
    final p = paint(treble(), bass(), proportional: true);
    final xs = noteXs(p, 0);
    final barline = barlineXs(p, 0).first;
    expect(barline, greaterThan(xs[3]));
    expect(barline, lessThan(xs[4]));
  });

  test('staves still share an x at every common onset', () {
    final p = paint(treble(), bass(), proportional: true);
    final top = noteXs(p, 0);
    final bottom = noteXs(p, 1);
    // Bass onsets 0 | 1, 3/2, 7/4 meet treble notes 0, 4, 6, 7. (Engraved
    // alignment anchors the barline here instead, which leaves the two
    // downbeats apart.)
    expect(bottom[0], closeTo(top[0], 0.01));
    expect(bottom[1], closeTo(top[4], 0.01));
    expect(bottom[2], closeTo(top[6], 0.01));
    expect(bottom[3], closeTo(top[7], 0.01));
  });

  test('the system keeps its engraved width', () {
    final on = paint(treble(), bass(), proportional: true);
    final off = paint(treble(), bass(), proportional: false);
    expect(noteXs(on, 0).first, closeTo(noteXs(off, 0).first, 0.01));
    expect(barlineXs(on, 0).last, closeTo(barlineXs(off, 0).last, 0.01));
    expect(on.systemCount, off.systemCount);
  });

  test('off by default: engraved spacing is unchanged and sub-linear', () {
    final byDefault = GrandStaffPainter(
      staffGroup: StaffGroup(bracket: BracketType.brace, staves: [
        Staff(measures: treble()),
        Staff(measures: bass()),
      ]),
      staffSpace: ss,
      metadata: metadata,
      availableWidth: 1100,
      theme: const MusicScoreTheme(),
    );
    final off = paint(treble(), bass(), proportional: false);
    expect(noteXs(byDefault, 0), noteXs(off, 0));
    final xs = noteXs(off, 0);
    // The half note's gap is less than twice a quarter's in engraving.
    expect(xs[1] - xs[0], lessThan(2 * (xs[5] - xs[4]) - 1));
  });

  test('a system too dense for one rate keeps engraved spacing', () {
    // A half note then sixteen 32nds, narrow: one rate would give each 32nd a
    // sliver of the half note's room, below the 1.4 staff space note gap.
    List<Measure> dense() => [
          bar(first: true, [
            n('C', 5, DurationType.half),
            for (var i = 0; i < 16; i++) n('D', 5, DurationType.thirtySecond),
          ]),
        ];
    List<Measure> rest() => [bar(first: true, clef: ClefType.bass, [n('C', 3, DurationType.whole)])];
    final on = paint(dense(), rest(), proportional: true, width: 420);
    final off = paint(dense(), rest(), proportional: false, width: 420);
    expect(noteXs(on, 0), noteXs(off, 0));
    expect(barlineXs(on, 0), barlineXs(off, 0));
  });
}
