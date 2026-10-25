r"""W4 计划前置探针：Windows 自带 SQLite 能不能承担向量库与关键词索引。

回答三个问题，答案写进 `W04_task_plan.md` 的决策 1：
1. `C:\Windows\System32\winsqlite3.dll` 的版本，以及 FTS5 / JSON1 / WAL 是否可用；
2. `tokenize='trigram'` 与默认 `unicode61` 对中文的实际行为差异；
3. 384 维暴力余弦在 1.5k / 10k 块上的耗时。

用法（仓库根目录）：
    engine\.venv\Scripts\python.exe week4\probes\probe_sqlite_capacity.py
"""

from __future__ import annotations

import ctypes
import time

DLL = r"C:\Windows\System32\winsqlite3.dll"

lib = ctypes.CDLL(DLL)
lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
lib.sqlite3_open.restype = ctypes.c_int
lib.sqlite3_prepare_v2.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_int,
    ctypes.POINTER(ctypes.c_void_p),
    ctypes.POINTER(ctypes.c_char_p),
]
lib.sqlite3_prepare_v2.restype = ctypes.c_int
lib.sqlite3_step.argtypes = [ctypes.c_void_p]
lib.sqlite3_step.restype = ctypes.c_int
lib.sqlite3_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.sqlite3_column_text.restype = ctypes.c_char_p
lib.sqlite3_column_count.argtypes = [ctypes.c_void_p]
lib.sqlite3_column_count.restype = ctypes.c_int
lib.sqlite3_finalize.argtypes = [ctypes.c_void_p]
lib.sqlite3_errmsg.argtypes = [ctypes.c_void_p]
lib.sqlite3_errmsg.restype = ctypes.c_char_p
lib.sqlite3_close.argtypes = [ctypes.c_void_p]


def run(handle: ctypes.c_void_p, sql: str) -> tuple[int, str, list[list[str]]]:
    stmt = ctypes.c_void_p()
    tail = ctypes.c_char_p()
    code = lib.sqlite3_prepare_v2(
        handle, sql.encode("utf-8"), -1, ctypes.byref(stmt), ctypes.byref(tail)
    )
    if code != 0:
        return code, lib.sqlite3_errmsg(handle).decode("utf-8", "replace"), []
    rows: list[list[str]] = []
    try:
        while True:
            step = lib.sqlite3_step(stmt)
            if step == 100:
                rows.append(
                    [
                        (lib.sqlite3_column_text(stmt, i) or b"").decode("utf-8", "replace")
                        for i in range(lib.sqlite3_column_count(stmt))
                    ]
                )
            elif step == 101:
                break
            else:
                return step, lib.sqlite3_errmsg(handle).decode("utf-8", "replace"), rows
    finally:
        lib.sqlite3_finalize(stmt)
    return 0, "ok", rows


def main() -> int:
    handle = ctypes.c_void_p()
    open_code = lib.sqlite3_open(b":memory:", ctypes.byref(handle))
    print(f"probe=sqlite_capacity dll={DLL} open_rc={open_code}")

    for label, sql in (
        ("version", "select sqlite_version()"),
        ("source_id", "select sqlite_source_id()"),
        ("json1", "select json_extract('{\"a\":1}', '$.a')"),
        ("fts5", "create virtual table f5 using fts5(body)"),
        ("fts4", "create virtual table f4 using fts4(body)"),
        ("trigram", "create virtual table tg using fts5(body, tokenize='trigram')"),
    ):
        code, message, rows = run(handle, sql)
        print(f"capability {label}: rc={code} {message} rows={rows}")

    # 中文分词行为：同一句放进两个虚表，用同一条查询对比命中。
    doc = "离线检索可以在没有网络的电脑上运行。键盘操作必须能走完整个流程。"
    for table in ("f5", "tg"):
        run(handle, f"insert into {table}(body) values ('{doc}')")
    run(handle, "create virtual table f5v using fts5vocab(f5, 'row')")
    code, message, rows = run(handle, "select term, cnt from f5v")
    print(f"unicode61_vocab: rc={code} rows={rows}")

    for token in ("离线", "离线检索", "键盘", "整个流程", "电脑上"):
        _, _, uni = run(handle, f"select count(*) from f5 where body match '{token}'")
        _, _, tri = run(handle, f"select count(*) from tg where body match '{token}'")
        _, _, like = run(handle, f"select count(*) from f5 where body like '%{token}%'")
        print(
            f"probe '{token}' unicode61={uni[0][0]} trigram={tri[0][0]} like={like[0][0]}"
        )

    # 384 维暴力余弦的规模曲线。numpy 只负责生成数据与计时，产品实现是 Dart。
    import numpy as np

    for n in (1500, 10000):
        rng = np.random.default_rng(11)
        matrix = rng.standard_normal((n, 384)).astype(np.float32)
        query = rng.standard_normal(384).astype(np.float32)
        _ = matrix @ query  # warmup：第一条 1.5k 计时会被首次 BLAS 线程池创建污染
        samples = []
        for _ in range(5):
            started = time.perf_counter()
            _scores = matrix @ query
            samples.append((time.perf_counter() - started) * 1000)
        samples.sort()
        print(
            f"bruteforce n={n} dim=384 dots_ms_median={samples[2]:.1f} "
            f"min={samples[0]:.1f} max={samples[-1]:.1f}"
        )

    code, message, rows = run(handle, "pragma journal_mode=wal")
    print(f"journal_mode(memory_db): rc={code} rows={rows}")

    lib.sqlite3_close(handle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
