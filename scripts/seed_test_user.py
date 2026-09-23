"""
One-off script to seed a dummy regular User account (for testing chat
features, NOT an admin — see scripts/create_admin.py for that).

Usage:
    python scripts/seed_test_user.py [username] [password]

Defaults to username "testuser", password "123456" if not given.

Example:
    python scripts/seed_test_user.py
    python scripts/seed_test_user.py testuser2 mypassword
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlmodel import Session, select
import app.models  # noqa: F401 - registers tables with SQLModel metadata
from app.database import engine, create_db_and_tables
from app.models import User
from app.auth import _hash_password


def seed_test_user(username: str = "testuser", password: str = "123456"):
    create_db_and_tables()

    with Session(engine) as session:
        existing = session.exec(select(User).where(User.username == username)).first()
        if existing:
            existing.password_hash = _hash_password(password)
            session.add(existing)
            session.commit()
            print(f"User '{username}' sudah ada — password di-update jadi '{password}'.")
            return

        user = User(username=username, password_hash=_hash_password(password), auth_provider="local")
        session.add(user)
        session.commit()
        print(f"User dummy '{username}' berhasil dibuat dengan password '{password}'.")


if __name__ == "__main__":
    username = sys.argv[1] if len(sys.argv) > 1 else "testuser"
    password = sys.argv[2] if len(sys.argv) > 2 else "123456"
    seed_test_user(username, password)
