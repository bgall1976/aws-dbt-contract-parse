# AWS dbt Contract Parse Pipeline

An end-to-end data pipeline that extracts structured data from healthcare contract PDFs using AI (Docling), loads it into Redshift Serverless, and transforms it with dbt into an analytics-ready dimensional model.

---

## Architecture Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   PDF       │     │    S3       │     │    SQS      │     │    ECS      │
│  Contracts  │────▶│  Raw Bucket │────▶│   Queue     │────▶│  Fargate    │
└─────────────┘     └─────────────┘     └─────────────┘     │  (Docling)  │
                                                            └──────┬──────┘
                                                                   │
                    ┌─────────────┐     ┌─────────────┐            │
                    │    dbt      │     │  Redshift   │     ┌──────▼──────┐
                    │  Transform  │◀────│  Serverless │◀────│     S3      │
                    │  (Star      │     │   (COPY)    │     │  Processed  │
                    │   Schema)   │     └─────────────┘     │   (JSON)    │
                    └─────────────┘                         └─────────────┘
```

**Data Flow:**
1. Upload PDF contract to S3 raw bucket
2. S3 event triggers SQS message
3. ECS Fargate container polls SQS, downloads PDF
4. Docling + AI extracts structured data from PDF
5. JSON output saved to S3 processed bucket
6. COPY command loads JSON into Redshift
7. dbt transforms raw data into star schema

---

## Project Structure

```
aws-dbt-contract-parse/
├── extraction/                 # Docling PDF extraction service
│   ├── Dockerfile
│   ├── requirements.txt
│   └── src/
│       ├── extractor.py       # Main entry point with SQS polling
│       ├── docling_parser.py  # PDF parsing with Docling
│       ├── contract_schema.py # Pydantic schemas
│       └── s3_handler.py      # S3 upload/download
├── dbt_project/               # dbt transformation models
│   ├── dbt_project.yml
│   ├── models/
│   │   ├── staging/           # stg_contracts, stg_rate_schedules, stg_amendments
│   │   ├── intermediate/      # int_contracts_enriched, int_rates_normalized
│   │   └── marts/core/        # dim_*, fact_contracted_rates
│   ├── seeds/                 # Reference data (ref_payers, ref_service_categories)
│   └── snapshots/             # SCD Type 2 tracking
├── scripts/
│   ├── create_infra/          # AWS infrastructure scripts (01-11)
│   └── teardown/              # Cleanup scripts
└── sample-contract.pdf        # Test PDF
```

---

## Prerequisites

- **AWS Account** with admin permissions
- **AWS CLI v2** installed and configured
- **Docker Desktop** for Windows (with WSL 2)
- **Python 3.10+**
- **Git**

---

## Deployment Guide

### Phase 1: AWS Infrastructure Setup

Run these commands in **AWS CloudShell** (accessed via AWS Console top navigation bar).

#### Step 1.1: Set Environment Variables

```bash
export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2
export REDSHIFT_ADMIN_PASSWORD='YourSecurePassword123!'
```

> **Password Requirements:** 8+ characters, uppercase, lowercase, number

#### Step 1.2: Clone Repository

```bash
cd ~
git clone https://github.com/bgall1976/aws-dbt-contract-parse.git
cd aws-dbt-contract-parse/scripts/create_infra
chmod +x *.sh
```

#### Step 1.3: Run Infrastructure Scripts

```bash
bash 01-create-s3-buckets.sh
bash 02-create-sqs-queue.sh
bash 03-configure-s3-events.sh
bash 04-create-ecr-repo.sh
bash 05-create-iam-roles.sh
bash 06-create-cloudwatch-logs.sh
bash 07-create-ecs-cluster.sh
bash 08-create-ecs-task-definition.sh
bash 09-create-redshift.sh        # Takes 5-10 minutes
bash 10-summary.sh
```

#### Step 1.4: Note Your Resource Names

After `10-summary.sh`, save these values:

```
AWS_ACCOUNT_ID=<your-account-id>
S3_RAW_BUCKET=contract-pipeline-raw-dev-<account-id>
S3_PROCESSED_BUCKET=contract-pipeline-processed-dev-<account-id>
SQS_QUEUE_URL=https://sqs.us-east-2.amazonaws.com/<account-id>/contract-pipeline-queue-dev
ECR_REPO=<account-id>.dkr.ecr.us-east-2.amazonaws.com/contract-pipeline-dev
```

---

### Phase 2: Build and Deploy Docker Image

Run these in **Windows Command Prompt** (not PowerShell).

#### Step 2.1: Navigate to Project

```cmd
cd C:\Users\<YourUsername>\Documents\github_portfolio\aws-dbt-contract-parse\extraction
```

#### Step 2.2: Login to ECR

Replace `<account-id>` with your AWS account ID:

```cmd
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-2.amazonaws.com
```

#### Step 2.3: Build Docker Image

```cmd
docker build -t contract-extractor .
```

> **Build time:** 5-10 minutes (downloads Docling models)

#### Step 2.4: Tag and Push to ECR

```cmd
docker tag contract-extractor:latest <account-id>.dkr.ecr.us-east-2.amazonaws.com/contract-pipeline-dev:latest

docker push <account-id>.dkr.ecr.us-east-2.amazonaws.com/contract-pipeline-dev:latest
```

---

### Phase 3: Create ECS Service

Run in **AWS CloudShell**:

#### Step 3.1: Get Network Configuration

```bash
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" --query 'Subnets[0].SubnetId' --output text)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=contract-pipeline-redshift-sg" --query 'SecurityGroups[0].GroupId' --output text)

echo "VPC: $DEFAULT_VPC_ID"
echo "Subnet: $SUBNET_ID"
echo "Security Group: $SG_ID"
```

#### Step 3.2: Create ECS Service

```bash
aws ecs create-service \
    --cluster contract-pipeline-dev \
    --service-name contract-extractor \
    --task-definition contract-pipeline-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region us-east-2
```

#### Step 3.3: Update Task Definition for SQS Polling (if needed)

If the container isn't polling SQS, register an updated task definition. Run this as a **single line** in Windows CMD:

```cmd
aws ecs register-task-definition --family contract-pipeline-task --network-mode awsvpc --requires-compatibilities FARGATE --cpu "1024" --memory "2048" --execution-role-arn "arn:aws:iam::<account-id>:role/contract-pipeline-ecs-execution-role" --task-role-arn "arn:aws:iam::<account-id>:role/contract-pipeline-ecs-task-role" --container-definitions "[{\"name\":\"extractor\",\"image\":\"<account-id>.dkr.ecr.us-east-2.amazonaws.com/contract-pipeline-dev:latest\",\"essential\":true,\"command\":[\"--poll\"],\"environment\":[{\"name\":\"AWS_REGION\",\"value\":\"us-east-2\"},{\"name\":\"S3_RAW_BUCKET\",\"value\":\"contract-pipeline-raw-dev-<account-id>\"},{\"name\":\"S3_PROCESSED_BUCKET\",\"value\":\"contract-pipeline-processed-dev-<account-id>\"},{\"name\":\"SQS_QUEUE_URL\",\"value\":\"https://sqs.us-east-2.amazonaws.com/<account-id>/contract-pipeline-queue-dev\"}],\"logConfiguration\":{\"logDriver\":\"awslogs\",\"options\":{\"awslogs-group\":\"/ecs/contract-pipeline-dev\",\"awslogs-region\":\"us-east-2\",\"awslogs-stream-prefix\":\"extractor\"}}}]" --region us-east-2
```

Then force a new deployment:

```cmd
aws ecs update-service --cluster contract-pipeline-dev --service contract-extractor --task-definition contract-pipeline-task --force-new-deployment --region us-east-2
```

---

### Phase 4: Test PDF Extraction

#### Step 4.1: Check ECS Service is Running

```cmd
aws ecs describe-services --cluster contract-pipeline-dev --services contract-extractor --region us-east-2 --query "services[0].deployments[0].{status:status,runningCount:runningCount,taskDefinition:taskDefinition}"
```

Expected output: `runningCount: 1`

#### Step 4.2: Upload Test PDF

```cmd
aws s3 cp sample-contract.pdf s3://contract-pipeline-raw-dev-<account-id>/incoming/
```

#### Step 4.3: Monitor Logs

```cmd
aws logs tail /ecs/contract-pipeline-dev --follow --region us-east-2
```

You should see:
- RapidOCR model downloads
- "Processing PDF" messages
- "Successfully processed PDF" messages

#### Step 4.4: Verify Output

```cmd
aws s3 ls s3://contract-pipeline-processed-dev-<account-id>/contracts/ --recursive --region us-east-2
```

---

### Phase 5: Redshift Setup

#### Step 5.1: Create IAM Role for Redshift S3 Access

Run in Windows CMD:

```cmd
aws iam create-role --role-name contract-pipeline-redshift-role --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"redshift.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}" --region us-east-2

aws iam attach-role-policy --role-name contract-pipeline-redshift-role --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

aws redshift-serverless update-namespace --namespace-name contract-pipeline-dev --iam-roles "arn:aws:iam::<account-id>:role/contract-pipeline-redshift-role" --region us-east-2
```

#### Step 5.2: Get Redshift Endpoint

```cmd
aws redshift-serverless get-workgroup --workgroup-name contract-pipeline-workgroup-dev --region us-east-2 --query "workgroup.endpoint.address" --output text
```

Save this endpoint for dbt configuration.

#### Step 5.3: Create Table and Load Data

1. Go to **AWS Console → Redshift → Query Editor v2**
2. Connect to `contract-pipeline-workgroup-dev`
   - Database: `contracts_dw`
   - User: `admin`
   - Password: (your password)

3. Run this SQL:

```sql
-- Create raw_contracts table
CREATE TABLE IF NOT EXISTS public.raw_contracts (
    contract_id VARCHAR(100),
    payer_name VARCHAR(255),
    payer_id VARCHAR(50),
    provider_npi VARCHAR(20),
    provider_name VARCHAR(255),
    effective_date VARCHAR(50),
    termination_date VARCHAR(50),
    rate_schedules SUPER,
    amendments SUPER,
    extraction_metadata SUPER,
    loaded_at TIMESTAMP DEFAULT GETDATE()
);

-- Load data from S3
COPY public.raw_contracts (
    contract_id, payer_name, payer_id, provider_npi, provider_name,
    effective_date, termination_date, rate_schedules, amendments, extraction_metadata
)
FROM 's3://contract-pipeline-processed-dev-<account-id>/contracts/'
IAM_ROLE 'arn:aws:iam::<account-id>:role/contract-pipeline-redshift-role'
FORMAT AS JSON 'auto'
REGION 'us-east-2';

-- Verify data loaded
SELECT * FROM public.raw_contracts;
```

---

### Phase 6: dbt Setup and Run

#### Step 6.1: Create Python Virtual Environment

```cmd
cd C:\Users\<YourUsername>\Documents\github_portfolio\aws-dbt-contract-parse
python -m venv venv
venv\Scripts\activate
pip install dbt-redshift
```

#### Step 6.2: Configure dbt Profile

Create/edit `C:\Users\<YourUsername>\.dbt\profiles.yml`:

```yaml
contract_pipeline:
  target: dev
  outputs:
    dev:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      port: 5439
      user: "{{ env_var('REDSHIFT_USER') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD') }}"
      dbname: contracts_dw
      schema: public
      threads: 4
```

#### Step 6.3: Set Environment Variables

```cmd
set REDSHIFT_HOST=contract-pipeline-workgroup-dev.<account-id>.us-east-2.redshift-serverless.amazonaws.com
set REDSHIFT_PORT=5439
set REDSHIFT_USER=admin
set REDSHIFT_PASSWORD=YourSecurePassword123!
set REDSHIFT_DATABASE=contracts_dw
```

#### Step 6.4: Update dbt Source Configuration

Edit `dbt_project\models\sources\_sources.yml`:

```yaml
version: 2

sources:
  - name: raw_contracts
    description: Raw contract data loaded from S3
    database: contracts_dw
    schema: public
    tables:
      - name: raw_contracts
        description: Contract JSON loaded via COPY command
```

#### Step 6.5: Test Connection and Run dbt

```cmd
cd dbt_project

dbt debug
dbt run
```

Expected output:
```
Completed successfully
Done. PASS=11 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=11
```

#### Step 6.6: Verify Results in Redshift

```sql
-- Staging layer
SELECT * FROM public_staging.stg_contracts;

-- Dimension tables
SELECT * FROM public_marts.dim_contract;
SELECT * FROM public_marts.dim_payer;
SELECT * FROM public_marts.dim_provider;

-- Fact table (empty if no rate schedules in source PDF)
SELECT * FROM public_marts.fact_contracted_rates;
```

---

## Data Model

### Star Schema

```
                    ┌─────────────────┐
                    │   dim_date      │
                    └────────┬────────┘
                             │
┌─────────────┐    ┌────────┴────────┐    ┌─────────────┐
│ dim_payer   │────│ fact_contracted │────│ dim_provider│
└─────────────┘    │     _rates      │    └─────────────┘
                   └────────┬────────┘
                            │
┌─────────────┐    ┌────────┴────────┐
│ dim_service │────│  dim_contract   │
└─────────────┘    └─────────────────┘
```

### Model Layers

| Layer | Models | Description |
|-------|--------|-------------|
| **Staging** | `stg_contracts`, `stg_rate_schedules`, `stg_amendments` | Cleaned, typed source data |
| **Intermediate** | `int_contracts_enriched`, `int_rates_normalized` | Business logic, aggregations |
| **Marts** | `dim_*`, `fact_contracted_rates` | Analytics-ready star schema |

---

## Troubleshooting

### ECS Container Keeps Restarting

**Symptom:** Container restarts every ~3 minutes

**Cause:** Out of memory (Docling + OCR models need >1GB)

**Fix:** Update task definition to 2GB memory:
```cmd
aws ecs register-task-definition ... --memory "2048" ...
```

### OpenCV Import Error

**Symptom:** `ImportError: libGL.so.1: cannot open shared object file`

**Fix:** Add to Dockerfile:
```dockerfile
RUN apt-get update && apt-get install -y libgl1 libglib2.0-0
```

### OCR Model Permission Error

**Symptom:** `PermissionError: [Errno 13] Permission denied: ...rapidocr/models/`

**Fix:** Add to Dockerfile before switching to non-root user:
```dockerfile
RUN python -c "from rapidocr import RapidOCR; RapidOCR()" || true
RUN chmod -R 777 /usr/local/lib/python3.11/site-packages/rapidocr/models || true
```

### dbt "database does not exist" Error

**Symptom:** `"contracts_dw" does not exist`

**Fix:** Ensure `_sources.yml` references correct table name:
```yaml
tables:
  - name: raw_contracts  # Must match actual table name
```

### COPY Command Fails

**Symptom:** Access denied or no files found

**Fix:**
1. Verify IAM role is attached to Redshift namespace
2. Check S3 path matches where JSON files are located
3. Ensure JSON files exist: `aws s3 ls s3://bucket/contracts/ --recursive`

---

## Cost Management

| Service | Estimated Monthly Cost |
|---------|------------------------|
| Redshift Serverless | $0 (idle) - $50+ (active queries) |
| ECS Fargate | $0 (stopped) - $30+ (running 24/7) |
| S3 | < $1 |
| SQS | < $1 |
| ECR | < $1 |
| **Total (idle)** | **< $5/month** |

### Stop ECS to Save Costs

```cmd
aws ecs update-service --cluster contract-pipeline-dev --service contract-extractor --desired-count 0 --region us-east-2
```

### Restart ECS When Needed

```cmd
aws ecs update-service --cluster contract-pipeline-dev --service contract-extractor --desired-count 1 --region us-east-2
```

---

## Tear Down Infrastructure

Run in **AWS CloudShell** to delete all resources:

```bash
cd ~/aws-dbt-contract-parse/scripts/teardown
chmod +x *.sh

bash 01-delete-ecs-services.sh
bash 02-delete-ecs-task-definitions.sh
bash 03-delete-ecs-cluster.sh
bash 04-delete-redshift.sh
bash 05-delete-ecr-repo.sh
bash 06-delete-s3-buckets.sh
bash 07-delete-sqs-queues.sh
bash 08-delete-iam-roles.sh
bash 09-delete-cloudwatch-logs.sh
bash 10-delete-security-groups.sh
bash 11-summary.sh
```

---

## License

MIT License - see [LICENSE](LICENSE) for details.
