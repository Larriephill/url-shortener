# lambda/handler.py
import os
import json
import time
import logging
import random
import string

import boto3
from botocore.exceptions import ClientError

# ---------- Logging (JSON) ----------
# Keep logs as plain JSON lines for CloudWatch Logs Insights friendliness
logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger(__name__)


def jlog(**kv):
    """Emit a JSON log line."""
    try:
        log.info(json.dumps(kv, default=str))
    except Exception:
        log.info(str(kv))


# ---------- Lazy AWS clients/resources ----------
_DDB_TABLE = None
_CW = None


def _get_table():
    """Lazy DynamoDB Table from env TABLE_NAME."""
    global _DDB_TABLE
    if _DDB_TABLE is None:
        table_name = os.environ.get("TABLE_NAME")
        if not table_name:
            raise RuntimeError("TABLE_NAME env var is required")
        region = os.environ.get("AWS_REGION", "eu-west-2")
        _DDB_TABLE = boto3.resource("dynamodb", region_name=region).Table(table_name)
    return _DDB_TABLE


def _cw():
    """Lazy CloudWatch client (for optional custom metrics)."""
    global _CW
    if _CW is None:
        region = os.environ.get("AWS_REGION", "eu-west-2")
        _CW = boto3.client("cloudwatch", region_name=region)
    return _CW


# ---------- Helpers ----------
def generate_shortcode(length: int = 6) -> str:
    """Random [A-Za-z0-9]{length}."""
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for _ in range(length))


def metric(name: str, value: float = 1.0, dims: list | None = None):
    """Send a custom metric if enabled via METRICS_ENABLED=true."""
    if os.getenv("METRICS_ENABLED", "false").lower() != "true":
        return
    try:
        dims = (dims or []) + [{"Name": "Stage", "Value": os.getenv("STAGE", "dev")}]
        _cw().put_metric_data(
            Namespace="UrlShortener",
            MetricData=[
                {
                    "MetricName": name,
                    "Value": float(value),
                    "Unit": "Count",
                    "Dimensions": dims,
                    "Timestamp": time.time(),
                }
            ],
        )
    except Exception as e:
        jlog(level="warn", msg="metric_failed", error=str(e))


def _get_method(event: dict) -> str:
    """
    Support both API Gateway v1 (REST) and v2 (HTTP API).
    v1: event['httpMethod']
    v2: event['requestContext']['http']['method']
    """
    m = event.get("httpMethod")
    if not m:
        m = (event.get("requestContext", {}).get("http", {}) or {}).get("method")
    return (m or "").upper()


def _get_json_body(event: dict) -> dict:
    """
    Body may be a dict (tests/direct invoke) or a JSON string (APIGW).
    Also handle base64 encoding if APIGW set isBase64Encoded=true.
    """
    body = event.get("body")
    if body is None:
        return {}
    if isinstance(body, dict):
        return body
    if event.get("isBase64Encoded"):
        import base64

        try:
            body = base64.b64decode(body).decode("utf-8")
        except Exception:
            return {}
    try:
        return json.loads(body)
    except Exception:
        return {}


def _get_path_param(event: dict, name: str) -> str:
    return (event.get("pathParameters") or {}).get(name, "")


# ---------- Data access ----------
def put_mapping(shortcode: str, long_url: str, ttl_epoch: int | None = None):
    """
    Create item and avoid overwriting an existing shortcode.
    Writes TTL field if provided.
    """
    item = {"shortcode": shortcode, "url": long_url}
    if ttl_epoch is not None:
        item["expiresAt"] = ttl_epoch  # DynamoDB TTL attribute (Number)

    _get_table().put_item(
        Item=item, ConditionExpression="attribute_not_exists(shortcode)"
    )


def get_mapping(shortcode: str) -> dict | None:
    resp = _get_table().get_item(Key={"shortcode": shortcode})
    return resp.get("Item")


# ---------- Lambda entry ----------
def lambda_handler(event, context):
    # Log the incoming event (redact body if you want; kept simple here)
    jlog(event=event, stage=os.getenv("STAGE", "dev"))

    method = _get_method(event)

    if method == "POST":
        data = _get_json_body(event)
        long_url = (data.get("url") or "").strip()
        if not long_url:
            return _json(400, {"error": "url is required"})
        if not long_url.startswith("http"):
            long_url = "https://" + long_url

        # TTL handling
        ttl_days = int(os.getenv("TTL_DAYS", "0"))
        ttl_epoch = int(time.time()) + ttl_days * 86400 if ttl_days > 0 else None

        # Create shortcode with simple collision retry
        attempts = 0
        while True:
            attempts += 1
            code = generate_shortcode()
            try:
                put_mapping(code, long_url, ttl_epoch)
                break
            except ClientError as e:
                if (
                    e.response.get("Error", {}).get("Code")
                    == "ConditionalCheckFailedException"
                    and attempts < 5
                ):
                    continue  # collision; try a new code
                raise

        metric("UrlCreatedCount", 1)
        return _json(201, {"shortcode": code, "long_url": long_url})

    if method == "GET":
        code = _get_path_param(event, "code")
        item = get_mapping(code) if code else None
        if not item:
            return _json(404, {"error": "Not found"})
        metric("RedirectCount", 1)
        return {
            "statusCode": 302,
            "headers": {"Location": item["url"]},
            "body": "",
        }

    return _json(405, {"error": "Method not allowed"})


# ---------- Response helpers ----------
def _json(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
