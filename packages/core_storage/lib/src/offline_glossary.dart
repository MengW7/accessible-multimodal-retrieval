/// 固定的离线视觉词表。不是分词器，也不读取证据句。
///
/// [clipQueryText] 只在命中词表时改写送给 MobileCLIP 文本塔的字符串。
/// [keywordTrigramProbes] 给已经切出中文 bigram 的查询补 trigram 探针。
/// 整句中文不会出现在探针里。未命中的问句保持原样。
const Map<String, String> _glosses = <String, String>{
  '人': 'person',
  '男人': 'man',
  '女人': 'woman',
  '孩子': 'child',
  '婴儿': 'baby',
  '人群': 'crowd',
  '红色': 'red',
  '蓝色': 'blue',
  '绿色': 'green',
  '黄色': 'yellow',
  '黑色': 'black',
  '白色': 'white',
  '灰色': 'gray',
  '棕色': 'brown',
  '粉色': 'pink',
  '紫色': 'purple',
  '橙色': 'orange',
  '厨房': 'kitchen',
  '浴室': 'bathroom',
  '卧室': 'bedroom',
  '客厅': 'living',
  '卫生间': 'toilet',
  '阳台': 'balcony',
  '办公室': 'office',
  '教室': 'classroom',
  '商店': 'shop',
  '超市': 'supermarket',
  '餐厅': 'restaurant',
  '街道': 'street',
  '马路': 'road',
  '人行道': 'sidewalk',
  '路边': 'roadside',
  '公园': 'park',
  '海滩': 'beach',
  '沙滩': 'beach',
  '山上': 'mountain',
  '河边': 'river',
  '湖边': 'lake',
  '海边': 'sea',
  '机场': 'airport',
  '跑道': 'runway',
  '车站': 'station',
  '房间': 'room',
  '室内': 'indoor',
  '室外': 'outdoor',
  '墙壁': 'wall',
  '墙': 'wall',
  '大门': 'door',
  '窗户': 'window',
  '地板': 'floor',
  '天花板': 'ceiling',
  '自行车': 'bicycle',
  '汽车': 'car',
  '轿车': 'car',
  '公交车': 'bus',
  '火车': 'train',
  '飞机': 'airplane',
  '客机': 'airliner',
  '轮船': 'ship',
  '小船': 'boat',
  '船': 'boat',
  '卡车': 'truck',
  '摩托车': 'motorcycle',
  '车': 'car',
  '披萨': 'pizza',
  '面包': 'bread',
  '蛋糕': 'cake',
  '苹果': 'apple',
  '香蕉': 'banana',
  '米饭': 'rice',
  '咖啡': 'coffee',
  '杯子': 'cup',
  '瓶子': 'bottle',
  '小狗': 'dog',
  '小猫': 'cat',
  '狗': 'dog',
  '猫': 'cat',
  '鸟': 'bird',
  '马': 'horse',
  '牛': 'cow',
  '山羊': 'goat',
  '羊': 'sheep',
  '桌子': 'table',
  '椅子': 'chair',
  '沙发': 'sofa',
  '床': 'bed',
  '书': 'book',
  '电脑': 'computer',
  '手机': 'phone',
  '书包': 'backpack',
  '帽子': 'hat',
  '鞋子': 'shoe',
  '花朵': 'flower',
  '树木': 'tree',
  '树': 'tree',
  '草地': 'grass',
  '足球': 'ball',
  '时钟': 'clock',
  '台灯': 'lamp',
  '淋浴': 'shower',
  '花洒': 'shower',
  '水槽': 'sink',
  '镜子': 'mirror',
  '毛巾': 'towel',
  '长椅': 'bench',
  '水面': 'water',
  '桶': 'bucket',
  '楼': 'building',
  '文档': 'document',
  '标题': 'title',
  '页面': 'page',
  '文字': 'text',
  '图片': 'picture',
  '版面': 'layout',
  '坐着': 'sitting',
  '站着': 'standing',
  '走着': 'walking',
  '吃着': 'eating',
  '做饭': 'cooking',
  '骑着': 'riding',
  '停着': 'parked',
  '停在': 'parked',
  '破损': 'broken',
  '破的': 'broken',
  '大型': 'large',
  '小型': 'small',
  '顶部': 'top',
  '一群': 'group',
};

final List<MapEntry<String, String>> _keysLongestFirst = () {
  final List<MapEntry<String, String>> entries = _glosses.entries.toList(
    growable: false,
  );
  entries.sort((MapEntry<String, String> left, MapEntry<String, String> right) {
    final int length = right.key.length.compareTo(left.key.length);
    if (length != 0) {
      return length;
    }
    return left.key.compareTo(right.key);
  });
  return entries;
}();

class _Piece {
  const _Piece(this.text, {required this.gloss});

  final String text;

  final bool gloss;
}

/// 问句里命中的英文词，从左到右，同一英文词只留第一次。
List<String> offlineGlosses(String query) {
  return _unique(<String>[
    for (final _Piece piece in _pieces(query))
      if (piece.gloss) piece.text,
  ]);
}

/// 问句里连续的拉丁字母，长度至少 3。中文不算。
List<String> latinSpans(String query) {
  return _unique(<String>[
    for (final _Piece piece in _pieces(query))
      if (!piece.gloss) piece.text,
  ]);
}

/// bigram 查询额外送给 trigram 的字符串。拉丁串和英文词都要不少于 3 个字符。
List<String> keywordTrigramProbes(String query) {
  return _unique(<String>[
    for (final _Piece piece in _pieces(query))
      if (piece.text.length >= 3) piece.text,
  ]);
}

/// 送给 MobileCLIP 文本塔的字符串。没有命中词表时返回原问句。
String clipQueryText(String query) {
  final List<_Piece> pieces = _pieces(query);
  var hasGloss = false;
  for (final _Piece piece in pieces) {
    if (piece.gloss) {
      hasGloss = true;
      break;
    }
  }
  if (!hasGloss) {
    return query;
  }
  return _unique(<String>[for (final _Piece piece in pieces) piece.text])
      .join(' ');
}

List<String> _unique(List<String> words) {
  final List<String> unique = <String>[];
  final Set<String> seen = <String>{};
  for (final String word in words) {
    if (seen.add(word)) {
      unique.add(word);
    }
  }
  return unique;
}

List<_Piece> _pieces(String query) {
  final List<_Piece> pieces = <_Piece>[];
  var index = 0;
  while (index < query.length) {
    MapEntry<String, String>? match;
    for (final MapEntry<String, String> entry in _keysLongestFirst) {
      if (query.startsWith(entry.key, index)) {
        match = entry;
        break;
      }
    }
    if (match != null) {
      pieces.add(_Piece(match.value, gloss: true));
      index += match.key.length;
      continue;
    }
    final int start = index;
    while (index < query.length && _isLatinLetter(query.codeUnitAt(index))) {
      index += 1;
    }
    if (index > start) {
      final String word = query.substring(start, index);
      if (word.length >= 3) {
        pieces.add(_Piece(word, gloss: false));
      }
      continue;
    }
    index += 1;
  }
  return pieces;
}

bool _isLatinLetter(int unit) {
  return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
}
