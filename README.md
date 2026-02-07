# Healthcare Contract PDF Ingestion Pipeline

A production-ready data engineering pipeline that ingests healthcare provider contract PDFs, extracts structured data using AI-powered document processing, and models the results for analysis in a cloud data warehouse.

## 🎯 Project Overview

This project demonstrates an end-to-end document processing pipeline using modern cloud-native technologies:

- **AWS S3** as data lake landing zones (raw PDFs → structured JSON)
- **AWS ECS** for containerized document extraction service
- **Docling** for AI-powered PDF parsing and data extraction
- **Amazon Redshift** as the analytical data warehouse
- **dbt** for transformation, testing, and SCD Type 2 modeling
- **GitHub Actions** for CI/CD automation

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        PDF CONTRACT INGESTION PIPELINE                                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌──────────────┐    ┌──────────────────────┐    ┌──────────────────────────────────┐  │
│  │   INGEST     │    │      EXTRACT         │    │           TRANSFORM              │  │
│  │              │    │                      │    │                                  │  │
│  │ ┌──────────┐ │    │  ┌────────────────┐  │    │  ┌────────────────────────────┐  │  │
│  │ │ Contract │ │    │  │  ECS Fargate   │  │    │  │      Amazon Redshift       │  │  │
│  │ │   PDFs   │─┼───▶│  │   Container    │──┼───▶│  │                            │  │  │
│  │ └──────────┘ │    │  │                │  │    │  │  ┌─────────┐  ┌─────────┐  │  │  │
│  │      │       │    │  │  ┌──────────┐  │  │    │  │  │ Staging │─▶│  Marts  │  │  │  │
│  │      ▼       │    │  │  │ Docling  │  │  │    │  │  └─────────┘  └─────────┘  │  │  │
│  │ ┌──────────┐ │    │  │  │  Parser  │  │  │    │  │       │            │       │  │  │
│  │ │    S3    │ │    │  │  └──────────┘  │  │    │  │       ▼            ▼       │  │  │
│  │ │   Raw    │ │    │  └────────────────┘  │    │  │  ┌─────────┐  ┌─────────┐  │  │  │
│  │ │  Bucket  │ │    │          │           │    │  │  │   dbt   │  │ dim_    │  │  │  │
│  │ └──────────┘ │    │          ▼           │    │  │  │  Tests  │  │contract │  │  │  │
│  │              │    │  ┌────────────────┐  │    │  │  └─────────┘  │ (SCD2)  │  │  │  │
│  │              │    │  │      S3        │  │    │  │               └─────────┘  │  │  │
│  │              │    │  │   Processed    │──┼───▶│  │                            │  │  │
│  │              │    │  │    (JSON)      │  │    │  └────────────────────────────┘  │  │
│  │              │    │  └────────────────┘  │    │                                  │  │
│  └──────────────┘    └──────────────────────┘    └──────────────────────────────────┘  │
│                                                                                         │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              CI/CD (GitHub Actions)                               │  │
│  │  PR → dbt compile + test (dev) │ Merge → Deploy models + trigger pipeline (prod) │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Contract   │     │   Docling   │     │  Structured │     │  Redshift   │
│    PDF      │────▶│  Extraction │────▶│    JSON     │────▶│    dbt      │
│             │     │             │     │             │     │   Models    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
     │                    │                    │                   │
     ▼                    ▼                    ▼                   ▼
 s3://raw/          ECS Fargate         s3://processed/      dim_contract
 contracts/         + Docling           contracts/           fact_rates
                                        {payer}/{date}/      (SCD Type 2)
```

## 📋 Prerequisites

- **AWS Account** with permissions for S3, ECS, ECR, Redshift, IAM
- **Python 3.11+**
- **Docker** for local development and container builds
- **Terraform** (optional, for infrastructure provisioning)
- **dbt Core 1.7+**
- Git and GitHub account

---

## 🚀 Quick Start (Windows)

### Step 1: Clone the Repository

```cmd
git clone https://github.com/bgall1976/pdf-contract-pipeline.git
cd pdf-contract-pipeline
```

**What this does:**
- Downloads the complete project from GitHub to your local machine
- Changes into the project directory

---

### Step 2: Create Virtual Environment

```cmd
python -m venv venv
venv\Scripts\activate
```

**What this does:**
- Creates an isolated Python environment
- Activates it (you'll see `(venv)` in your prompt)

---

### Step 3: Install Dependencies

```cmd
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

**What this does:**
- Installs all required Python packages including dbt-redshift, docling, boto3

---

### Step 4: Set Environment Variables

**⚠️ IMPORTANT: Run each command on a separate line!**

```cmd
set AWS_ACCESS_KEY_ID=your_access_key
set AWS_SECRET_ACCESS_KEY=your_secret_key
set AWS_REGION=us-east-1
set REDSHIFT_HOST=your-cluster.xxxx.us-east-1.redshift.amazonaws.com
set REDSHIFT_PORT=5439
set REDSHIFT_USER=admin
set "REDSHIFT_PASSWORD=your_password_here"
set REDSHIFT_DATABASE=contracts_dw
set S3_RAW_BUCKET=your-raw-contracts-bucket
set S3_PROCESSED_BUCKET=your-processed-contracts-bucket
```

**⚠️ Note:** If your password contains special characters, wrap the command in quotes.

---

### Step 5: Create dbt Profile

```cmd
mkdir %USERPROFILE%\.dbt
copy profiles\profiles.yml %USERPROFILE%\.dbt\profiles.yml
```

**What this does:**
- Creates the dbt configuration directory
- Copies the Redshift connection profile

---

### Step 6: Test dbt Connection

```cmd
dbt debug
```

**Expected output:**
```
Connection test: [OK connection ok]
All checks passed!
```

---

### Step 7: Install dbt Packages

```cmd
dbt deps
```

**What this does:**
- Installs dbt packages like `dbt-utils` for helper macros

---

### Step 8: Run the Pipeline

```cmd
# Load seed data (reference tables)
dbt seed

# Run all models
dbt run

# Run data quality tests
dbt test
```

---

## 📁 Project Structure

```
pdf-contract-pipeline/
│
├── README.md                           # This file
├── requirements.txt                    # Python dependencies
├── docker-compose.yml                  # Local development setup
│
├── extraction/                         # PDF extraction service
│   ├── Dockerfile                      # Container definition
│   ├── requirements.txt                # Extraction dependencies
│   ├── src/
│   │   ├── __init__.py
│   │   ├── extractor.py               # Main extraction logic
│   │   ├── docling_parser.py          # Docling PDF parser
│   │   ├── contract_schema.py         # Output JSON schema
│   │   └── s3_handler.py              # S3 read/write operations
│   └── tests/
│       ├── test_extractor.py
│       └── sample_contracts/           # Test PDFs
│
├── infrastructure/                     # Terraform IaC
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── s3/
│   │   ├── ecs/
│   │   ├── ecr/
│   │   └── redshift/
│   └── environments/
│       ├── dev.tfvars
│       └── prod.tfvars
│
├── dbt_project/                        # dbt transformation project
│   ├── dbt_project.yml
│   ├── packages.yml
│   │
│   ├── profiles/
│   │   └── profiles.yml                # Sample Redshift profile
│   │
│   ├── seeds/                          # Reference data
│   │   ├── ref_payers.csv
│   │   ├── ref_service_categories.csv
│   │   └── _seeds.yml
│   │
│   ├── models/
│   │   ├── sources/
│   │   │   └── _sources.yml            # S3 JSON source definitions
│   │   │
│   │   ├── staging/
│   │   │   ├── _stg_models.yml
│   │   │   ├── stg_contracts.sql       # Clean/type-cast extracted data
│   │   │   ├── stg_rate_schedules.sql
│   │   │   └── stg_amendments.sql
│   │   │
│   │   ├── intermediate/
│   │   │   ├── _int_models.yml
│   │   │   ├── int_contracts_enriched.sql
│   │   │   ├── int_rates_normalized.sql
│   │   │   └── int_amendments_parsed.sql
│   │   │
│   │   └── marts/
│   │       ├── core/
│   │       │   ├── _core_models.yml
│   │       │   ├── dim_contract.sql    # SCD Type 2 dimension
│   │       │   ├── dim_provider.sql
│   │       │   ├── dim_payer.sql
│   │       │   ├── dim_service.sql
│   │       │   ├── dim_date.sql
│   │       │   └── fact_contracted_rates.sql
│   │       │
│   │       └── analytics/
│   │           ├── _analytics_models.yml
│   │           ├── contract_summary.sql
│   │           └── rate_comparison.sql
│   │
│   ├── snapshots/
│   │   └── contract_snapshot.sql       # SCD Type 2 history
│   │
│   ├── macros/
│   │   ├── extract_json_field.sql
│   │   ├── parse_date_range.sql
│   │   └── generate_contract_key.sql
│   │
│   └── tests/
│       ├── assert_valid_contract_dates.sql
│       └── assert_positive_rates.sql
│
├── .github/
│   └── workflows/
│       ├── ci.yml                      # PR validation
│       ├── cd.yml                      # Production deployment
│       └── extraction_deploy.yml       # Container deployment
│
└── docs/
    ├── architecture.md
    ├── extraction_service.md
    └── data_dictionary.md
```

---

## 🔧 Components

### 1. PDF Extraction Service (ECS + Docling)

The extraction service runs as a containerized application on AWS ECS Fargate.

**Key Features:**
- Triggered by S3 events when new PDFs arrive
- Uses Docling for AI-powered document understanding
- Extracts structured contract data:
  - Effective dates and termination dates
  - Rate schedules by service category
  - Provider identifiers (NPI, Tax ID)
  - Payer information
  - Amendment clauses and modifications
- Outputs structured JSON to processed S3 bucket

**Extracted Data Schema:**
```json
{
  "contract_id": "CTR-2024-001",
  "payer_name": "Blue Cross Blue Shield",
  "payer_id": "BCBS-001",
  "provider_npi": "1234567890",
  "provider_name": "Regional Medical Center",
  "effective_date": "2024-01-01",
  "termination_date": "2026-12-31",
  "rate_schedules": [
    {
      "service_category": "Inpatient",
      "cpt_code": "99213",
      "rate_type": "per_diem",
      "rate_amount": 1250.00,
      "effective_date": "2024-01-01"
    }
  ],
  "amendments": [
    {
      "amendment_id": "AMD-001",
      "effective_date": "2024-07-01",
      "description": "Rate increase for outpatient services",
      "changes": {...}
    }
  ],
  "extraction_metadata": {
    "extracted_at": "2024-01-15T10:30:00Z",
    "confidence_score": 0.95,
    "source_file": "contract_bcbs_2024.pdf"
  }
}
```

---

### 2. S3 Data Lake Structure

```
s3://contracts-raw-bucket/
└── incoming/
    └── {year}/{month}/{day}/
        └── contract_*.pdf

s3://contracts-processed-bucket/
└── contracts/
    └── payer={payer_id}/
        └── contract_date={YYYY-MM-DD}/
            └── contract_*.json
```

**Partitioning Strategy:**
- Partitioned by `payer_id` and `contract_date` for efficient querying
- Enables Redshift Spectrum to scan only relevant partitions

---

### 3. dbt Transformation Models

#### Staging Layer
Cleans and type-casts the extracted JSON data:

```sql
-- models/staging/stg_contracts.sql
with source as (
    select * from {{ source('s3_json', 'contracts') }}
),

cleaned as (
    select
        contract_id,
        trim(payer_name) as payer_name,
        payer_id,
        provider_npi,
        trim(provider_name) as provider_name,
        cast(effective_date as date) as effective_date,
        cast(termination_date as date) as termination_date,
        cast(extraction_metadata.extracted_at as timestamp) as extracted_at,
        extraction_metadata.confidence_score,
        extraction_metadata.source_file
    from source
    where contract_id is not null
)

select * from cleaned
```

#### Intermediate Layer
Normalizes rate schedules and enriches data:

```sql
-- models/intermediate/int_rates_normalized.sql
with rate_schedules as (
    select
        c.contract_id,
        c.payer_id,
        c.provider_npi,
        rs.value:service_category::varchar as service_category,
        rs.value:cpt_code::varchar as cpt_code,
        rs.value:rate_type::varchar as rate_type,
        rs.value:rate_amount::decimal(12,2) as rate_amount,
        rs.value:effective_date::date as rate_effective_date
    from {{ ref('stg_contracts') }} c,
    lateral flatten(input => c.rate_schedules) rs
)

select * from rate_schedules
```

#### Marts Layer
Builds dimensional model with SCD Type 2:

```sql
-- models/marts/core/dim_contract.sql
{{
    config(
        materialized='table',
        tags=['core', 'dimension', 'scd2']
    )
}}

with snapshot_data as (
    select * from {{ ref('contract_snapshot') }}
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['contract_id', 'dbt_valid_from']) }} as contract_key,
        contract_id,
        payer_id,
        payer_name,
        provider_npi,
        provider_name,
        effective_date,
        termination_date,
        dbt_valid_from as valid_from,
        dbt_valid_to as valid_to,
        case when dbt_valid_to is null then true else false end as is_current
    from snapshot_data
)

select * from final
```

---

### 4. SCD Type 2 Implementation

Tracks contract changes over time using dbt snapshots:

```sql
-- snapshots/contract_snapshot.sql
{% snapshot contract_snapshot %}

{{
    config(
      target_schema='snapshots',
      strategy='check',
      unique_key='contract_id',
      check_cols=['payer_name', 'effective_date', 'termination_date', 'provider_npi'],
    )
}}

select * from {{ ref('stg_contracts') }}

{% endsnapshot %}
```

**Why SCD Type 2 for Contracts?**
- Track when contract terms were modified
- Analyze rates as they existed at any point in time
- Audit trail for compliance and dispute resolution
- Historical trending of rate changes

---

### 5. CI/CD Pipeline (GitHub Actions)

#### Pull Request Validation (`ci.yml`)
```yaml
on:
  pull_request:
    branches: [main]

jobs:
  dbt-ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dbt
        run: pip install dbt-redshift
      - name: dbt compile
        run: dbt compile --target dev
      - name: dbt test
        run: dbt test --target dev
```

#### Production Deployment (`cd.yml`)
```yaml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy dbt models
        run: |
          dbt deps
          dbt run --target prod
          dbt test --target prod
      - name: Trigger pipeline run
        run: aws lambda invoke --function-name trigger-extraction-pipeline
```

---

## 📊 Data Model

### Fact Table: `fact_contracted_rates`

| Column | Type | Description |
|--------|------|-------------|
| rate_key | VARCHAR | Surrogate key |
| contract_key | VARCHAR | FK to dim_contract |
| provider_key | VARCHAR | FK to dim_provider |
| payer_key | VARCHAR | FK to dim_payer |
| service_key | VARCHAR | FK to dim_service |
| effective_date_key | INTEGER | FK to dim_date |
| rate_type | VARCHAR | per_diem, percentage, flat_fee |
| rate_amount | DECIMAL(12,2) | Contracted rate |
| rate_unit | VARCHAR | Unit of measure |

### Dimension: `dim_contract` (SCD Type 2)

| Column | Type | Description |
|--------|------|-------------|
| contract_key | VARCHAR | Surrogate key |
| contract_id | VARCHAR | Natural key |
| payer_id | VARCHAR | Payer identifier |
| payer_name | VARCHAR | Payer name |
| provider_npi | VARCHAR | Provider NPI |
| provider_name | VARCHAR | Provider name |
| effective_date | DATE | Contract start |
| termination_date | DATE | Contract end |
| valid_from | TIMESTAMP | SCD2 row start |
| valid_to | TIMESTAMP | SCD2 row end |
| is_current | BOOLEAN | Current record flag |

---

## 🧪 Data Quality Tests

### Built-in Tests
```yaml
# models/marts/core/_core_models.yml
models:
  - name: fact_contracted_rates
    columns:
      - name: rate_key
        tests:
          - unique
          - not_null
      - name: rate_amount
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
```

### Custom Tests
```sql
-- tests/assert_valid_contract_dates.sql
select
    contract_id,
    effective_date,
    termination_date
from {{ ref('dim_contract') }}
where termination_date < effective_date
```

---

## 🔐 Security Considerations

1. **S3 Bucket Policies**: Restrict access to specific IAM roles
2. **Encryption**: Enable SSE-S3 or SSE-KMS for data at rest
3. **VPC**: Run ECS tasks and Redshift in private subnets
4. **Secrets Manager**: Store credentials securely
5. **IAM Roles**: Least privilege access for each component
6. **PHI Handling**: Contract data may contain sensitive information

---

## 📈 Sample Queries

### Current Contracted Rates by Provider
```sql
SELECT
    p.provider_name,
    py.payer_name,
    s.service_category,
    f.rate_amount,
    c.effective_date,
    c.termination_date
FROM {{ ref('fact_contracted_rates') }} f
JOIN {{ ref('dim_contract') }} c ON f.contract_key = c.contract_key
JOIN {{ ref('dim_provider') }} p ON f.provider_key = p.provider_key
JOIN {{ ref('dim_payer') }} py ON f.payer_key = py.payer_key
JOIN {{ ref('dim_service') }} s ON f.service_key = s.service_key
WHERE c.is_current = true
ORDER BY p.provider_name, py.payer_name
```

### Contract Rate Changes Over Time
```sql
SELECT
    contract_id,
    payer_name,
    valid_from,
    valid_to,
    effective_date,
    termination_date
FROM {{ ref('dim_contract') }}
WHERE contract_id = 'CTR-2024-001'
ORDER BY valid_from
```

---

## 🚀 Deployment

### Local Development
```cmd
docker-compose up -d
dbt run --target dev
```

### Production
```cmd
# Deploy infrastructure
cd infrastructure
terraform apply -var-file=environments/prod.tfvars

# Deploy dbt models
dbt run --target prod
dbt test --target prod
```

---

## 🔧 Troubleshooting

**Extraction service not triggered:**
- Check S3 event notification configuration
- Verify ECS task IAM permissions
- Check CloudWatch logs for errors

**dbt connection fails:**
- Verify Redshift security group allows your IP
- Check environment variables are set
- Ensure VPC endpoints are configured

**JSON parsing errors:**
- Check Docling confidence scores
- Review extraction logs for warnings
- Validate JSON schema compliance

---

## 📚 Resources

- [Docling Documentation](https://github.com/DS4SD/docling)
- [dbt Documentation](https://docs.getdbt.com/)
- [Amazon Redshift Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)
- [AWS ECS Developer Guide](https://docs.aws.amazon.com/ecs/latest/developerguide/)

---

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

---

**Built for demonstrating modern healthcare data engineering with document processing, cloud-native architecture, and analytics best practices.**
