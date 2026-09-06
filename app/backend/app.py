import os

from flask import Flask, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

from aws_clients import publish_notification, send_request_message
from db import get_connection, init_db

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", os.urandom(24))

ARCHITECTURES = ["64bit-x86", "64bit-arm"]
INSTANCE_TYPES = ["t3-nano", "t3-micro", "t3-small"]

with app.app_context():
    init_db()


def current_user():
    return session.get("username")


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        if not username or not password:
            flash("Username and password are required.")
            return redirect(url_for("register"))

        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE username = %s", (username,))
                if cur.fetchone():
                    flash("That username is already taken.")
                    return redirect(url_for("register"))
                cur.execute(
                    "INSERT INTO users (username, password_hash) VALUES (%s, %s)",
                    (username, generate_password_hash(password)),
                )
            conn.commit()
        finally:
            conn.close()

        flash("Account created. Please log in.")
        return redirect(url_for("login"))

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]

        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT password_hash FROM users WHERE username = %s", (username,))
                row = cur.fetchone()
        finally:
            conn.close()

        if row and check_password_hash(row[0], password):
            session["username"] = username
            return redirect(url_for("index"))

        flash("Invalid username or password.")
        return redirect(url_for("login"))

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.pop("username", None)
    return redirect(url_for("login"))


@app.route("/", methods=["GET", "POST"])
def index():
    username = current_user()
    if not username:
        return redirect(url_for("login"))

    if request.method == "POST":
        vm_name = request.form.get("vm_name", "").strip()
        architecture = request.form.get("architecture")
        instance_type = request.form.get("instance_type")

        if not vm_name or architecture not in ARCHITECTURES or instance_type not in INSTANCE_TYPES:
            flash("Please fill in the form correctly.")
            return redirect(url_for("index"))

        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO vm_requests (user_id, vm_name, architecture, instance_type, status)
                    VALUES ((SELECT id FROM users WHERE username = %s), %s, %s, %s, 'PENDING')
                    RETURNING id
                    """,
                    (username, vm_name, architecture, instance_type),
                )
                request_id = cur.fetchone()[0]
            conn.commit()
        finally:
            conn.close()

        # Event 1: new record created on the DB
        publish_notification(
            "New VM request recorded",
            f"User '{username}' created request #{request_id}: "
            f"{vm_name} ({architecture}, {instance_type})",
        )

        send_request_message(
            {
                "request_id": request_id,
                "username": username,
                "vm_name": vm_name,
                "architecture": architecture,
                "instance_type": instance_type,
            }
        )

        flash("Request submitted.")
        return redirect(url_for("index"))

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT u.username, r.vm_name, r.architecture, r.instance_type, r.status, r.created_at
                FROM vm_requests r
                JOIN users u ON u.id = r.user_id
                ORDER BY r.created_at DESC
                """
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    return render_template(
        "index.html",
        username=username,
        architectures=ARCHITECTURES,
        instance_types=INSTANCE_TYPES,
        rows=rows,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
