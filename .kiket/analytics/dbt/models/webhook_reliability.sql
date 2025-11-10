with webhook_stats as (
  select
    date(received_at) as delivery_date,
    event_type,
    count(*) as total_deliveries,
    count(case when processed then 1 end) as successful_deliveries,
    count(case when not processed then 1 end) as failed_deliveries,
    count(case when error is not null then 1 end) as deliveries_with_error
  from {{ source('github_data', 'webhook_deliveries') }}
  group by 1, 2
)

select
  delivery_date,
  event_type,
  total_deliveries,
  successful_deliveries,
  failed_deliveries,
  deliveries_with_error,
  round(100.0 * successful_deliveries / nullif(total_deliveries, 0), 2) as success_rate_pct
from webhook_stats
order by delivery_date desc, event_type
