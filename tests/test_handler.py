# tests/test_handler.py
import os, sys, json, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

import boto3
from moto import mock_aws
from handler import lambda_handler

TABLE  = "urls_dev"
REGION = "eu-west-2"

@mock_aws
def test_post_then_get_redirects():
    os.environ["AWS_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE
    os.environ["TTL_DAYS"]   = "1"

    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "shortcode", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "shortcode", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # POST must be a JSON string (API Gateway style)
    post_event = {"httpMethod": "POST", "body": json.dumps({"url": "example.com"})}
    post_res = lambda_handler(post_event, {})
    assert post_res["statusCode"] == 201
    body = json.loads(post_res["body"]) if isinstance(post_res["body"], str) else post_res["body"]
    code = body["short"]
    assert code

    # GET -> 302 redirect
    get_event = {"httpMethod": "GET", "pathParameters": {"code": code}}
    get_res = lambda_handler(get_event, {})
    assert get_res["statusCode"] == 302
    assert get_res["headers"]["Location"] == "https://example.com"

@mock_aws
def test_post_sets_ttl_and_get_redirects():
    os.environ["AWS_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE
    os.environ["TTL_DAYS"]   = "1"

    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "shortcode", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "shortcode", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # POST -> 201 with code
    post_event = {"httpMethod": "POST", "body": json.dumps({"url": "example.com"})}
    post_res = lambda_handler(post_event, {})
    assert post_res["statusCode"] == 201
    body = json.loads(post_res["body"]) if isinstance(post_res["body"], str) else post_res["body"]
    code = body["short"]
    assert code

    # TTL attribute exists and is in the future
    item = ddb.get_item(TableName=TABLE, Key={"shortcode": {"S": code}}).get("Item", {})
    ttl_attr = item.get("expiresAt") or item.get("expires_at")
    assert ttl_attr and int(ttl_attr["N"]) > int(time.time()) + 60, "TTL should be in the future"

    # GET -> 302 redirect
    get_event = {"httpMethod": "GET", "pathParameters": {"code": code}}
    get_res = lambda_handler(get_event, {})
    assert get_res["statusCode"] == 302
    assert get_res["headers"]["Location"] == "https://example.com"
