import os, sys, json, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

import boto3
from moto import mock_aws
from handler import lambda_handler   # safe now because table is lazy-initialized

TABLE  = "urls_dev"
REGION = "eu-west-2"

@mock_aws
def test_post_then_get_redirects():
    # Make handler & moto use the same region and table name
    os.environ["AWS_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE
    os.environ["TTL_DAYS"]   = "1"  # 1 day TTL

    # Create the table in moto
    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "shortcode", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "shortcode", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # POST to create
    post_event = {"httpMethod": "POST", "body": json.dumps({"url": "example.com"})}
    post_res = lambda_handler(post_event, {})
    assert post_res["statusCode"] == 201
    body = json.loads(post_res["body"]) if isinstance(post_res["body"], str) else post_res["body"]
    code = body["short"]
    assert code

    # GET to resolve
    get_event = {"httpMethod": "GET", "pathParameters": {"code": code}}
    get_res = lambda_handler(get_event, {})
    assert get_res["statusCode"] == 302
    assert get_res["headers"]["Location"] == "https://example.com"


@mock_aws
def test_post_sets_ttl_and_get_redirects():
    # Env for handler and moto
    os.environ["AWS_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE
    os.environ["TTL_DAYS"]   = "1"  # 1 day TTL

    # Create table in moto
    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "shortcode", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "shortcode", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # POST -> creates item with expiresAt
    post_event = {"httpMethod": "POST", "body": json.dumps({"url": "example.com"})}
    post_res = lambda_handler(post_event, {})
    assert post_res["statusCode"] == 201
    body = json.loads(post_res["body"]) if isinstance(post_res["body"], str) else post_res["body"]
    code = body["shortcode"]
    assert code

    # Read the raw item with client (typed attributes)
    item = ddb.get_item(TableName=TABLE, Key={"shortcode": {"S": code}}).get("Item", {})
    assert "expiresAt" in item, "TTL attribute missing"
    ttl_val = int(item["expiresAt"]["N"])
    assert ttl_attr and int(ttl_attr["N"]) > int(time.time()) + 60 "TTL should be in the future"

    # GET -> 302 redirect still works
    get_event = {"httpMethod": "GET", "pathParameters": {"code": code}}
    get_res = lambda_handler(get_event, {})
    assert get_res["statusCode"] == 302
    assert get_res["headers"]["Location"] == "https://example.com"
