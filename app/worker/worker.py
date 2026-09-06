import json
import os

import boto3
import psycopg2

REGION = os.environ.get("AWS_REGION", "il-central-1")
QUEUE_URL = os.environ["SQS_QUEUE_URL"]
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
BUCKET = os.environ["S3_BUCKET"]

sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)


def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )


def publish(subject: str, message: str) -> None:
    sns.publish(TopicArn=TOPIC_ARN, Subject=subject[:100], Message=message)


def process_message(body: str) -> None:
    data = json.loads(body)
    request_id = data["request_id"]
    key = f"user-choices/{request_id}.json"

    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=json.dumps(data, indent=2).encode("utf-8"),
        ContentType="application/json",
    )
    # Event 2: new file uploaded to S3
    publish("File uploaded to S3", f"Saved request #{request_id} choices to s3://{BUCKET}/{key}")

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE vm_requests SET status = 'COMPLETED', s3_key = %s, updated_at = now() WHERE id = %s",
                (key, request_id),
            )
        conn.commit()
    finally:
        conn.close()

    # Event 3: status changed on the application
    publish("VM request status changed", f"Request #{request_id} status changed to COMPLETED")


def main() -> None:
    print(f"worker started, polling {QUEUE_URL}", flush=True)
    while True:
        resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=20)
        for msg in resp.get("Messages", []):
            try:
                process_message(msg["Body"])
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
            except Exception as exc:  # noqa: BLE001 - keep polling regardless of one bad message
                print(f"failed to process message: {exc}", flush=True)


if __name__ == "__main__":
    main()
