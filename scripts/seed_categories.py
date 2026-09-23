"""
Seeds the initial Category/Subcategory tree.

Category name is "Regional Batam" (not just "Regional") — this app is
scoped to Batam for now, but the Category/Subcategory structure already
supports expanding nationwide later: adding "Regional Jakarta",
"Regional Surabaya", etc. as SEPARATE Category rows, each with their own
kecamatan/district subcategories, needs no schema change — just run a
similar seed for that city.

Regional Batam's subcategories are Batam's ACTUAL 12 kecamatan
(districts).

Usage:
    python scripts/seed_categories.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlmodel import Session, select
import app.models  # noqa: F401 - registers tables with SQLModel metadata
from app.database import engine, create_db_and_tables
from app.models import Category, Subcategory

# Batam's 12 official kecamatan (as of this app's last update — verify
# against current BPS/Pemko Batam data if this ever needs to change).
BATAM_KECAMATAN = [
    "Batu Ampar", "Lubuk Baja", "Sekupang", "Nongsa", "Batam Kota",
    "Sagulung", "Sungai Beduk", "Bengkong", "Batu Aji", "Bulang",
    "Galang", "Belakang Padang",
]

HOBBY_TOPICS = ["Game", "Musik", "Kuliner", "Otomotif", "Olahraga"]


def get_or_create_category(session: Session, name: str, sort_order: int) -> Category:
    existing = session.exec(select(Category).where(Category.name == name)).first()
    if existing:
        return existing
    cat = Category(name=name, sort_order=sort_order)
    session.add(cat)
    session.commit()
    session.refresh(cat)
    return cat


def get_or_create_subcategory(session: Session, category_id: int, name: str, sort_order: int):
    existing = session.exec(
        select(Subcategory).where(Subcategory.category_id == category_id, Subcategory.name == name)
    ).first()
    if existing:
        return existing
    sub = Subcategory(category_id=category_id, name=name, sort_order=sort_order)
    session.add(sub)
    session.commit()


def seed():
    create_db_and_tables()

    with Session(engine) as session:
        regional = get_or_create_category(session, "Regional Batam", sort_order=0)
        for i, kecamatan in enumerate(BATAM_KECAMATAN):
            get_or_create_subcategory(session, regional.id, kecamatan, sort_order=i)
        print(f"Regional Batam: {len(BATAM_KECAMATAN)} kecamatan ditambahkan.")

        hobi = get_or_create_category(session, "Hobi & Komunitas", sort_order=1)
        for i, topic in enumerate(HOBBY_TOPICS):
            get_or_create_subcategory(session, hobi.id, topic, sort_order=i)
        print(f"Hobi & Komunitas: {len(HOBBY_TOPICS)} topik ditambahkan.")


if __name__ == "__main__":
    seed()
    print("Selesai.")
    print()
    print("Catatan: kalau nanti mau expand ke kota lain, tambah kategori baru")
    print("seperti 'Regional Jakarta' dengan kecamatan/subcategory-nya sendiri —")
    print("tidak perlu ubah struktur database, cukup tambah data baru.")

