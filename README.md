# Azure-Native Data Engineering UI

> Source of truth for the Azure-native batch data engineering and Power BI demonstration project.

**Status:** MVP complete  
**Last verified:** 2026-08-01
**Implementation style:** Azure portal and service UIs  
**Cost strategy:** Serverless and manual execution; no Spark or Dedicated SQL pool

## 1. Project objective

Build a cost-conscious Azure-native data engineering workflow that:

1. Ingests machine API JSON files.
2. Preserves the source payload in an ADLS Gen2 Raw layer.
3. Parses the `print_events` JSON array with Synapse Serverless SQL.
4. Produces Bronze, Silver, and Gold data as Parquet.
5. Exposes a Gold reporting view.
6. Serves reusable DAX measures through a Power BI semantic model.
7. Presents a one-page operations report for print-event KPIs.

## 2. Architecture

### Business flow

![Business flow from print events to operational action](docs/images/business-flow.svg)

### Technical architecture

![Azure-native technical architecture](docs/images/technical-flow.svg)

Verified Power BI lineage:

```text
Synapse -> sm_gold_print_event_kpis_daily -> rpt_print_event_kpis_daily
```

## 3. Azure resources

| Component | Resource / object | Purpose |
|---|---|---|
| Resource group | `rg-qr-de-native-demo-UI` | Project boundary |
| Azure budget | USD 10/month | Cost guardrail |
| ADLS Gen2 | `stqrdenativeui740561` | Data lake storage |
| Container | `datalake` | Raw and medallion data |
| Azure Data Factory | `adf-qr-de-native-ui-740561` | Batch ingestion |
| ADF pipeline | `pl_ingest_machine_api_json` | Incrementally copies machine API JSON to Raw using a last-modified UTC window |
| ADF trigger | `tr_daily_machine_api_incremental` | Stopped 24-hour tumbling window for future automated ingestion |
| Synapse workspace | `syn-qr-de-native-ui-740561` | Serverless SQL transformation and serving |
| Power BI linked service | `ls_powerbi_qr_native_demo` | Synapse-to-Power BI workspace link |
| Power BI workspace | `syn-qr-de-native-ui-740561` | BI artifacts |

The Azure subscription ID is intentionally excluded so this document can be made public later.

## 4. Data lake layout

```text
datalake/
├── raw/
│   └── machine_api/
│       └── <ingestion_timestamp>/
│           └── machine_api_response.json
├── bronze/
│   └── print_events/
│       └── run_20260731_01/
│           └── *.parquet
├── silver/
│   └── print_events/
│       └── run_20260731_01/
│           └── *.parquet
└── gold/
    └── print_event_kpis_daily/
        └── run_20260731_01/
            └── *.parquet
```

Raw ingestion completed for three `machine_api_response.json` files copied from `qrdbx06162114` into timestamped folders under:

```text
datalake/raw/machine_api/<timestamp>/
```

One inspected Raw folder was:

```text
datalake/raw/machine_api/20260621T000000Z/
```

The three Raw files contain two unique daily batches. The two deliveries for
`batch-20260619` are byte-identical test-ingestion duplicates. Bronze preserves
all 8,640 rows, while Silver deduplicates them to 5,760 unique `event_id` rows.

## 5. Medallion responsibilities

### Raw

- Immutable source JSON.
- Preserves the original machine API response.
- Stored by ingestion timestamp for traceability.

### Bronze

- Expands the `print_events` array into tabular event rows.
- Retains source-level event attributes with minimal transformation.
- Preserves duplicate source deliveries and ingestion lineage.
- Stored as Parquet to reduce repeated JSON scanning.

### Silver

- Applies data types and standardized field names.
- Deduplicates events by `event_id` using the latest source folder/load.
- Produces analytics-ready print-event records.
- Supports clean downstream aggregation.

### Gold

- Aggregates print-event KPIs by day, machine, and product.
- Stores reporting-ready Parquet.
- Feeds the Synapse reporting view and Power BI semantic model.

## 6. Synapse Serverless SQL

Only the built-in **Serverless SQL** endpoint is used.

Not used:

- Apache Spark pools
- Dedicated SQL pools

### Verified SQL artifacts

| Script / object | Purpose | Status |
|---|---|---|
| `sql_00_inspect_raw_json` | Inspect Raw JSON with Serverless SQL | Complete |
| `OPENJSON` parsing query | Expand `print_events`; parsing test returned 100 rows | Complete |
| Bronze Parquet transformation | Write parsed events to Bronze | Complete |
| Silver Parquet transformation | Clean and type event records | Complete |
| Gold Parquet transformation | Aggregate daily KPI records | Complete |
| `sql_06_create_gold_reporting_view` | Create the Power BI-facing Gold view | Complete |
| `sql_07_incremental_partition_template` | Prepare one new date-partitioned Bronze, Silver, and Gold run | Complete; saved template, not executed |
| `sql_08_create_scalable_gold_view` | Read current and future Gold Parquet partitions recursively | Complete and executed |
| `vw_gold_print_event_kpis_daily` | Reporting view over Gold Parquet | Complete |

### Showcase SQL exports

The repository includes a documented, sequential Serverless SQL implementation:

1. [`00_setup_serverless_objects.sql`](sql/00_setup_serverless_objects.sql)
2. [`01_inspect_raw_json.sql`](sql/01_inspect_raw_json.sql)
3. [`02_parse_print_events.sql`](sql/02_parse_print_events.sql)
4. [`03_create_bronze_parquet.sql`](sql/03_create_bronze_parquet.sql)
5. [`04_create_silver_parquet.sql`](sql/04_create_silver_parquet.sql)
6. [`05_create_gold_parquet.sql`](sql/05_create_gold_parquet.sql)
7. [`06_create_gold_reporting_view.sql`](sql/06_create_gold_reporting_view.sql)
8. [`07_incremental_partition_template.sql`](sql/07_incremental_partition_template.sql)
9. [`08_create_scalable_gold_view.sql`](sql/08_create_scalable_gold_view.sql)

Scripts 03-08 match the SQL artifacts published in Synapse Studio. Scripts
00-02 remain documented showcase versions for setup, inspection, and preview.
Validate a new API version with `01_inspect_raw_json.sql` before processing it.

### Incremental readiness

The published ADF pipeline now requires two string parameters:

```text
window_start_utc
window_end_utc
```

They drive the Copy activity's **Filter by last modified** settings, preventing
the normal incremental run from rescanning every source file. The incremental
Synapse template writes each new event date to new immutable paths such as:

```text
bronze/print_events/event_date=YYYY-MM-DD/run_<run_id>/
silver/print_events/event_date=YYYY-MM-DD/run_<run_id>/
gold/print_event_kpis_daily/event_date=YYYY-MM-DD/run_<run_id>/
```

The template must be updated with the actual event date, Raw ingestion-folder
pattern, and unique run ID before execution. CETAS output locations cannot be
reused. The stable Gold view recursively reads Parquet below
`gold/print_event_kpis_daily/`, so the semantic model keeps the same source view.

The published trigger configuration is:

```text
Name:             tr_daily_machine_api_incremental
Type:             Tumbling window
Frequency:        Every 24 hours
Start:            2026-08-02 00:00:00 UTC
Max concurrency:  1
Retry:            1 after 60 seconds
Runtime state:    Stopped
```

The trigger maps `windowStartTime` and `windowEndTime` to the two pipeline
parameters. Keep it stopped until recurring source delivery is ready.

## 7. Gold reporting schema

Verified fields exposed by `vw_gold_print_event_kpis_daily`:

| Field | Meaning |
|---|---|
| `event_date` | KPI date |
| `machine_id` | Machine identifier |
| `product_id` | Product identifier |
| `product_name` | Product name |
| `total_events` | Total print events |
| `printed_events` | Printed-event count from Gold |
| `successful_events` | Successful events |
| `rejected_events` | Rejected events |
| `failed_events` | Failed events |
| `qr_read_failures` | QR-read failure count |
| `success_rate_pct` | Gold success-rate percentage |
| `reject_rate_pct` | Gold reject-rate percentage |
| `avg_qr_grade_score` | Average QR grade score |
| `avg_abs_position_error_mm` | Average absolute position error in millimetres |
| `first_event_ts` | First event timestamp in the group |
| `last_event_ts` | Last event timestamp in the group |
| `gold_loaded_utc` | Gold load timestamp |

## 8. Power BI implementation

### Workspace

```text
syn-qr-de-native-ui-740561
```

Workspace description:

```text
Power BI reporting workspace for the Azure-native QR data engineering demo using Synapse Serverless SQL Gold KPIs.
```

### Semantic model

```text
sm_gold_print_event_kpis_daily
```

Source table:

```text
vw_gold_print_event_kpis_daily
```

Storage mode:

```text
Import
```

Display folder for custom measures:

```text
DAX Measures
```

### DAX measures

Reusable semantic-model artifacts:

- [`dax-measures.dax`](semantic/dax-measures.dax) — executable validation query
  containing all seven measure definitions.
- [`semantic-model.tmdl`](semantic/semantic-model.tmdl) — showcase TMDL
  representation including formats and the `DAX Measures` display folder.

```DAX
Total Events =
SUM ( vw_gold_print_event_kpis_daily[total_events] )

Successful Events =
SUM ( vw_gold_print_event_kpis_daily[successful_events] )

Rejected Events =
SUM ( vw_gold_print_event_kpis_daily[rejected_events] )

Success Rate % =
DIVIDE ( [Successful Events], [Total Events], 0 )

Reject Rate % =
DIVIDE ( [Rejected Events], [Total Events], 0 )

Average Daily QR Grade Score =
AVERAGE ( vw_gold_print_event_kpis_daily[avg_qr_grade_score] )

Average Daily Position Error (mm) =
AVERAGE ( vw_gold_print_event_kpis_daily[avg_abs_position_error_mm] )
```

Formatting:

- Count measures: whole number with thousands separator.
- Rate measures: percentage with two decimal places.
- QR grade score: decimal.
- Position error: decimal in millimetres.

### Report

```text
rpt_print_event_kpis_daily
```

Report design: one-page **Print Event Operations Overview**

Layout:

1. Report title.
2. Operational KPI cards.
3. Quality KPI cards.
4. Clustered column chart: Successful vs Rejected Events by Date.
5. Daily detail table at the bottom.

Visual standards:

- Font: Segoe UI
- Dark report theme
- Successful events: `#34A853`
- Rejected events: `#E15759`
- Exact data labels with no automatic `K` abbreviation
- Categorical date axis

## 9. Verified report output

Final Reading view and lineage were visually checked on 2026-07-31.

### KPI cards

| KPI | Verified value |
|---|---:|
| Total Events | 5,760 |
| Successful Events | 5,225 |
| Rejected Events | 535 |
| Success Rate | 90.71% |
| Reject Rate | 9.29% |
| Average Daily QR Grade Score | 0.91 |
| Average Daily Position Error | 0.194 mm |

### Daily detail

| Date | Machine | Product | Total | Successful | Rejected | Success rate | Reject rate |
|---|---|---|---:|---:|---:|---:|---:|
| 2026-06-19 | M01 | Cola Can 330ml | 2,880 | 2,612 | 268 | 90.69% | 9.31% |
| 2026-06-20 | M01 | Cola Can 330ml | 2,880 | 2,613 | 267 | 90.73% | 9.27% |
| **Total** |  |  | **5,760** | **5,225** | **535** | **90.71%** | **9.29%** |

## 10. Refresh and operating procedure

Current Power BI status:

- Semantic model refreshed: 2026-07-31 02:22 AM as displayed in Power BI.
- Scheduled refresh: not configured.
- Next refresh: `N/A`.

Recommended test workflow:

1. Run `pl_ingest_machine_api_json` only when new source data is required, and
   supply `window_start_utc` and `window_end_utc` in ISO-8601 UTC format.
2. Confirm the new JSON file exists under the expected Raw timestamp folder.
3. Copy `07_incremental_partition_template.sql`, replace its marked date,
   Raw-folder pattern, and run suffix, then execute it once.
4. Write new date- and run-partitioned Bronze, Silver, and Gold Parquet outputs.
5. Validate the Gold reporting view.
6. Refresh `sm_gold_print_event_kpis_daily` manually.
7. Validate KPI totals and dates in `rpt_print_event_kpis_daily`.
8. Save the report before leaving Editing view.

Avoid refreshing Power BI when the Gold data has not changed.

## 11. Cost controls

- Azure budget: USD 10/month.
- Synapse Serverless SQL only.
- No Spark pool.
- No Dedicated SQL pool.
- Parquet used after Raw to reduce scanned data.
- Manual pipeline execution during testing.
- Daily tumbling-window trigger published but intentionally stopped.
- Manual semantic-model refresh during testing.
- No Power BI app creation for the MVP.
- No scheduled refresh while the source remains static.

Power BI displayed a trial with six days remaining on 2026-07-31. Recheck licensing and workspace capacity before relying on sharing or scheduled refresh after the trial.

## 12. Security and GitHub readiness

Do not commit:

- Subscription IDs
- Access keys
- SAS tokens
- Connection strings
- Credentials
- Local browser/session data

Current repository structure:

```text
Azure-Native-Data-Engineering-UI/
├── README.md
├── sql/
│   ├── 00_setup_serverless_objects.sql
│   ├── 01_inspect_raw_json.sql
│   ├── 02_parse_print_events.sql
│   ├── 03_create_bronze_parquet.sql
│   ├── 04_create_silver_parquet.sql
│   ├── 05_create_gold_parquet.sql
│   ├── 06_create_gold_reporting_view.sql
│   ├── 07_incremental_partition_template.sql
│   └── 08_create_scalable_gold_view.sql
├── semantic/
│   ├── dax-measures.dax
│   └── semantic-model.tmdl
├── docs/
│   └── images/
│       ├── business-flow.svg
│       └── technical-flow.svg
```

## 13. Current limitations

- Demo dataset currently covers two dates.
- Current report data contains one machine and one product.
- Incremental ADF ingestion is parameterized, but Raw-to-Gold execution and
  Power BI refresh are not yet orchestrated end to end.
- No scheduled Power BI refresh.
- Validate Raw JSON schema before processing another API version.
- The ADF pipeline JSON has not been exported because the project was built and
  validated through the Azure UI.
- Infrastructure is not yet represented as Bicep, ARM, or Terraform.

## 14. Recommended next steps

1. Optionally export the ADF pipeline JSON for full reproducibility.
2. Capture clean screenshots of:
   - ADF pipeline
   - ADLS Raw/Bronze/Silver/Gold folders
   - Synapse Gold query result
   - Power BI report Reading view
   - Power BI lineage view
3. Optionally add a `.gitignore` if local tooling begins creating artifacts.
4. Add automated orchestration only if it provides portfolio value without
   exceeding the cost guardrails.

## 15. Completion checklist

- [x] Resource group and budget
- [x] ADLS Gen2 and medallion folders
- [x] ADF ingestion pipeline
- [x] Three Raw JSON ingestions
- [x] Raw JSON inspection
- [x] `print_events` parsing with `OPENJSON`
- [x] Bronze Parquet
- [x] Silver Parquet
- [x] Gold Parquet
- [x] Gold reporting view
- [x] Synapse-to-Power BI linked service
- [x] Power BI semantic model
- [x] Seven DAX measures grouped in `DAX Measures`
- [x] One-page Power BI operations report
- [x] Reading view validation
- [x] Lineage validation
- [x] Add showcase Synapse SQL scripts
- [x] Add DAX and TMDL semantic-model scripts
- [x] Add Business and Technical SVG architecture diagrams
- [x] Parameterize ADF ingestion by source last-modified UTC window
- [x] Add a stopped daily tumbling-window trigger with parameter mapping
- [x] Add incremental date-partition template
- [x] Create stable recursive Gold reporting view
- [ ] Optionally export the ADF pipeline JSON
- [x] Review for secrets, initialize Git, and publish the repository

## 16. Technical references

- [Query data storage with Synapse Serverless SQL](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-data-storage)
- [CREATE EXTERNAL TABLE AS SELECT (CETAS) in Synapse SQL](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-cetas)
- [Store query results from a serverless SQL pool](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/create-external-table-as-select)
- [Tabular Model Definition Language (TMDL)](https://learn.microsoft.com/en-us/analysis-services/tmdl/tmdl-overview)
