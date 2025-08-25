import os, sys, json
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

    # Create the table in moto
    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "shortcode", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "shortcode", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # POST to create
    post_event = {"httpMethod": "POST", "body": {"url": "example.com"}}
    post_res = lambda_handler(post_event, {})
    assert post_res["statusCode"] == 201
    body = json.loads(post_res["body"]) if isinstance(post_res["body"], str) else post_res["body"]
    code = body["shortcode"]
    assert code

    # GET to resolve
    get_event = {"httpMethod": "GET", "pathParameters": {"code": code}}
    get_res = lambda_handler(get_event, {})
    assert get_res["statusCode"] == 302
    assert get_res["headers"]["Location"] == "https://example.com"
