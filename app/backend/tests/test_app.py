"""Basic test suite for the backend Flask app - added for the Jenkins CI
pipeline's Test stage (there was none before). Mocks the DB connection so
these run without a real Postgres instance; no AWS credentials needed either
since boto3 client construction alone doesn't make a network call.
"""
import os
import sys
from unittest.mock import MagicMock, patch

os.environ.setdefault("DB_HOST", "test-host")
os.environ.setdefault("DB_NAME", "test-db")
os.environ.setdefault("DB_USER", "test-user")
os.environ.setdefault("DB_PASSWORD", "test-password")
os.environ.setdefault("SQS_QUEUE_URL", "https://sqs.il-central-1.amazonaws.com/000000000000/test-queue")
os.environ.setdefault("SNS_TOPIC_ARN", "arn:aws:sns:il-central-1:000000000000:test-topic")
os.environ.setdefault("AWS_REGION", "il-central-1")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import db as db_module  # noqa: E402

_mock_conn = MagicMock()
_mock_conn.cursor.return_value.__enter__.return_value = MagicMock()

with patch.object(db_module, "get_connection", return_value=_mock_conn):
    import app as app_module  # noqa: E402

import pytest  # noqa: E402


@pytest.fixture
def client():
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as test_client:
        yield test_client


def test_architectures_and_instance_types_are_stable():
    # Regression guard: these values are relied on by the Helm chart's
    # ConfigMap-free form rendering and by the form-validation logic below -
    # changing them here without updating the UI/docs would be a real bug.
    assert app_module.ARCHITECTURES == ["64bit-x86", "64bit-arm"]
    assert app_module.INSTANCE_TYPES == ["t3-nano", "t3-micro", "t3-small"]


def test_login_page_loads(client):
    resp = client.get("/login")
    assert resp.status_code == 200


def test_register_page_loads(client):
    resp = client.get("/register")
    assert resp.status_code == 200


def test_index_requires_login(client):
    resp = client.get("/", follow_redirects=False)
    assert resp.status_code == 302
    assert "/login" in resp.headers["Location"]
