import json
import os

import boto3

_region = os.environ.get("AWS_REGION", "il-central-1")
_sqs = boto3.client("sqs", region_name=_region)
_sns = boto3.client("sns", region_name=_region)

QUEUE_URL = os.environ["SQS_QUEUE_URL"]
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def publish_notification(subject: str, message: str) -> None:
    _sns.publish(TopicArn=TOPIC_ARN, Subject=subject[:100], Message=message)


def send_request_message(payload: dict) -> None:
    _sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(payload))
