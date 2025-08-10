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

# -------- config --------
TABLE_NAME = os.environ.get("TABLE", "")
if not TABLE_NAME:
    # We'll set TABLE with Terraform when we create the Lambda resource.
    logger.warning("Environment variable TABLE is not set yet.")

ddb = boto3.resource("dynamodb").Table(TABLE_NAME) if TABLE_NAME else None

ALPHABET = ascii_letters + digits  # a-zA-Z0-9
CODE_LEN = 6
URL_RE = re.compile(r"^(https?://)?([A-Za-z0-9.-]+\.[A-Za-z]{2,})(:[0-9]+)?(/.*)?$")


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


# -------- DynamoDB operations --------
def put_mapping(shortcode: str, long_url: str, ttl_epoch: int | None = None):
    item = {"shortcode": shortcode, "url": long_url}
    if ttl_epoch:
        item["expiresAt"] = ttl_epoch  # only if you enabled TTL on the table

    # Avoid overwriting an existing code
    ddb.put_item(
        Item=item,
        ConditionExpression="attribute_not_exists(shortcode)"
    )


def get_mapping(shortcode: str) -> str | None:
    res = ddb.get_item(Key={"shortcode": shortcode})
    item = res.get("Item")
    return item["url"] if item else None


# -------- main handler --------
def lambda_handler(event, context):
    """
    Supports:
      - POST /           with JSON {"url": "...", "ttl_seconds": <optional>}
      - GET  /{code}     redirects (302) to the long URL
    Works with API Gateway HTTP API (Lambda proxy integration).
    """
    logger.info("event=%s", json.dumps(event))

    # Detect HTTP method for both REST and HTTP API events
    method = (
        event.get("httpMethod") or
        event.get("requestContext", {}).get("http", {}).get("method")
    )

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

        # Optional TTL
        ttl_seconds = payload.get("ttl_seconds")
        ttl_epoch = int(time.time()) + int(ttl_seconds) if ttl_seconds else None

        # Generate a unique code (retry on collision)
        for _ in range(5):
            code = random_code()
            try:
                put_mapping(code, long_url, ttl_epoch)
                logger.info("Created mapping %s -> %s", code, long_url)
                return response(201, {"shortcode": code, "long_url": long_url})
            except ClientError as ce:
                if ce.response["Error"]["Code"] == "ConditionalCheckFailedException":
                    # Collision; try another code
                    continue
                logger.exception("DynamoDB error on PutItem")
                return response(500, {"error": "Internal error"})
        return response(503, {"error": "Could not generate unique shortcode"})

    elif method == "GET" and code_param:
        url = get_mapping(code_param)
        if not url:
            return response(404, {"error": "Shortcode not found"})

        # 302 redirect (body can be empty)
        return {
            "statusCode": 302,
            "headers": {"Location": url},
            "body": ""
        }

    else:
        return response(405, {"error": "Method not allowed"})
