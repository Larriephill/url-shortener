 # lambda/handler.py

import json, os, boto3, hashlib, base64, time, logging

log = logging.getLogger()
if not log.handlers:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))

_table = None

def _get_table():
    global _table
    if _table is None:
        table_name = os.getenv("TABLE_NAME") or os.getenv("TABLE")
        if not table_name:
            raise RuntimeError("TABLE env var is not set")
        region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
        ddb = boto3.resource("dynamodb", region_name=region) if region else boto3.resource("dynamodb")
        _table = ddb.Table(table_name)
    return _table

def _parse_body(event):
    b = event.get("body")
    if isinstance(b, (dict, list)):
        return b
    if b is None:
        return {}
    if event.get("isBase64Encoded"):
        b = base64.b64decode(b).decode()
    return json.loads(b or "{}")

def _normalize_url(u: str) -> str:
    u = (u or "").strip()
    if not u.startswith(("http://", "https://")):
        return "https://" + u
    return u

def lambda_handler(event, context):
    log.info(json.dumps({
        "msg": "request",
        "stage": os.getenv("STAGE", "dev"),
        "method": event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method"),
        "path": (event.get("requestContext", {}).get("http", {}) or {}).get("path"),
        "requestId": (event.get("requestContext", {}) or {}).get("requestId")
    }))

    method = event.get("httpMethod")
    if not method and "requestContext" in event and "http" in event["requestContext"]:
        method = event["requestContext"]["http"]["method"]

    if method == "POST":
        try:
            data = _parse_body(event)
            long_url = _normalize_url(data["url"])
        except Exception as e:
            log.warning(json.dumps({"msg": "invalid_body", "error": str(e)}))
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Invalid body", "detail": str(e)}),
            }

        code = hashlib.md5(long_url.encode()).hexdigest()[:6]
        item = {"shortcode": code, "url": long_url}

        ttl_days = os.getenv("TTL_DAYS")
        if ttl_days:
            try:
                exp = int(time.time()) + int(ttl_days) * 86400
                item["expiresAt"] = exp  # canonical TTL field
            except Exception as e:
                log.warning(json.dumps({"msg": "bad_ttl_env", "error": str(e)}))

        _get_table().put_item(Item=item)
        log.info(json.dumps({"msg": "created", "shortcode": code}))
        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"short": code}),
        }

    # GET
    path_params = event.get("pathParameters") or {}
    code = path_params.get("code")
    if not code:
        return {"statusCode": 400, "body": "Missing code"}

    item = _get_table().get_item(Key={"shortcode": code}).get("Item")
    if not item:
        return {"statusCode": 404, "body": "Not found"}

    log.info(json.dumps({"msg": "redirect", "shortcode": code}))
    return {"statusCode": 302, "headers": {"Location": item["url"]}, "body": ""}

