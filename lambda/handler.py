# lambda/handler.py
import json, os, boto3, hashlib, base64

ddb = boto3.resource("dynamodb").Table(os.environ["TABLE"])

def _body(event):
    b = event.get("body") or ""
    if event.get("isBase64Encoded"):
        b = base64.b64decode(b).decode()
    return b

def lambda_handler(event, context):
    # method (v1 or v2)
    method = event.get("httpMethod")
    if not method and "requestContext" in event and "http" in event["requestContext"]:
        method = event["requestContext"]["http"]["method"]

    # POST -> create shortcode
    if method == "POST":
        try:
            data = json.loads(_body(event) or "{}")
            long_url = data["url"]
        except Exception as e:
            return {"statusCode": 400, "headers": {"Content-Type": "application/json"},
                    "body": json.dumps({"error": "Invalid body", "detail": str(e)})}
        code = hashlib.md5(long_url.encode()).hexdigest()[:6]
        ddb.put_item(Item={"shortcode": code, "url": long_url})
        return {"statusCode": 201, "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"short": code})}

    # GET -> redirect
    path_params = event.get("pathParameters") or {}
    code = path_params.get("code")
    if not code:
        return {"statusCode": 400, "body": "Missing code"}

    item = ddb.get_item(Key={"shortcode": code}).get("Item")
    if not item:
        return {"statusCode": 404, "body": "Not found"}

    return {"statusCode": 302, "headers": {"Location": item["url"]}, "body": ""}


