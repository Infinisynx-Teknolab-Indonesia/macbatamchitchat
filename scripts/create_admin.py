"""
One-off script to create an admin account directly in the database.

Not exposed as a public API endpoint on purpose — admins are a separate
table (Admin) from regular chat users (User), and there's no network
route that creates one. This script is the only way, which is the right
level of trust for "can create admins": you already need access to run
code on the server machine.

Usage:
    python scripts/create_admin.py <username> <password> [role]

role defaults to "moderator". Other suggested values: "superadmin", "support".

Example:
    python scripts/create_admin.py adminchitcat "Gogle@123" superadmin
"""
import sys
import os

# Make "app" importable regardless of which folder you run this from,
# same fix as app/main.py uses.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlmodel import Session, select
import app.models  # noqa: F401 - registers tables with SQLModel metadata
from app.database import engine, create_db_and_tables
from app.models import Admin
from app.auth import _hash_password


def create_admin(username: str, password: str, role: str = "moderator"):
    create_db_and_tables()  # safe no-op if tables already exist

    with Session(engine) as session:
        existing = session.exec(select(Admin).where(Admin.username == username)).first()
        if existing:
            existing.password_hash = _hash_password(password)
            existing.role = role
            session.add(existing)
            session.commit()
            print(f"Admin '{username}' sudah ada — password & role di-update (role: {role}).")
            return

        admin = Admin(username=username, password_hash=_hash_password(password), role=role)
        session.add(admin)
        session.commit()
        print(f"Admin '{username}' berhasil dibuat dengan role '{role}'.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python scripts/create_admin.py <username> <password> [role]")
        sys.exit(1)

    username = sys.argv[1]
    password = sys.argv[2]
    role = sys.argv[3] if len(sys.argv) > 3 else "moderator"
    create_admin(username, password, role)
