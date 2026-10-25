// W4 存储路线探针。三个数字决定决策 1：写入耗时、暴力余弦耗时、FTS5 中文行为。
//
// 用法（week4/probes/dart_store_probe 下）：
//   dart pub get
//   dart run bin/probe.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

const int _dim = 384;

void main() {
  print('sqlite_version=${sqlite3.version.libVersion}');
  print('source=${sqlite3.version.sourceId}');

  final Directory tmp = Directory.systemTemp.createTempSync('w4_store_probe_');
  final Database db = sqlite3.open('${tmp.path}/probe.sqlite');
  db.execute('pragma journal_mode=wal');
  print('journal_mode=${db.select('pragma journal_mode').first.values.first}');

  // 1. 中文分词：unicode61 把整段中文当一个 token，trigram 按三字窗口。
  db.execute('create virtual table uni using fts5(body)');
  db.execute("create virtual table tri using fts5(body, tokenize='trigram')");
  const String doc = '离线检索可以在没有网络的电脑上运行。键盘操作必须能走完整个流程。';
  db.execute("insert into uni(body) values (?)", <Object?>[doc]);
  db.execute("insert into tri(body) values (?)", <Object?>[doc]);
  for (final String token in <String>['离线', '离线检索', '键盘', '整个流程']) {
    final int u = db
        .select("select count(*) c from uni where body match ?", <Object?>[token])
        .first['c'] as int;
    final int t = db
        .select("select count(*) c from tri where body match ?", <Object?>[token])
        .first['c'] as int;
    final int l = db
        .select('select count(*) c from uni where body like ?', <Object?>['%$token%'])
        .first['c'] as int;
    print('token=$token unicode61=$u trigram=$t like=$l');
  }

  // 2. 索引写入与暴力余弦的规模曲线。向量按 fp32 小端 BLOB 存。
  db.execute('create table chunk(id text primary key, vec blob)');
  for (final int n in <int>[1500, 10000]) {
    db.execute('delete from chunk');
    final Random rng = Random(11);
    final Stopwatch write = Stopwatch()..start();
    db.execute('begin');
    final PreparedStatement ins = db.prepare('insert into chunk values (?, ?)');
    for (var i = 0; i < n; i++) {
      final Float32List vector = Float32List(_dim);
      for (var d = 0; d < _dim; d++) {
        vector[d] = rng.nextDouble() * 2 - 1;
      }
      ins.execute(<Object?>['c$i', vector.buffer.asUint8List()]);
    }
    ins.dispose();
    db.execute('commit');
    write.stop();

    final Float32List query = Float32List(_dim);
    for (var d = 0; d < _dim; d++) {
      query[d] = rng.nextDouble() * 2 - 1;
    }
    final ResultSet rows = db.select('select id, vec from chunk');
    final List<double> samples = <double>[];
    for (var repeat = 0; repeat < 3; repeat++) {
      final Stopwatch scan = Stopwatch()..start();
      var best = -2.0;
      for (final Row row in rows) {
        final Uint8List raw = row['vec'] as Uint8List;
        final Float32List vector = raw.buffer.asFloat32List(raw.offsetInBytes, _dim);
        var dot = 0.0;
        for (var d = 0; d < _dim; d++) {
          dot += vector[d] * query[d];
        }
        if (dot > best) {
          best = dot;
        }
      }
      scan.stop();
      samples.add(scan.elapsedMicroseconds / 1000);
    }
    samples.sort();
    print(
      'n=$n write_ms=${write.elapsedMilliseconds} '
      'scan_ms_median=${samples[1].toStringAsFixed(1)} '
      'min=${samples.first.toStringAsFixed(1)} max=${samples.last.toStringAsFixed(1)}',
    );
  }

  db.dispose();
  tmp.deleteSync(recursive: true);
}
