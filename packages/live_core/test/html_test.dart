import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('elements, attributes in any order and quoting, classes and text', () {
    final root = HtmlElement.parseFragment(
      [
        '<div class="card a" data-log=\'{"id":1,"t":"a > b"}\' id=x>',
        '<IMG src="//img.example/a.jpg" CLASS="avatar"/>',
        "<span class='name'>Fixture &amp; live&ensp;粉丝</span>",
        '<!-- <span class="name">comment</span> -->',
        '<br>text</div>',
      ].join(),
    );
    final card = root.children.single;
    expect(card.tag, 'div');
    expect(card.attributes, {'class': 'card a', 'data-log': '{"id":1,"t":"a > b"}', 'id': 'x'});
    expect(card.classes, {'card', 'a'});
    expect(card.query((e) => e.tag == 'img')!.attributes['src'], '//img.example/a.jpg');
    expect(card.query((e) => e.hasClass('avatar'))!.tag, 'img', reason: 'names are case-insensitive');
    expect(card.queryAll((e) => e.hasClass('name')).single.text, 'Fixture & live\u2002粉丝');
    expect(card.text, 'Fixture & live\u2002粉丝text');
    expect(card.query((e) => e.tag == 'span')!.ancestors, [card, root]);
  });

  test('stray and missing end tags, raw text and a lone "<" are tolerated', () {
    final root = HtmlElement.parseFragment('<p>a</b>b<ul><li>1<li>2</ul><script>if (a < b) "</p>"</script>1 < 2');
    final p = root.children.single;
    expect(p.tag, 'p', reason: 'a stray end tag closes nothing; an unclosed element ends with the fragment');
    expect(p.query((e) => e.tag == 'script')!.text, 'if (a < b) "</p>"');
    // No implied end tags: the second item opens inside the first.
    expect(p.queryAll((e) => e.tag == 'li').map((e) => e.text), ['12', '2']);
    expect(root.text, 'ab12if (a < b) "</p>"1 < 2');
  });

  test('the first of a repeated attribute wins; values without quotes end at a space', () {
    final element = HtmlElement.parseFragment('<a href=/u/1 href="/u/2" title=x&amp;y data-on>').children.single;
    expect(element.attributes, {'href': '/u/1', 'title': 'x&y', 'data-on': ''});
  });
}
