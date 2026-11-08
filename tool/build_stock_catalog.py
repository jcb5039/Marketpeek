#!/usr/bin/env python3
"""한국투자증권 공개 종목 마스터 파일로 앱 검색용 종목 목록(assets/stocks/*.json)을 만든다.

    python3 tool/build_stock_catalog.py            # 마스터 파일을 내려받아서 생성
    python3 tool/build_stock_catalog.py --from DIR # 이미 받은 *.zip이 있는 폴더에서 생성

출력 (용량을 줄이려고 배열로 저장, lib/data/catalog.dart가 읽는다):
    assets/stocks/kr.json  [[종목코드, 이름, "KOSPI"|"KOSDAQ"], ...]
    assets/stocks/us.json  [[티커, 한글명, 영문명, 거래소코드(NAS|NYS|AMS)], ...]

신규 상장·상장폐지를 반영하려면 가끔 다시 실행하고 커밋한다.
"""
import argparse
import json
import os
import sys
import urllib.request
import zipfile
from io import BytesIO

BASE = "https://new.real.download.dws.co.kr/common/master/"
KR_FILES = [("kospi_code.mst", "KOSPI"), ("kosdaq_code.mst", "KOSDAQ")]
US_FILES = ["nasmst.cod", "nysmst.cod", "amsmst.cod"]

# 해외 마스터 보안 유형: 1 지수, 2 주식, 3 ETP(ETF 등), 4 워런트. 주식·ETF만 쓴다.
US_TYPES = {"2", "3"}


def read_master(name, src_dir):
    if src_dir:
        with open(os.path.join(src_dir, name + ".zip"), "rb") as f:
            data = f.read()
    else:
        with urllib.request.urlopen(BASE + name + ".zip", timeout=60) as res:
            data = res.read()
    z = zipfile.ZipFile(BytesIO(data))
    return z.read(z.namelist()[0])


def parse_kr(raw, market):
    # 고정폭(바이트): 단축코드 9 · 표준코드 12 · 한글명 40 · 그룹코드 2 · ...
    out = []
    for line in raw.split(b"\n"):
        line = line.rstrip(b"\r")
        if len(line) < 63:
            continue
        code = line[0:9].decode("ascii").strip()
        if len(code) != 6:  # 펀드·수익증권 등 9자리 코드는 뺀다
            continue
        name = line[21:61].decode("cp949").strip()
        out.append([code, name, market])
    return out


def parse_us(raw):
    # 탭 구분: 국가 · 거래소ID · 거래소코드 · 거래소명 · 심볼 · 실시간심볼 · 한글명 · 영문명 · 유형 · ...
    out = []
    for line in raw.decode("cp949").splitlines():
        f = line.split("\t")
        if len(f) < 9 or f[8] not in US_TYPES:
            continue
        out.append([f[4].strip(), f[6].strip(), f[7].strip(), f[2].strip()])
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--from", dest="src", help="마스터 *.zip 폴더 (없으면 내려받음)")
    args = p.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "stocks")
    os.makedirs(out_dir, exist_ok=True)

    kr = []
    for name, market in KR_FILES:
        kr += parse_kr(read_master(name, args.src), market)
    kr.sort(key=lambda r: r[0])

    us = {}
    for name in US_FILES:
        for row in parse_us(read_master(name, args.src)):
            us.setdefault(row[0], row)  # 같은 티커가 두 거래소에 있으면 먼저 나온 것
    us_rows = sorted(us.values(), key=lambda r: r[0])

    for fname, rows in [("kr.json", kr), ("us.json", us_rows)]:
        with open(os.path.join(out_dir, fname), "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
    print(f"kr {len(kr)}, us {len(us_rows)} -> {out_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
