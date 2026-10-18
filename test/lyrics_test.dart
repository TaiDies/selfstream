import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/core/api.dart';

void main() {
  test('word timings and the credit line are read when the server sends them', () {
    final l = Api.parseLyrics({
      'structuredLyrics': [
        {
          'synced': true,
          'source': 'Lyrics from Unison',
          'line': [
            {
              'start': 1000,
              'value': 'Never gonna',
              'words': [
                {'start': 1000, 'end': 1500, 'value': 'Never '},
                {'start': 1500, 'end': 2000, 'value': 'gonna'},
              ],
            },
            {'start': 3000, 'value': 'give you up'},
          ],
        }
      ]
    })!;
    expect(l.hasWords, isTrue);
    expect(l.source, 'Lyrics from Unison');
    expect(l.lines[0].words.length, 2);
    expect(l.lines[0].words[1].start, const Duration(milliseconds: 1500));
    expect(l.lines[1].words, isEmpty);
  });

  test('plain line lyrics still work', () {
    final l = Api.parseLyrics({
      'structuredLyrics': [
        {
          'synced': true,
          'line': [
            {'start': 500, 'value': 'hello'}
          ],
        }
      ]
    })!;
    expect(l.hasWords, isFalse);
    expect(l.source, '');
    expect(l.lines.single.text, 'hello');
  });
}
