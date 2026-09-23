"""
Seeds 10 dummy users (5 male, 5 female) with gender set — for testing the
room member list's gender icons and general room-chat UI without needing
10 real people to sign up.

Usage:
    python scripts/seed_dummy_room_users.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlmodel import Session, select
import app.models  # noqa: F401
from app.database import engine, create_db_and_tables
from app.models import User
from app.auth import _hash_password

DUMMY_USERS = [
    ("andi_batam", "Andi Saputra", "male"),
    ("budi_santoso", "Budi Santoso", "male"),
    ("anto_gaming", "Anto Wijaya", "male"),
    ("rudi_kepri", "Rudi Hartono", "male"),
    ("doni_nagoya", "Doni Pratama", "male"),
    ("wati99", "Wati Anggraini", "female"),
    ("rina_kepri", "Rina Marlina", "female"),
    ("sari_lawson", "Sari Wulandari", "female"),
    ("citra_dewi", "Citra Dewi", "female"),
    ("fitri_citra", "Fitri Handayani", "female"),
]


def seed():
    create_db_and_tables()

    with Session(engine) as session:
        for username, full_name, gender in DUMMY_USERS:
            existing = session.exec(select(User).where(User.username == username)).first()
            if existing:
                existing.full_name = full_name
                existing.gender = gender
                session.add(existing)
                print(f"Update: {username} ({gender})")
            else:
                user = User(
                    username=username,
                    full_name=full_name,
                    gender=gender,
                    password_hash=_hash_password("dummy12345"),
                    auth_provider="local",
                )
                session.add(user)
                print(f"Dibuat: {username} ({gender})")
        session.commit()


if __name__ == "__main__":
    seed()
    print()
    print(f"Selesai — {len(DUMMY_USERS)} user dummy siap (password semuanya: dummy12345)")
