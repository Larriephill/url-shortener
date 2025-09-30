# URL Shortener (Serverless, AWS)

A serverless URL shortener built on **AWS Lambda**, **API Gateway**, and **DynamoDB**.  
It creates short links via `POST` requests and redirects users with `GET` requests.

---

## Introduction

This project is a serverless URL shortener designed to demonstrate practical **DevOps and cloud engineering skills**.  
It shows how to build, provision, and operate a small but complete application on AWS using **Infrastructure as Code (Terraform)** and a **CI/CD pipeline (GitHub Actions + OIDC)**.

While URL shorteners already exist, this project serves as a **portfolio piece** to highlight:
- Designing a real-world serverless architecture on AWS.
- Automating deployments with modern DevOps practices.
- Implementing observability (metrics, alarms, dashboards).
- Managing multi-environment infrastructure (dev & prod) securely without long-lived AWS keys.

---

## 🏗️ Architecture Diagram
<img width="1536" height="1024" alt="Architecture Diagram" src="https://github.com/user-attachments/assets/1f37a9a7-5a08-489b-8bb6-9cf2bd994d11" />

![Architecture Diagram](A_diagram_in_a_digital_image_illustrates_the_archi.png)

**AWS services used:**
- API Gateway (HTTP API) — exposes endpoints and maps to custom domain
- Lambda (Python 3.12) — handles create/redirect logic
- DynamoDB — stores shortcodes, original URLs, and optional expiry with TTL
- CloudWatch — alarms and dashboards for monitoring
- Route 53 + ACM — custom domain `api.regalhorizon.click`

---

## 🚀 User Instructions

### 1. Deploy (Dev Environment)

**Prerequisites:**
- Terraform ≥ 1.9
- AWS CLI configured with permissions
- Python 3.12

**Steps:**

```bash
# 1. Navigate to terraform directory
cd terraform

# 2. Create backend config for dev
cat > backend-dev.hcl <<'HCL'
bucket         = "urlshortenerlarriephill"
key            = "state/dev/terraform.tfstate"
region         = "eu-west-2"
dynamodb_table = "tf-lock-dev"
encrypt        = true
HCL

# 3. Initialize Terraform with backend
terraform init -reconfigure -backend-config=backend-dev.hcl

# 4. Deploy to dev
terraform apply -auto-approve -var="stage=dev"
```

After apply, Terraform will output the **API base URL**. Save it in an environment variable:

```bash
API=$(terraform output -raw api_base_url)
```

---

### 2. Test the API

**Create a short link (POST /**):**

```bash
curl -sS -H 'Content-Type: application/json'   -d '{"url":"https://example.com"}' "$API"
# => {"short":"<code>"}
```

**Resolve a short link (GET /{code}):**

```bash
curl -i "$API/<code>"
# Expect: HTTP/1.1 302 Found
# Location: https://example.com
```

---

### 3. Production Deployment

Prod is deployed via **GitHub Actions** CI/CD (`deploy-prod.yml`) using OIDC to assume an AWS role.  
You can also deploy manually with a `backend-prod.hcl` file (similar to dev).

---

## ⚠️ Known Issues & Limitations

### Problems Faced
- **API Mapping Conflicts**: Sometimes `api.regalhorizon.click` already had an API mapping; solution was to import or delete the existing mapping with `aws apigatewayv2 get-api-mappings`.
- **CI AccessDenied Errors**: Initial GitHub Actions runs failed because the IAM role lacked certain permissions. Fixed by adding read/list permissions for Lambda, Route53, ACM, and CloudWatch Dashboards.
- **CNAMEAlreadyExists Errors**: Encountered when setting up the custom domain; solved by avoiding CloudFront/WAF and sticking with API Gateway’s native custom domain.

### Intentional Limitations
- **No CloudFront / WAF**: Left out to keep the project simple and low-cost for a personal portfolio.  
- **No Authentication or Rate Limiting**: All endpoints are public; suitable for demo purposes but not production.  
- **No Analytics / Expiry Management**: DynamoDB supports TTL, but advanced analytics and link deletion were not implemented.  
- **Basic Error Handling**: Focused on core functionality; minimal error responses (400/404).

---

## 🔮 Future Improvements

To make this project production-grade, I would add the following:

- **Rate Limiting & Usage Plans**: Use API Gateway usage plans to prevent abuse and control traffic.  
- **Authentication & Authorization**: Introduce authentication (e.g., Cognito or IAM-based auth) so only authorized users can create or manage short links.  
- **Analytics & Reporting**: Capture request metrics (click counts, request sources) using DynamoDB Streams with a Lambda consumer or Firehose → S3 for analysis.  
- **Link Management**: Add endpoints to delete or update short links, and improve TTL expiry handling.  
- **Automated Testing**: Add unit tests for the Lambda handler and load tests with k6 to validate performance at scale.  
- **OpenAPI Documentation**: Publish an OpenAPI/Swagger spec for the API to make it easier to integrate with external clients.  
- **CI/CD Enhancements**: Add static code analysis, linting, and test execution in the GitHub Actions pipeline before deployment.  
- **Front-End Integration**: Build a simple React/Next.js front-end where users can generate and manage short links instead of relying only on API calls.

---

## 📂 Repository Structure

```
url-shortener/
├── lambda/
│   └── handler.py              # Core Lambda logic (create + redirect)
│
├── terraform/                  # Infrastructure as Code (Terraform 1.9.x)
│   ├── main.tf                 # Root Terraform config
│   ├── lambda.tf               # Lambda definition & packaging
│   ├── apigw.tf                # API Gateway HTTP API + routes
│   ├── domain.tf               # Custom domain + Route 53 + ACM
│   ├── iam.tf                  # Base IAM roles & policies
│   ├── iam_ci.tf               # CI/CD IAM roles
│   ├── iam_ci_apply.tf         # Dev apply role
│   ├── iam_ci_apply_prod.tf    # Prod apply role
│   ├── iam_oidc.tf             # GitHub OIDC provider
│   ├── observability.tf        # CloudWatch metrics, alarms, dashboard
│   ├── variables.tf            # Input variables
│   └── env.tf                  # Stage-specific values
│
├── .github/workflows/          # GitHub Actions pipelines
│   ├── deploy-dev.yml
│   └── deploy-prod.yml
│
├── verify.sh                   # Smoke test (runs after deploy)
└── README.md                   # Project documentation
```

---

## 📜 License & Credits

This project is released under the **MIT License**.  

Built by **Oluwaseyi Abiola** — connect with me on [LinkedIn](https://www.linkedin.com/in/philipabiola).  

> I created this project out of a strong interest in **DevOps and Cloud Engineering**, to put theory into practice and gain hands-on experience with **Terraform, CI/CD, and AWS serverless services**.
