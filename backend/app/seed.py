from sqlalchemy import select

from app.database import SessionLocal
from app.models import Comment, Document, DocumentVersion, Notification, Project, Share, User
from app.security import hash_password

DEMO_PASSWORD = "InspiraT-demo-2026!"


def seed() -> None:
    with SessionLocal() as db:
        if db.scalar(select(User).where(User.username == "ines")):
            print("Los datos de demostración ya existen.")
            return
        ines = User(
            email="ines@example.com",
            username="ines",
            display_name="Inés Valdivia",
            password_hash=hash_password(DEMO_PASSWORD),
        )
        mateo = User(
            email="mateo@example.com",
            username="mateo",
            display_name="Mateo Rojas",
            password_hash=hash_password(DEMO_PASSWORD),
        )
        db.add_all([ines, mateo])
        db.flush()
        project = Project(
            client_id="10000000-0000-4000-8000-000000000001",
            owner_id=ines.id,
            title="La ciudad sumergida",
            subtitle="Una novela sobre memoria y mareas",
            work_type="novel",
            synopsis="Cada lluvia devuelve a la ciudad un recuerdo que alguien quiso borrar.",
            color="#1E5B57",
            word_goal=65_000,
        )
        db.add(project)
        db.flush()
        chapter = Document(
            client_id="20000000-0000-4000-8000-000000000001",
            project_id=project.id,
            title="1. La primera lluvia",
            kind="chapter",
            content=(
                "La lluvia recordó primero. Golpeó las ventanas con la paciencia "
                "de quien conoce todos los nombres de la casa."
            ),
            word_count=20,
        )
        chapter_two = Document(
            client_id="20000000-0000-4000-8000-000000000002",
            project_id=project.id,
            title="2. El mapa de sal",
            kind="chapter",
            content="Inés desplegó el mapa sobre la mesa. Las calles cambiaban con la marea.",
            word_count=14,
            position=1,
        )
        db.add_all([chapter, chapter_two])
        db.flush()
        db.add(
            DocumentVersion(
                document_id=chapter.id,
                author_id=ines.id,
                name="Primer borrador",
                content="La lluvia llegó primero.",
                revision=1,
                is_manual=True,
            )
        )
        share = Share(
            document_id=chapter.id,
            sender_id=ines.id,
            recipient_id=mateo.id,
            permission="comment",
            message="¿Me ayudas con el ritmo del inicio?",
        )
        db.add(share)
        db.add(
            Comment(
                document_id=chapter.id,
                author_id=mateo.id,
                body="La imagen abre muy bien; conservaría esta frase.",
                anchor_start=0,
                anchor_end=26,
                quoted_text="La lluvia recordó primero.",
            )
        )
        db.add(
            Notification(
                user_id=ines.id,
                kind="comment",
                title="Mateo comentó «La primera lluvia»",
                resource_id=chapter.id,
            )
        )
        db.commit()
        print("Datos demo creados.")
        print("ines / mateo — contraseña: InspiraT-demo-2026!")


if __name__ == "__main__":
    seed()
