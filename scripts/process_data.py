#!/usr/bin/env python3
"""
process_data.py - 행안부 LOCALDATA 일반음식점(general_restaurants)·휴게음식점(rest_cafes)·제과점(bakeries) 인허가 CSV에서
'붕어빵·호떡·토스트·어묵…' 등 겨울/길거리 간식 상호를 가진 영업 중 점포를 뽑아 사이트 데이터로 가공한다.

입력: data/raw/general_restaurants.csv(일반음식점), rest_cafes.csv(휴게음식점), bakeries.csv(제과점) (CP949, EPSG:5174)
      ../wooaleisure/_rawdata/lei_*.json (동 중심 좌표 보강용 - 있으면 사용)
출력: _rawdata/snk_{시도}.json (점포), _rawdata/dongs.json (동 허브 목록+근처 정보), assets/dongs.json (내 주변 찾기용 경량본), search_index.json
"""
import csv, io, json, re, sys, hashlib, math
from pathlib import Path
from collections import Counter, defaultdict
import numpy as np
from pyproj import Transformer

sys.stdout.reconfigure(encoding="utf-8")
csv.field_size_limit(10_000_000)

ROOT = Path(__file__).parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "_rawdata"
LEISURE = ROOT.parent / "wooaleisure" / "_rawdata"

DO_MAP = {
    "서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주",
    "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기",
    "강원특별자치도": "강원", "강원도": "강원", "충청북도": "충북", "충청남도": "충남",
    "전북특별자치도": "전북", "전라북도": "전북", "전라남도": "전남", "경상북도": "경북", "경상남도": "경남",
    "제주특별자치도": "제주", "제주도": "제주",
}

# 우선순위 순서 (앞쪽이 대표 종류). key, 라벨, 아이콘, 키워드
TYPES = [
    ("bungeoppang", "붕어빵", "🐟", ["붕어빵", "잉어빵", "국화빵", "풀빵", "계란빵"]),
    ("hotteok", "호떡", "🥞", ["호떡"]),
    ("toast", "토스트", "🥪", ["토스트"]),
    ("goguma", "군고구마", "🍠", ["군고구마", "고구마"]),
    ("eomuk", "어묵·오뎅", "🍢", ["어묵", "오뎅"]),
    ("kkwabaegi", "꽈배기", "🥨", ["꽈배기"]),
    ("hodu", "호두과자", "🌰", ["호두과자"]),
    ("takoyaki", "타코야끼", "🐙", ["타코야끼", "타코야키"]),
    ("hotdog", "핫도그", "🌭", ["핫도그"]),
    ("mandu", "만두·찐빵", "🥟", ["찐빵", "호빵", "만두"]),
    ("tteokbokki", "떡볶이", "🌶️", ["떡볶이", "떡볶"]),
    ("etc", "닭꼬치·츄러스", "🍡", ["닭꼬치", "츄러스", "츄로스", "옥수수", "델리만쥬", "땅콩과자"]),
]
TYPE_BY_KEY = {t[0]: t for t in TYPES}

DONG_TOKEN = re.compile(r"^[가-힣][가-힣0-9]*(?:동|읍|면)$|^[가-힣]+\d+가$")
BUILDING_LABEL = re.compile(r"^[가나다라마바사아자차카타파하]동$")


def clean(s):
    return re.sub(r"\s+", " ", str(s or "").strip())


def split_address(addr):
    toks = addr.split()
    if len(toks) < 2:
        return None, None, []
    sido_full = toks[0]
    if sido_full == "세종특별자치시":
        return sido_full, "세종시", toks[1:]
    sg = toks[1]
    rest = toks[2:]
    if sg.endswith("시") and rest and rest[0].endswith("구") and len(rest[0]) > 1:
        sg = f"{sg} {rest[0]}"
        rest = rest[1:]
    return sido_full, sg, rest


def find_dong(tokens):
    for t in tokens[:4]:
        t = t.strip("(),")
        if DONG_TOKEN.match(t) and not BUILDING_LABEL.match(t):
            return t
    return None


def dong_from_paren(addr):
    for m in re.finditer(r"\(([^)]*)\)", addr):
        for part in re.split(r"[,\s]+", m.group(1)):
            if DONG_TOKEN.match(part) and not BUILDING_LABEL.match(part):
                return part
    return None


def fmt_tel(t):
    d = re.sub(r"\D", "", t or "")
    if len(d) < 8:
        return ""
    if d.startswith("02"):
        return f"02-{d[2:-4]}-{d[-4:]}" if len(d) >= 9 else ""
    if len(d) in (10, 11) and d.startswith("0"):
        return f"{d[:3]}-{d[3:-4]}-{d[-4:]}"
    if len(d) == 8:
        return f"{d[:4]}-{d[4:]}"
    return ""


def make_slug(name, addr):
    base = re.sub(r"[^\w가-힣\s-]", "", name).strip()
    base = re.sub(r"\s+", "-", base)
    base = re.sub(r"-+", "-", base)[:24].strip("-")
    h = hashlib.md5(f"{name}|{addr}".encode("utf-8")).hexdigest()[:6]
    return f"{base}-{h}" if base else h


def match_types(name):
    n = name.replace(" ", "")
    found = []
    for key, _label, _icon, kws in TYPES:
        if any(k in n for k in kws):
            found.append(key)
    return found


def read_rows(path):
    with open(path, "rb") as f:
        wrapper = io.TextIOWrapper(f, encoding="cp949", errors="replace", newline="")
        rdr = csv.DictReader(wrapper)
        for r in rdr:
            yield r


def haversine_matrix(lat1, lng1, lat2, lng2):
    """(N,) x (M,) -> (N, M) km"""
    p = math.pi / 180
    a = np.sin((lat2[None, :] - lat1[:, None]) * p / 2) ** 2 + \
        np.cos(lat1[:, None] * p) * np.cos(lat2[None, :] * p) * np.sin((lng2[None, :] - lng1[:, None]) * p / 2) ** 2
    return 12742 * np.arcsin(np.sqrt(a))


def main():
    tf = Transformer.from_crs("EPSG:5174", "EPSG:4326", always_xy=True)
    items, seen, skipped = [], Counter(), Counter()
    dedupe = set()
    for src in ("general_restaurants", "rest_cafes", "bakeries"):
        path = RAW / f"{src}.csv"
        n_open = 0
        for r in read_rows(path):
            if clean(r.get("영업상태명")) != "영업/정상":
                continue
            n_open += 1
            name = clean(r.get("사업장명"))
            if not name:
                continue
            types = match_types(name)
            if not types:
                continue
            lot, road = clean(r.get("지번주소")), clean(r.get("도로명주소"))
            addr = road or lot
            if not addr:
                skipped["no_addr"] += 1
                continue
            sido_full, sg, rest = split_address(lot or road)
            if not sido_full:
                skipped["bad_addr"] += 1
                continue
            if sido_full == "전남광주통합특별시":
                do = "광주" if (sg or "").endswith("구") else "전남"
            else:
                do = DO_MAP.get(sido_full)
            if not do or not sg:
                skipped["no_sido"] += 1
                continue
            key = (name, addr)
            if key in dedupe:
                skipped["dup"] += 1
                continue
            dedupe.add(key)
            dong = find_dong(rest) or dong_from_paren(road) or "기타"
            lat = lng = None
            x, y = clean(r.get("좌표정보(X)")), clean(r.get("좌표정보(Y)"))
            try:
                if x and y:
                    lo, la = tf.transform(float(x), float(y))
                    if 33 <= la <= 39 and 124 <= lo <= 132:
                        lat, lng = round(la, 6), round(lo, 6)
            except ValueError:
                pass
            slug = make_slug(name, addr)
            seen[slug] += 1
            if seen[slug] > 1:
                slug = f"{slug}-{seen[slug]}"
            primary = types[0]
            items.append({
                "slug": slug, "shopName": name, "types": types, "type": primary,
                "typeLabel": TYPE_BY_KEY[primary][1], "typeIcon": TYPE_BY_KEY[primary][2],
                "typeLabels": [TYPE_BY_KEY[t][1] for t in types],
                "doShort": do, "sigungu": sg, "sgSlug": sg.replace(" ", "-"), "dong": dong,
                "road": road, "lot": lot, "tel": fmt_tel(r.get("전화번호")),
                "permit": clean(r.get("인허가일자")), "upd": clean(r.get("데이터갱신시점"))[:10],
                "biz": clean(r.get("업태구분명")), "src": src,
                "lat": lat, "lng": lng,
            })
        print(f"[{src}] 영업 {n_open:,} → 누적 간식 점포 {len(items):,}", flush=True)

    print("제외:", dict(skipped), "종류별:", dict(Counter(i["type"] for i in items)))

    # ---- 동 단위 집계 & 순위
    by_dong = defaultdict(list)
    for i in items:
        by_dong[(i["doShort"], i["sigungu"], i["dong"])].append(i)
    for lst in by_dong.values():
        lst.sort(key=lambda x: (x["permit"] or "9999", x["slug"]))
        for rank, i in enumerate(lst, 1):
            i["dongCount"] = len(lst)
            i["dongRank"] = rank

    # ---- 동 중심 좌표 (점포 + 레저 시설)
    pts = defaultdict(list)
    for i in items:
        if i["lat"] is not None and i["dong"] != "기타":
            pts[(i["doShort"], i["sigungu"], i["dong"])].append((i["lat"], i["lng"]))
    ref_sg = {}
    if LEISURE.exists():
        for p in LEISURE.glob("lei_*.json"):
            for f in json.loads(p.read_text(encoding="utf-8")):
                if f.get("dong") and f["dong"] != "기타" and f.get("lat") not in ("", None):
                    k = (f["doShort"], f["sigungu"], f["dong"])
                    pts[k].append((float(f["lat"]), float(f["lng"])))
                    ref_sg[k] = f["sgSlug"]
    for i in items:
        ref_sg.setdefault((i["doShort"], i["sigungu"], i["dong"]), i["sgSlug"])
    for k in list(by_dong.keys()):
        pts.setdefault(k, [])
    dong_keys = sorted(k for k in pts.keys() if k[2] != "기타")
    centroid = {}
    for k in dong_keys:
        v = pts[k]
        if v:
            centroid[k] = (sum(a for a, _ in v) / len(v), sum(b for _, b in v) / len(v))
    print(f"동 {len(dong_keys):,}개 (좌표 있음 {len(centroid):,}, 점포 보유 {sum(1 for k in dong_keys if k in by_dong):,})")

    # ---- 점포별 근처 점포 (좌표 있는 점포끼리)
    geo = [i for i in items if i["lat"] is not None]
    glat = np.array([i["lat"] for i in geo])
    glng = np.array([i["lng"] for i in geo])
    for i in items:
        i["near"] = []
    CH = 800
    for s in range(0, len(geo), CH):
        d = haversine_matrix(glat[s:s + CH], glng[s:s + CH], glat, glng)
        for r in range(d.shape[0]):
            d[r, s + r] = 1e9
        idx = np.argpartition(d, 8, axis=1)[:, :8]
        for r in range(idx.shape[0]):
            row = idx[r][np.argsort(d[r, idx[r]])]
            me = geo[s + r]
            me["near"] = [{"slug": geo[j]["slug"], "name": geo[j]["shopName"], "type": geo[j]["typeLabel"],
                           "dong": geo[j]["dong"], "m": int(d[r, j] * 1000)} for j in row if d[r, j] < 3.0][:6]
    print("근처 점포 계산 완료", flush=True)

    # ---- 동 허브별 근처 점포/근처 동
    dk = [k for k in dong_keys if k in centroid]
    dlat = np.array([centroid[k][0] for k in dk])
    dlng = np.array([centroid[k][1] for k in dk])
    dd = haversine_matrix(dlat, dlng, dlat, dlng)
    for r in range(len(dk)):
        dd[r, r] = 1e9
    dd_idx = np.argsort(dd, axis=1)[:, :8]
    sd = haversine_matrix(dlat, dlng, glat, glng)
    sd_idx = np.argsort(sd, axis=1)[:, :10]
    dong_out = []
    for r, k in enumerate(dk):
        do, sg, dong = k
        near_dongs = []
        for j in dd_idx[r]:
            if dd[r, j] > 6.0:
                break
            nk = dk[j]
            near_dongs.append({"do": nk[0], "sg": nk[1], "sgSlug": ref_sg.get(nk, nk[1].replace(" ", "-")), "dong": nk[2], "km": round(float(dd[r, j]), 1),
                               "n": len(by_dong.get(nk, []))})
        near_shops = []
        own = {i["slug"] for i in by_dong.get(k, [])}
        for j in sd_idx[r]:
            if sd[r, j] > 4.0:
                break
            s = geo[j]
            if s["slug"] in own:
                continue
            near_shops.append({"slug": s["slug"], "name": s["shopName"], "type": s["typeLabel"], "icon": s["typeIcon"], "dong": s["dong"],
                               "sigungu": s["sigungu"], "km": round(float(sd[r, j]), 1)})
        dong_out.append({"do": do, "sigungu": sg, "sgSlug": ref_sg.get(k, sg.replace(" ", "-")), "dong": dong,
                         "lat": round(centroid[k][0], 5), "lng": round(centroid[k][1], 5),
                         "nearDongs": near_dongs, "nearShops": near_shops[:8], "shopCount": len(by_dong.get(k, []))})
    # 좌표 없는 동(점포만 있고 좌표 없음)도 허브는 만든다
    have = {(d["do"], d["sigungu"], d["dong"]) for d in dong_out}
    for k in dong_keys:
        if k not in have:
            do, sg, dong = k
            dong_out.append({"do": do, "sigungu": sg, "sgSlug": ref_sg.get(k, sg.replace(" ", "-")), "dong": dong,
                             "lat": None, "lng": None, "nearDongs": [], "nearShops": [], "shopCount": len(by_dong.get(k, []))})
    (OUT).mkdir(parents=True, exist_ok=True)
    (OUT / "dongs.json").write_text(json.dumps(dong_out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    light = [{"d": d["do"], "s": d["sigungu"], "g": d["sgSlug"], "n": d["dong"], "a": d["lat"], "o": d["lng"]} for d in dong_out if d["lat"] is not None]
    (ROOT / "assets").mkdir(exist_ok=True)
    (ROOT / "assets" / "dongs.json").write_text(json.dumps(light, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # ---- 시도별 샤드
    for old in OUT.glob("snk_*.json"):
        old.unlink()
    by_do = defaultdict(list)
    for i in items:
        by_do[i["doShort"]].append(i)
    for do, group in by_do.items():
        (OUT / f"snk_{do}.json").write_text(json.dumps(group, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    index = [{"n": i["shopName"], "s": i["slug"], "do": i["doShort"], "sg": i["sigungu"], "dg": i["dong"], "c": i["typeLabel"]} for i in items]
    (ROOT / "search_index.json").write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"점포 {len(items):,}곳, 동 허브 {len(dong_out):,}개, 시도 샤드 {len(by_do)}개, 검색 인덱스 저장")


if __name__ == "__main__":
    main()
