with repo_stats as (
  select
    r.id as repo_id,
    r.full_name,
    r.kiket_project_id,
    count(distinct pr.id) as total_prs,
    count(distinct case when pr.merged then pr.id end) as merged_prs,
    count(distinct case when pr.state = 'open' then pr.id end) as open_prs,
    count(distinct pr.author) as unique_contributors,
    count(distinct im.id) as mapped_issues,
    max(pr.synced_at) as last_pr_sync,
    max(im.last_synced_at) as last_issue_sync,
    avg(case
      when pr.merged and pr.merged_at is not null and pr.pr_created_at is not null
      then extract(epoch from (pr.merged_at - pr.pr_created_at)) / 3600
    end) as avg_merge_time_hours,
    round(100.0 * count(distinct case when pr.merged then pr.id end) /
      nullif(count(distinct pr.id), 0), 2) as merge_rate_pct
  from {{ source('github_data', 'repositories') }} r
  left join {{ source('github_data', 'pull_requests') }} pr on r.id = pr.repository_id
  left join {{ source('github_data', 'issue_mappings') }} im on r.id = im.repository_id
  group by 1, 2, 3
)

select
  repo_id,
  full_name as repository,
  kiket_project_id,
  total_prs,
  merged_prs,
  open_prs,
  unique_contributors,
  mapped_issues,
  round(cast(avg_merge_time_hours as numeric), 2) as avg_merge_time_hours,
  merge_rate_pct,
  last_pr_sync,
  last_issue_sync
from repo_stats
