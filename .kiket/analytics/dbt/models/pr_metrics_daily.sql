{{
  config(
    materialized='incremental',
    unique_key=['repo_id', 'metric_date']
  )
}}

with pr_daily as (
  select
    repository_id as repo_id,
    date(pr_created_at) as metric_date,
    count(*) as prs_opened,
    count(case when merged then 1 end) as prs_merged,
    count(case when state = 'closed' and not merged then 1 end) as prs_closed_unmerged,
    count(case when draft then 1 end) as prs_draft,
    avg(case
      when merged and merged_at is not null and pr_created_at is not null
      then extract(epoch from (merged_at - pr_created_at)) / 3600
    end) as avg_time_to_merge_hours,
    avg(reviews_count) as avg_reviews,
    avg(approved_reviews) as avg_approved_reviews,
    count(case when checks_status = 'success' then 1 end) as prs_checks_passed,
    count(case when checks_status = 'failure' then 1 end) as prs_checks_failed
  from {{ source('github_data', 'pull_requests') }}
  where pr_created_at is not null
  {% if is_incremental() %}
    and pr_created_at >= (select max(metric_date) - interval '7 days' from {{ this }})
  {% endif %}
  group by 1, 2
)

select
  repo_id,
  metric_date,
  prs_opened,
  prs_merged,
  prs_closed_unmerged,
  prs_draft,
  round(cast(avg_time_to_merge_hours as numeric), 2) as avg_time_to_merge_hours,
  round(cast(avg_reviews as numeric), 2) as avg_reviews,
  round(cast(avg_approved_reviews as numeric), 2) as avg_approved_reviews,
  prs_checks_passed,
  prs_checks_failed,
  round(100.0 * prs_merged / nullif(prs_opened, 0), 2) as merge_rate_pct,
  round(100.0 * prs_checks_passed / nullif(prs_checks_passed + prs_checks_failed, 0), 2) as check_success_rate_pct
from pr_daily
