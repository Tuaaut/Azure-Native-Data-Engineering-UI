# Azure-Native Data Engineering UI

Azure-native QR printing analytics: **Function → ADLS Gen2 → ADF → Synapse Serverless SQL → Power BI**.

**Current runtime:** Azure cloud. Windows is used for administration, SQL, source files and Power BI Desktop. No local Docker, Python service or Task Scheduler is required.

## 1. Business objective

Turn machine print events into daily machine/product KPIs: production volume, successful and rejected events, QR readability and print-position quality. The Power BI report is a one-page Print Event Operations Overview.

![Business flow](docs/images/business-flow.svg)
![Technical flow](docs/images/technical-flow.svg)

Diagrams show the service topology. The operating schedule and publication rules below supersede older timing or storage examples in screenshots.

## 2. Current schedule and cloud resources

All times are Bangkok time.

| # | Component | Resource / operation | Schedule |
|---:|---|---|---|
| 1 | Generator | `func-qr-de-native-gen-740561` writes the previous business day's JSON | Monday/Thursday 12:00 |
| 2 | Data lake | `stqrdenativeui740561`, container `datalake` | Persistent storage |
| 3 | ADF | `adf-qr-de-native-ui-740561`, pipeline `pl_ingest_machine_api_json` | Monday/Thursday 12:30 |
| 4 | Synapse | `syn-qr-de-native-ui-740561`, database `qr_native_lakehouse` | After successful Copy |
| 5 | Power BI | Workspace `syn-qr-de-native-ui-740561`, model `sm_gold_print_event_kpis_daily` | Monday/Thursday 13:00 |

ADF's legacy trigger name is still `tr_daily_machine_api_schedule_1200_bkk`; its actual recurrence is weekly Monday/Thursday at 12:30. The trigger passes a four-day last-modified window, allowing overlapping source deliveries. The Copy activity preserves actual source-folder names.

ADF concurrency is one. Copy has a 10-minute timeout; transformation has a 15-minute timeout. The BI schedule is intentionally later, but it is still time-based, not an ADF success dependency: a delayed/failed pipeline can leave Power BI showing the last valid snapshot.

## 3. Data and publication contract

```text
datalake/
  landing/machine_api/<source-folder>/machine_api_response.json
  raw/machine_api/<source-folder>/machine_api_response.json
  bronze/, silver/, gold/                 # historical published data, retained
  medallion_v2/
    bronze/event_date=YYYY-MM-DD/run_<attempt>/
    silver/event_date=YYYY-MM-DD/run_<attempt>/
    gold/event_date=YYYY-MM-DD/run_<attempt>/
    commits/<attempt>/                    # validated publication manifests
```

The procedure reads `event_ts` inside the JSON rather than assuming the folder name equals the ADF run date. Normal runs expect the previous Bangkok business date. An explicit `@event_date` supports recovery of older deliveries; late historical corrections require such a targeted run.

1. Confirm Raw has events for the expected date. Missing/stale source raises SQL error 50003.
2. Write an immutable Bronze candidate preserving source lineage and repeated deliveries.
3. Validate required fields, ranges and the reject rule; reject invalid candidates.
4. Deduplicate by `event_id` into Silver, using latest source folder/load.
5. Aggregate one complete business-date snapshot into Gold and reconcile its event count with Silver.
6. Write a commit manifest only after validation. The stable Gold view exposes the latest committed snapshot for each date, retaining legacy data for dates not yet replaced.

Repeating a date replaces its visible snapshot rather than adding its totals. Empty/failed candidates and old files remain invisible to the v2 reporting view. Unique attempt names bypass the empty external tables left by the old procedure without deleting historical data.

The current implementation scans available Raw JSON to find the requested event date (about 48 MB during the September review). It incrementally replaces one date, but does not claim partition-pruned Raw reads. For larger histories, introduce an indexed delivery manifest/event-date Raw layout before scaling. ADF serialization is required; avoid direct concurrent procedure runs.

### Quality rule

An event is rejected if `print_status != 'PRINTED'`, `qr_read_success != 1`, or `ABS(position_error_mm) > 0.45`. The source Boolean `is_reject` must agree. QR grade is a quality indicator, not another rejection threshold. Current validation requires non-null QR grade/position values.

## 4. SQL and reproducibility

| # | Files | Purpose |
|---:|---|---|
| 1 | [00 setup](sql/00_setup_serverless_objects.sql) | Database, `ds_datalake`, `ff_parquet`, aligned with published Synapse objects |
| 2 | [01 inspect](sql/01_inspect_raw_json.sql), [02 parse](sql/02_parse_print_events.sql) | Serverless CSV/OPENJSON syntax against actual Raw paths |
| 3 | [03 Bronze](sql/03_create_bronze_parquet.sql), [04 Silver](sql/04_create_silver_parquet.sql), [05 Gold](sql/05_create_gold_parquet.sql) | Historical one-off showcase mappings, with fixed output locations |
| 4 | [06 historical view](sql/06_create_gold_reporting_view.sql), [07 partition template](sql/07_incremental_partition_template.sql), [08 historical recursive view](sql/08_create_scalable_gold_view.sql) | Learning/history; do not deploy over the current reporting view |
| 5 | [09 current procedure](sql/09_create_incremental_medallion_procedure.sql) | Validated replacement of one business date |
| 6 | [10 current view](sql/10_create_committed_gold_view.sql) | Latest committed date snapshots plus unreplaced historical dates |
| 7 | [11 validation](sql/11_validate_current_gold.sql) | Freshness, counts, duplicate grains and KPI reconciliation |

The procedure generator [build_sql.py](scripts/build_sql.py) uses the historical 03–05 column mappings; changing those mappings requires regenerating and reviewing 09–10. Do not rerun fixed-location CETAS showcase scripts against occupied locations.

Current ADF exports: [pipeline](infra/adf-pipeline.json), [trigger](infra/adf-trigger.json), [source dataset](infra/ds_source_machine_api_json.json), [sink dataset](infra/ds_sink_raw_machine_api_json.json). [Generator bindings](infra/generator-bindings.json) document the timer; they are not a backup of the Python function source. Linked-service credentials, RBAC and function implementation are not recreated by these files.

## 5. Windows operations

Sign in with Azure CLI using an account authorized for this project. The PowerShell helper obtains a short-lived Entra SQL token in memory; it never writes the token to disk.

```powershell
az login
.\scripts\Invoke-ProjectSql.ps1 -File .\sql\11_validate_current_gold.sql
```

The helper uses the existing Windows .NET SQL client. `sqlcmd` and the Azure CLI `datafactory` extension are optional; the reviewed administration used `az rest`.

For controlled recovery, pass an ISO-8601 UTC scheduled time and the actual business date. This writes new snapshots and incurs normal serverless query/storage charges:

```powershell
.\scripts\Invoke-ProjectSql.ps1 -Query "EXEC dbo.usp_process_machine_api_incremental @window_end_utc='2026-09-03T05:30:00Z', @event_date='2026-09-02';"
```

Prefer the existing ADF pipeline for ordinary runs so its concurrency and alerting apply. After recovery, run SQL validation, refresh the Power BI semantic model, and verify report totals. Do not generate synthetic missing calendar days: this source intentionally delivers only twice a week.

Deployment order for this existing environment: preserve definitions → deploy 09 → validate/publish recovered dates → deploy 10 → run 11. A new environment also requires real source data, cloud identities/linked services and historical baseline or an adapted bootstrap view; this is not a one-command infrastructure deployment.

## 6. Power BI and Desktop

Report: `rpt_print_event_kpis_daily`; model: `sm_gold_print_event_kpis_daily`; source: `dbo.vw_gold_print_event_kpis_daily`; storage mode: Import.

![Power BI report layout](docs/images/power-bi-report.jpg)

The screenshot is historical. Current totals follow validated Gold publications.

For Desktop editing, open [rpt_print_event_kpis_daily_local.pbip](powerbi/rpt_print_event_kpis_daily_local.pbip), which includes both the Report and SemanticModel definitions. Keep the adjacent `.Report` and `.SemanticModel` folders together. This export contains definitions, not cached imported data: authenticate to Synapse with the project's organizational account and refresh in Desktop to populate it. The alternative [live-connected report](powerbi/rpt_print_event_kpis_daily.pbip) uses the already-refreshed online semantic model and requires Power BI sign-in/access.

See [export script](powerbi/export-report-definition.ps1); use `-IncludeSemanticModel` to export a complete local project. Existing exports are preserved under distinct names. PBIX REST export was rejected by the service for this PremiumFiles model; PBIP is the project-definition alternative used here.

Measure definitions are in [DAX](semantic/dax-measures.dax) and [TMDL](semantic/semantic-model.tmdl). Count/rate measures aggregate totals. QR grade and absolute position-error measures now weight each Gold group mean by its event count. The old measure names containing `Average Daily` are retained for visual compatibility; they represent an event-weighted average over the selected dates, not an equal-weight average of days. Legacy Silver had no null values for either metric, and v2 rejects nulls. Results inherit the four-decimal precision of the stored group means.

## 7. Monitoring and cost

- ADF failure alert `ar-qr-adf-pipeline-failed` remains enabled and notification-only. Missing expected data, failed quality validation or count reconciliation now fails the SQL activity, so these no longer silently pass this alert.
- Power BI retains failure email on its Monday/Thursday 13:00 schedule.
- The Function's Application Insights smart detector is not a scheduled-delivery freshness check. Missing source is detected at the following ADF run. A stopped ADF trigger or an alert-delivery outage is not covered by that check.
- The historical USD 10/month Azure budget is an alert target, not a hard spending cap; current spend/budget state was not revalidated during remediation.
- Serverless SQL only; no Spark/Dedicated SQL pool. Old snapshots and failed candidates are retained for recovery; storage cleanup is a separate maintenance decision.

## 8. Progress and source control

| # | Work | Status |
|---:|---|---|
| 1 | Windows cloud access | Verified Azure, Storage, SQL and Power BI APIs |
| 2 | Wrong-folder / empty-success defect | Corrected; recovered August 31 and September 2 |
| 3 | Gold freshness | Latest business date September 2; 95,040 events after recovery |
| 4 | Rerun safety | Validated date replacement; duplicate reporting grains = 0 |
| 5 | Failure detection | Missing-source negative test raises error 50003 without changing published totals |
| 6 | Scheduling | ADF Mon/Thu 12:30; BI Mon/Thu 13:00 |
| 7 | Local Git | Recovered existing GitHub history; private backups/handover excluded; no push performed |

The detailed dated evidence, remaining operational limitations and next checkpoint stay in the existing local `CURRENT_STATUS.md`. The next unattended run must still be observed; manual verification is not proof of future unattended operation.

Never commit access tokens, credentials, local settings, private backups, or cached report data. Git history was restored from the existing [GitHub repository](https://github.com/Tuaaut/Azure-Native-Data-Engineering-UI) without replacing the copied working files.

## 9. References

- [Serverless JSON queries](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-json-files)
- [CETAS](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-cetas)
- [Power BI project files](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-overview)
