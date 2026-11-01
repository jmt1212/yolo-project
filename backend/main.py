"""Backend API untuk aplikasi deteksi lot parkir (dipakai oleh UI Flutter di parking_ui/).

Menyimpan daftar gedung, foto parkiran per gedung, dan konfigurasi slot per foto,
lalu menjalankan model YOLO pilihan untuk menentukan status tiap slot.

Jalankan dari folder ini:
    ..\\trial1\\.venv\\Scripts\\python.exe main.py
"""
import json
import shutil
import threading
import time
import uuid
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from ultralytics import YOLO

BASE_DIR = Path(__file__).resolve().parent
REPO_DIR = BASE_DIR.parent
DATA_DIR = BASE_DIR / "data"
PHOTO_DIR = DATA_DIR / "photos"
DB_PATH = DATA_DIR / "db.json"

DEFAULT_SETTINGS = {
    "model_dir": str(REPO_DIR / "trial1"),
    "model": "best_3.pt",
    "conf": 0.35,
    "overlap": 0.30,
}
DEFAULT_BUILDINGS = {
    "Gedung T": "Kampus Timur",
    "Gedung Q": "Kampus Pusat",
    "Gedung W": "Kampus Timur",
}
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

app = FastAPI(title="Deteksi Lot Parkir")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

db_lock = threading.Lock()
model_lock = threading.Lock()
model_cache = {}


# ---------------------------------------------------------------------------
# Penyimpanan (file JSON sederhana)
# ---------------------------------------------------------------------------

def now_iso():
  return time.strftime("%Y-%m-%dT%H:%M:%S")


def new_id():
  return uuid.uuid4().hex[:12]


def save_db(db):
  tmp = DB_PATH.with_suffix(".tmp")
  tmp.write_text(json.dumps(db, indent=2, ensure_ascii=False), encoding="utf-8")
  tmp.replace(DB_PATH)


def seed_db():
  """Isi awal: Gedung T, Q, W. Gedung Q diberi contoh foto + slot dari trial1."""
  db = {"settings": dict(DEFAULT_SETTINGS), "buildings": [], "photos": []}
  for name, location in DEFAULT_BUILDINGS.items():
    db["buildings"].append({
        "id": new_id(),
        "name": name,
        "location": location,
        "layout_photo_id": None,
        "created_at": now_iso(),
    })

  sample_img = REPO_DIR / "trial1" / "cropgedq.jpg"
  sample_cfg = REPO_DIR / "trial1" / "slots_config.json"
  if sample_img.exists() and sample_cfg.exists():
    gedung_q = next(b for b in db["buildings"] if b["name"] == "Gedung Q")
    data = sample_img.read_bytes()
    db["photos"].append(store_photo(gedung_q["id"], sample_img.name, data))
    photo = db["photos"][-1]
    slots = json.loads(sample_cfg.read_text())
    for i, slot in enumerate(slots, start=1):
      slot["label"] = f"Q-{i:02d}"  # kode lot seperti di wireframe, mis. T-01
    photo["slots"] = normalize_slots(slots, photo["width"], photo["height"])
  save_db(db)
  return db


def load_db():
  DATA_DIR.mkdir(exist_ok=True)
  PHOTO_DIR.mkdir(exist_ok=True)
  if not DB_PATH.exists():
    return seed_db()
  db = json.loads(DB_PATH.read_text(encoding="utf-8"))
  db["settings"] = {**DEFAULT_SETTINGS, **db.get("settings", {})}
  for building in db["buildings"]:
    # Data dari versi sebelumnya belum punya lokasi dan foto acuan.
    building.setdefault("location", DEFAULT_BUILDINGS.get(building["name"], ""))
    building.setdefault("layout_photo_id", None)
  return db


def find(items, item_id, what):
  for item in items:
    if item["id"] == item_id:
      return item
  raise HTTPException(404, f"{what} tidak ditemukan")


# ---------------------------------------------------------------------------
# Foto & slot
# ---------------------------------------------------------------------------

def store_photo(building_id, original_name, data):
  img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
  if img is None:
    raise HTTPException(400, "File bukan gambar yang valid")
  ext = Path(original_name).suffix.lower()
  if ext not in ALLOWED_EXT:
    ext = ".jpg"
  photo_id = new_id()
  filename = photo_id + ext
  (PHOTO_DIR / filename).write_bytes(data)
  return {
      "id": photo_id,
      "building_id": building_id,
      "filename": filename,
      "original_name": original_name,
      "width": int(img.shape[1]),
      "height": int(img.shape[0]),
      "slots": [],
      "uploaded_at": now_iso(),
      "last_result": None,
  }


def normalize_slots(slots, width, height):
  """Urutkan sudut kotak, batasi ke ukuran gambar, buang kotak kosong, beri id 1..n."""
  result = []
  for slot in slots:
    x1, y1, x2, y2 = [float(v) for v in slot["bbox"]]
    x1, x2 = sorted((max(0, min(x1, width)), max(0, min(x2, width))))
    y1, y2 = sorted((max(0, min(y1, height)), max(0, min(y2, height))))
    if x2 - x1 < 2 or y2 - y1 < 2:
      continue
    slot_id = len(result) + 1
    label = str(slot.get("label") or "").strip() or f"Slot A{slot_id}"
    result.append({
        "id": slot_id,
        "label": label,
        "bbox": [round(x1), round(y1), round(x2), round(y2)],
    })
  return result


def photo_summary(photo):
  out = {k: v for k, v in photo.items() if k != "filename"}
  out["slot_count"] = len(photo["slots"])
  return out


def layout_photo(db, building):
  """Foto acuan gedung: foto yang dipilih admin, atau foto pertama yang punya slot."""
  photos = [p for p in db["photos"] if p["building_id"] == building["id"] and p["slots"]]
  chosen = next((p for p in photos if p["id"] == building.get("layout_photo_id")), None)
  return chosen or (photos[0] if photos else None)


def building_summary(db, building):
  layout = layout_photo(db, building)
  return {
      **building,
      "layout_photo_id": layout["id"] if layout else None,
      "lot_count": len(layout["slots"]) if layout else 0,
      "photo_count": sum(1 for p in db["photos"] if p["building_id"] == building["id"]),
  }


def scale_slots(slots, src_w, src_h, dst_w, dst_h):
  """Pakai slot dari foto acuan pada foto lain dengan menskalakan koordinatnya.

  Hanya tepat jika kamera, sudut, dan potongan fotonya sama; kalau rasio
  ukurannya berbeda, kembalikan peringatan.
  """
  sx, sy = dst_w / src_w, dst_h / src_h
  scaled = [
      {**s, "bbox": [round(s["bbox"][0] * sx), round(s["bbox"][1] * sy),
                     round(s["bbox"][2] * sx), round(s["bbox"][3] * sy)]}
      for s in slots
  ]
  warning = None
  if abs(sx - sy) / max(sx, sy) > 0.03:
    warning = ("Ukuran foto berbeda dengan foto acuan gedung ini, "
               "sehingga posisi lot mungkin kurang tepat.")
  return scaled, warning


# ---------------------------------------------------------------------------
# Model & deteksi (logika sama dengan trial1/app.py)
# ---------------------------------------------------------------------------

def list_models(model_dir):
  path = Path(model_dir)
  if not path.is_dir():
    raise HTTPException(400, f"Folder tidak ditemukan: {model_dir}")
  return [
      {"name": p.name, "size_mb": round(p.stat().st_size / 1e6, 1)}
      for p in sorted(path.glob("*.pt"))
  ]


def get_model(path):
  key = str(path)
  with model_lock:
    if key not in model_cache:
      model_cache[key] = YOLO(key)
    return model_cache[key]


def slot_coverage(car_box, slot_box):
  """Bagian slot yang tertutup kotak mobil (luas irisan / luas slot)."""
  w = max(0, min(car_box[2], slot_box[2]) - max(car_box[0], slot_box[0]))
  h = max(0, min(car_box[3], slot_box[3]) - max(car_box[1], slot_box[1]))
  slot_area = (slot_box[2] - slot_box[0]) * (slot_box[3] - slot_box[1])
  return (w * h) / slot_area if slot_area > 0 else 0.0


def run_detection(photo, slots_in, model_path, conf, overlap):
  model = get_model(model_path)
  started = time.perf_counter()
  with model_lock:
    results = model.predict(
        source=str(PHOTO_DIR / photo["filename"]), conf=conf, save=False, verbose=False
    )[0]
  elapsed_ms = round((time.perf_counter() - started) * 1000)

  class_names = [str(n) for n in results.names.values()]
  cars = []
  for box in results.boxes:
    label = results.names.get(int(box.cls[0].item()), "").lower()
    if "car" in label:
      cars.append({
          "bbox": [round(v, 1) for v in box.xyxy[0].cpu().numpy().tolist()],
          "conf": round(float(box.conf[0].item()), 3),
      })

  slots = []
  counts = {"empty": 0, "occupied": 0, "anomaly": 0}
  for slot in slots_in:
    matching = sum(1 for car in cars if slot_coverage(car["bbox"], slot["bbox"]) > overlap)
    status = "empty" if matching == 0 else "occupied" if matching == 1 else "anomaly"
    counts[status] += 1
    slots.append({**slot, "status": status, "cars": matching})

  warning = None
  if not any("car" in n.lower() for n in class_names):
    warning = f"Model ini tidak punya kelas 'car' (kelas: {', '.join(class_names)})"
  return {
      "model": Path(model_path).name,
      "conf": conf,
      "overlap": overlap,
      "class_names": class_names,
      "warning": warning,
      "summary": {"total": len(slots), **counts},
      "slots": slots,
      "cars": cars,
      "elapsed_ms": elapsed_ms,
      "detected_at": now_iso(),
  }


# ---------------------------------------------------------------------------
# Skema request
# ---------------------------------------------------------------------------

class BuildingIn(BaseModel):
  name: str
  location: str = ""


class BuildingPatch(BaseModel):
  name: Optional[str] = None
  location: Optional[str] = None
  layout_photo_id: Optional[str] = None


class SlotIn(BaseModel):
  label: Optional[str] = None
  bbox: list[float]


class SlotsIn(BaseModel):
  slots: list[SlotIn]


class SettingsIn(BaseModel):
  model_dir: Optional[str] = None
  model: Optional[str] = None
  conf: Optional[float] = None
  overlap: Optional[float] = None


class DetectIn(BaseModel):
  model: Optional[str] = None
  conf: Optional[float] = None
  overlap: Optional[float] = None
  # Lot yang diatur manual oleh pengguna untuk foto ini (menggantikan slot foto/foto acuan).
  slots: Optional[list[SlotIn]] = None


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------

@app.get("/api/health")
def health():
  return {"status": "ok"}


@app.get("/api/settings")
def get_settings():
  with db_lock:
    return load_db()["settings"]


@app.put("/api/settings")
def update_settings(body: SettingsIn):
  with db_lock:
    db = load_db()
    settings = db["settings"]
    model_dir = body.model_dir if body.model_dir is not None else settings["model_dir"]
    models = [m["name"] for m in list_models(model_dir)]
    model = body.model if body.model is not None else settings["model"]
    if model not in models:
      if body.model is not None:
        raise HTTPException(400, f"Model '{model}' tidak ada di folder ini")
      model = models[0] if models else ""
    if body.conf is not None and not 0 < body.conf < 1:
      raise HTTPException(400, "Confidence harus di antara 0 dan 1")
    if body.overlap is not None and not 0 < body.overlap < 1:
      raise HTTPException(400, "Batas overlap harus di antara 0 dan 1")
    settings.update({
        "model_dir": str(Path(model_dir).resolve()),
        "model": model,
        "conf": body.conf if body.conf is not None else settings["conf"],
        "overlap": body.overlap if body.overlap is not None else settings["overlap"],
    })
    save_db(db)
    return settings


@app.get("/api/models")
def get_models(dir: Optional[str] = None):
  with db_lock:
    model_dir = dir or load_db()["settings"]["model_dir"]
  return {"dir": str(Path(model_dir).resolve()), "models": list_models(model_dir)}


@app.get("/api/browse")
def browse(path: Optional[str] = None):
  """Daftar subfolder dan file .pt, untuk memilih folder model dari UI."""
  with db_lock:
    current = Path(path or load_db()["settings"]["model_dir"]).resolve()
  if not current.is_dir():
    raise HTTPException(400, f"Folder tidak ditemukan: {current}")
  dirs = []
  for p in sorted(current.iterdir(), key=lambda p: p.name.lower()):
    try:
      if p.is_dir() and not p.name.startswith("."):
        dirs.append(p.name)
    except OSError:
      continue
  parent = str(current.parent) if current.parent != current else None
  return {"path": str(current), "parent": parent, "dirs": dirs,
          "models": list_models(current)}


@app.get("/api/buildings")
def get_buildings():
  with db_lock:
    db = load_db()
  return [building_summary(db, b) for b in db["buildings"]]


@app.get("/api/buildings/{building_id}")
def get_building(building_id: str):
  with db_lock:
    db = load_db()
  return building_summary(db, find(db["buildings"], building_id, "Gedung"))


@app.get("/api/buildings/{building_id}/layout")
def get_layout(building_id: str):
  """Lot dari foto acuan gedung, untuk diisi awal di editor lot pada foto baru."""
  with db_lock:
    db = load_db()
  layout = layout_photo(db, find(db["buildings"], building_id, "Gedung"))
  if layout is None:
    return {"width": None, "height": None, "slots": []}
  return {"width": layout["width"], "height": layout["height"], "slots": layout["slots"]}


def clean_name(name, db, skip_id=None):
  name = name.strip()
  if not name:
    raise HTTPException(400, "Nama gedung tidak boleh kosong")
  if any(b["name"].lower() == name.lower() and b["id"] != skip_id for b in db["buildings"]):
    raise HTTPException(409, f"'{name}' sudah ada")
  return name


@app.post("/api/buildings", status_code=201)
def add_building(body: BuildingIn):
  with db_lock:
    db = load_db()
    building = {
        "id": new_id(),
        "name": clean_name(body.name, db),
        "location": body.location.strip(),
        "layout_photo_id": None,
        "created_at": now_iso(),
    }
    db["buildings"].append(building)
    save_db(db)
    return building_summary(db, building)


@app.patch("/api/buildings/{building_id}")
def update_building(building_id: str, body: BuildingPatch):
  with db_lock:
    db = load_db()
    building = find(db["buildings"], building_id, "Gedung")
    if body.name is not None:
      building["name"] = clean_name(body.name, db, skip_id=building_id)
    if body.location is not None:
      building["location"] = body.location.strip()
    if body.layout_photo_id is not None:
      photo = find(db["photos"], body.layout_photo_id, "Foto")
      if photo["building_id"] != building_id:
        raise HTTPException(400, "Foto ini bukan milik gedung tersebut")
      if not photo["slots"]:
        raise HTTPException(400, "Foto acuan harus punya slot. Atur slotnya dulu.")
      building["layout_photo_id"] = photo["id"]
    save_db(db)
    return building_summary(db, building)


@app.delete("/api/buildings/{building_id}", status_code=204)
def delete_building(building_id: str):
  with db_lock:
    db = load_db()
    find(db["buildings"], building_id, "Gedung")
    for photo in [p for p in db["photos"] if p["building_id"] == building_id]:
      (PHOTO_DIR / photo["filename"]).unlink(missing_ok=True)
    db["photos"] = [p for p in db["photos"] if p["building_id"] != building_id]
    db["buildings"] = [b for b in db["buildings"] if b["id"] != building_id]
    save_db(db)


@app.get("/api/buildings/{building_id}/photos")
def get_photos(building_id: str):
  with db_lock:
    db = load_db()
  find(db["buildings"], building_id, "Gedung")
  return [photo_summary(p) for p in db["photos"] if p["building_id"] == building_id]


@app.post("/api/buildings/{building_id}/photos", status_code=201)
async def upload_photo(building_id: str, file: UploadFile = File(...)):
  data = await file.read()
  with db_lock:
    db = load_db()
    find(db["buildings"], building_id, "Gedung")
    photo = store_photo(building_id, file.filename or "foto.jpg", data)
    db["photos"].append(photo)
    save_db(db)
  return photo_summary(photo)


@app.get("/api/photos/{photo_id}")
def get_photo(photo_id: str):
  with db_lock:
    db = load_db()
  return photo_summary(find(db["photos"], photo_id, "Foto"))


@app.get("/api/photos/{photo_id}/image")
def get_photo_image(photo_id: str):
  with db_lock:
    db = load_db()
  photo = find(db["photos"], photo_id, "Foto")
  return FileResponse(PHOTO_DIR / photo["filename"])


@app.delete("/api/photos/{photo_id}", status_code=204)
def delete_photo(photo_id: str):
  with db_lock:
    db = load_db()
    photo = find(db["photos"], photo_id, "Foto")
    (PHOTO_DIR / photo["filename"]).unlink(missing_ok=True)
    db["photos"] = [p for p in db["photos"] if p["id"] != photo_id]
    save_db(db)


@app.put("/api/photos/{photo_id}/slots")
def save_slots(photo_id: str, body: SlotsIn):
  with db_lock:
    db = load_db()
    photo = find(db["photos"], photo_id, "Foto")
    slots = normalize_slots(
        [s.model_dump() for s in body.slots], photo["width"], photo["height"]
    )
    result = photo["last_result"]
    if result and [s["bbox"] for s in slots] == [s["bbox"] for s in result["slots"]]:
      # Hanya label yang berubah: hasil deteksi lama masih berlaku.
      for slot, res in zip(slots, result["slots"]):
        res["label"] = slot["label"]
    else:
      photo["last_result"] = None
    photo["slots"] = slots
    save_db(db)
  return photo_summary(photo)


@app.post("/api/photos/{photo_id}/detect")
def detect(photo_id: str, body: DetectIn):
  with db_lock:
    db = load_db()
    photo = find(db["photos"], photo_id, "Foto")
    settings = db["settings"]
    # Foto yang slotnya diatur sendiri memakai slot itu; foto lain (mis. unggahan
    # pengunjung) memakai slot dari foto acuan gedungnya.
    layout_warning = None
    if body.slots is not None:
      slots = normalize_slots([s.model_dump() for s in body.slots], photo["width"], photo["height"])
      photo["slots"] = slots  # disimpan supaya "Coba lagi" memakai lot yang sama
      save_db(db)
      source = "manual"
    elif photo["slots"]:
      slots, source = photo["slots"], "photo"
    else:
      building = find(db["buildings"], photo["building_id"], "Gedung")
      layout = layout_photo(db, building)
      if layout:
        slots, layout_warning = scale_slots(
            layout["slots"], layout["width"], layout["height"], photo["width"], photo["height"]
        )
        source = "building"
      else:
        slots, source = [], "none"
  model_name = body.model or settings["model"]
  model_path = Path(settings["model_dir"]) / model_name
  if not model_path.is_file():
    raise HTTPException(400, f"Model tidak ditemukan: {model_path}")
  result = run_detection(
      photo,
      slots,
      model_path,
      body.conf if body.conf is not None else settings["conf"],
      body.overlap if body.overlap is not None else settings["overlap"],
  )
  result["layout_source"] = source
  result["layout_warning"] = layout_warning
  with db_lock:
    db = load_db()
    stored = next((p for p in db["photos"] if p["id"] == photo_id), None)
    if stored is not None:
      stored["last_result"] = result
      save_db(db)
  return result


if __name__ == "__main__":
  import uvicorn

  uvicorn.run(app, host="127.0.0.1", port=8001)
