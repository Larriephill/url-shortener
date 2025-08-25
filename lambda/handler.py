import os
import json
import logging
import re
import time
from secrets import choice
from string import ascii_letters, digits

import boto3
from botocore.exceptions import ClientError

# -------- logging --------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# -------- config / constants --------
ALPHABET = ascii_letters + digits  # a-zA-Z0-9
CODE_LEN = 6
URL_RE = re.compile(r"^(https?://)?([A-Za-z0-9.-]+\.[A-Za-z]{2,})(:[0-9]+)?(/.*)?$")

# -------- DynamoDB table (lazy, cached) --------
_DDB_TABLE = None

def _get_table():
    """Lazily create and cache the DynamoDB Table object."""
    global _DDB_TABLE
    if _DDB_TABLE is None:
        table_name = os.environ["TABLE_NAME"]            # must be set
        region = os.environ.get("AWS_REGION", "eu-west-2")
        _DDB_TABLE = boto3.resource("dynamodb", region_name=region).Table(table_name)
    return _DDB_TABLE

def put_mapping(shortcode: str, long_url: str, ttl_epoch: int | None = None):
    """Write mapping; optionally include TTL attribute if you enable TTL."""
    item = {"shortcode": shortcode, "url": long_url}
    if ttl_epoch is not None:
        # DynamoDB TTL attribute must be named exactly "expiresAt" and be a Number
        item["expiresAt"] = ttl_epoch
    _get_table().put_item(Item=item, ConditionExpression="attribute_not_exists(shortcode)")

def get_mapping(shortcode: str):
    """Read mapping by shortcode."""
    resp = _get_table().get_item(Key={"shortcode": shortcode})
    return resp.get("Item")

# -------- helpers (pure functions where possible) --------
def normalize_url(url: str) -> str:
    """
    Ensures the URL has http/https scheme and looks roughly valid.
    Minimal check to avoid garbage; not a full RFC validator.
    """
    url = (url or "").strip()
    if not url:
        raise ValueError("URL is required")

    # Quick shape check
    if not URL_RE.match(url):
        raise ValueError("URL looks invalid")

    # Prepend scheme if missing
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    return url

def random_code(n: int = CODE_LEN) -> str:
    return "".join(choice(ALPHABET) for _ in range(n))

def response(status: int, body=None, headers=None):
    """Standard Lambda proxy V2 style response."""
    base_headers = {"Content-Type": "application/json"}
    if headers:
        base_headers.update(headers)
    if body is None or isinstance(body, (dict, list)):
        body = json.dumps(body or {})
    return {"statusCode": status, "headers": base_headers, "body": body}

# -------- main handler --------
def lambda_handler(event, context):
    """
    Supports:
      - POST /           with JSON {"url": "..."}
      - GET  /{code}     redirects (302) to the long URL
    Works with API Gateway HTTP API (Lambda proxy integration).
    """
    logger.info("event=%s", json.dumps(event))

    # Detect HTTP method for both REST and HTTP API events
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
    )
    method = (method or "").upper()

    # Path parameters for {code}
    path_params = event.get("pathParameters") or {}
    code_param = path_params.get("code")

    if method == "POST":
        # Parse body (string → dict)
        body = event.get("body") or ""
        try:
            payload = json.loads(body) if isinstance(body, str) else body
        except json.JSONDecodeError:
            return response(400, {"error": "Body must be valid JSON"})

        # Validate/normalize URL
        try:
            long_url = normalize_url(payload.get("url"))
        except ValueError as e:
            return response(400, {"error": str(e)})

        # TTL via environment (0 = disabled)
        try:
            ttl_days = int(os.getenv("TTL_DAYS", "0"))
        except ValueError:
            ttl_days = 0
        ttl_epoch = int(time.time()) + ttl_days * 24 * 3600 if ttl_days > 0 else None

        # Generate a unique code (retry on collision)
        for _ in range(5):
            code = random_code()
            try:
                put_mapping(code, long_url, ttl_epoch)  # will include expiresAt if provided
                logger.info("Created mapping %s -> %s (ttl_days=%s)", code, long_url, ttl_days)
                return response(201, {"shortcode": code, "long_url": long_url})
            except ClientError as ce:
                if ce.response["Error"]["Code"] == "ConditionalCheckFailedException":
                    # Collision; try another code
                    continue
                logger.exception("DynamoDB error on PutItem")
                return response(500, {"error": "Internal error"})
        return response(503, {"error": "Could not generate unique shortcode"})

    elif method == "GET" and code_param:
        item = get_mapping(code_param)
        if not item:
            return response(404, {"error": "Shortcode not found"})

        url = item["url"]
        # 302 redirect (body can be empty)
        return {
            "statusCode": 302,
            "headers": {"Location": url},
            "body": ""
        }

    else:
        return response(405, {"error": "Method not allowed"})
