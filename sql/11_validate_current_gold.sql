USE qr_native_lakehouse;
GO
-- Read-only post-run checks. Latest date should match the actual source delivery,
-- not today's date: the generator runs Monday/Thursday for the previous day.
SELECT MAX(event_date) AS latest_event_date,
       SUM(total_events) AS total_events,
       SUM(successful_events) AS successful_events,
       SUM(rejected_events) AS rejected_events
FROM dbo.vw_gold_print_event_kpis_daily;

SELECT event_date, SUM(total_events) AS total_events
FROM dbo.vw_gold_print_event_kpis_daily
GROUP BY event_date ORDER BY event_date;

SELECT COUNT_BIG(*) AS duplicate_grains
FROM (
    SELECT event_date,machine_id,product_id,product_name
    FROM dbo.vw_gold_print_event_kpis_daily
    GROUP BY event_date,machine_id,product_id,product_name
    HAVING COUNT_BIG(*) > 1
) AS duplicates;

SELECT COUNT_BIG(*) AS invalid_gold_groups
FROM dbo.vw_gold_print_event_kpis_daily
WHERE total_events <> successful_events + rejected_events
   OR total_events <> printed_events + failed_events
   OR total_events <= 0;
GO
