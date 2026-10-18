import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/core/duplicates.dart';
import 'package:selfstream/core/models.dart';

Song song(int item, String title, {String artist = 'Nirvana'}) =>
    Song({'id': '$item', 'title': title, 'artist': artist, 'playlistItemId': item});

void main() {
  test('version tags are removed from titles', () {
    expect(baseTitle('Dumb (2021 Remaster)'), 'dumb');
    expect(baseTitle('Dumb - Instrumental'), 'dumb');
    expect(baseTitle('Dumb [Live at Reading]'), 'dumb');
    expect(baseTitle('Come As You Are (Remastered) - Radio Edit'), 'come as you are');
    expect(baseTitle('Heart-Shaped Box'), 'heart-shaped box');
    expect(baseTitle('Alive'), 'alive');
    expect(baseTitle('Lithium (feat. Someone)'), 'lithium (feat. someone)');
  });

  test('versions of three songs make three groups with the plain one first', () {
    final songs = [
      song(1, 'Dumb (Instrumental)'), song(2, 'Dumb'), song(3, 'Dumb - 2021 Remaster'),
      song(4, 'Lithium - Instrumental'), song(5, 'Lithium'), song(6, 'Lithium (Live)'),
      song(7, 'Drain You'), song(8, 'Drain You (Remastered)'), song(9, 'Drain You (Acoustic)'),
      song(10, 'Polly'),
    ];
    final groups = findDuplicates(songs);
    expect(groups.length, 3);
    expect(groups.map((g) => g.plain.title), ['Dumb', 'Lithium', 'Drain You']);
    expect(groups.map((g) => g.versions.length), [3, 3, 3]);
  });

  test('the same title by another artist is not a duplicate', () {
    expect(findDuplicates([song(1, 'Hurt'), song(2, 'Hurt', artist: 'Johnny Cash')]), isEmpty);
  });
}
