# kiket-ext-github

GitHub Integration Extension for Kiket - Sync pull requests, mirror issues, track CI/CD status, and automate workflows between GitHub and Kiket.

## Features

- **Repository Management**: Register and manage GitHub repositories with Kiket projects
- **Pull Request Sync**: Automatic synchronization of PR status, reviews, and checks
- **Issue Mirroring**: Bidirectional sync between GitHub issues and Kiket issues
- **Webhook Handling**: Process GitHub webhooks for real-time updates
- **CI/CD Status Tracking**: Monitor check runs and check suites
- **Commit Linking**: Auto-link commits to Kiket issues via commit messages
- **Branch/Tag Tracking**: Monitor branches, tags, and releases
- **Analytics Integration**: dbt models for PR metrics and repository insights
- **Sync Jobs**: Trigger full or incremental repository synchronization
- **CSV Export**: Export PR data for analysis

## Installation

### Prerequisites

- Ruby 3.4+
- Bundler
- GitHub App with appropriate permissions
- Access to Kiket custom_data module

### Setup

```bash
cd extensions/github
bundle install
```

### Environment Variables

Create a `.env` file:

```bash
RACK_ENV=development
PORT=9393

# GitHub App Configuration
GITHUB_APP_ID=your_app_id
GITHUB_APP_PRIVATE_KEY=your_private_key_pem
GITHUB_WEBHOOK_SECRET=your_webhook_secret
GITHUB_INSTALLATION_ID=your_installation_id
```

### GitHub App Setup

1. Create a GitHub App in your organization settings
2. Set permissions:
   - Repository contents: Read
   - Issues: Read & write
   - Pull requests: Read & write
   - Checks: Read
   - Metadata: Read
3. Subscribe to webhook events (see manifest.yaml)
4. Generate and save private key
5. Install the app in your repositories

### Running Locally

```bash
bundle exec puma -C puma.rb
```

The extension will be available at `http://localhost:9393`.

## API Endpoints

### Health Check

**GET /health**

Returns extension health status.

### Repository Management

**POST /repositories/register**

Register a GitHub repository with Kiket.

Request:
```json
{
  "owner": "kiket-dev",
  "name": "kiket",
  "installation_id": 12345,
  "kiket_project_id": "proj-123",
  "sync_enabled": true,
  "sync_issues": true,
  "sync_prs": true,
  "auto_link": true,
  "default_branch": "main"
}
```

**GET /repositories**

List registered repositories. Supports filtering by `kiket_project_id`.

**GET /repositories/:owner/:name**

Get details for a specific repository.

**DELETE /repositories/:owner/:name**

Unregister a repository and clean up associated data.

### Pull Request Management

**POST /pull_requests/sync**

Manually sync a pull request.

Request:
```json
{
  "repository": "kiket-dev/kiket",
  "pr_number": 42,
  "title": "Add new feature",
  "state": "open",
  "html_url": "https://github.com/kiket-dev/kiket/pull/42",
  "author": "john",
  "base_branch": "main",
  "head_branch": "feature/new-feature",
  "mergeable": true,
  "merged": false,
  "draft": false,
  "reviews_count": 2,
  "approved_reviews": 1,
  "changes_requested": 0,
  "checks_status": "success",
  "created_at": "2025-11-10T10:00:00Z",
  "updated_at": "2025-11-10T14:00:00Z",
  "kiket_issue_id": "ISSUE-123"
}
```

**GET /pull_requests**

List pull requests. Supports filtering by:
- `repository`: Filter by repository full name
- `state`: Filter by PR state (open, closed)

**GET /pull_requests/:owner/:name/:number**

Get details for a specific pull request.

### Issue Mirroring

**POST /issues/mirror**

Create a bidirectional mapping between GitHub and Kiket issues.

Request:
```json
{
  "repository": "kiket-dev/kiket",
  "github_issue_number": 10,
  "kiket_issue_id": "ISSUE-123",
  "direction": "github_to_kiket",
  "sync_comments": true,
  "sync_status": true,
  "sync_assignees": true,
  "sync_labels": true
}
```

**GET /issues/mappings**

List issue mappings. Supports filtering by:
- `repository`: Repository full name
- `kiket_issue_id`: Kiket issue ID
- `github_issue_number`: GitHub issue number

**DELETE /issues/mappings/:id**

Remove an issue mapping.

### Webhook Handling

**POST /webhooks/github**

Receives GitHub webhooks. Supported events:
- `pull_request`: PR opened, closed, merged, synchronized
- `pull_request_review`: Reviews submitted
- `check_suite`, `check_run`: CI/CD status updates
- `issues`: Issue created, edited, closed
- `issue_comment`: Comments on issues/PRs
- `push`: Commits pushed (for auto-linking)
- `create`, `delete`: Branch/tag events
- `release`: Release published

Requires headers:
- `X-GitHub-Event`: Event type
- `X-GitHub-Delivery`: Delivery ID
- `X-Hub-Signature-256`: Webhook signature (verified in production)

**GET /webhooks/deliveries**

List recent webhook deliveries with processing status.

Query parameters:
- `limit`: Max deliveries to return (default: 50, max: 100)
- `offset`: Pagination offset

### Sync Jobs

**POST /sync/trigger**

Trigger a repository sync job.

Request:
```json
{
  "repository": "kiket-dev/kiket",
  "sync_type": "full"
}
```

Sync types:
- `full`: Complete sync of issues and PRs
- `issues`: Issues only
- `prs`: Pull requests only
- `incremental`: Only recent changes

**GET /sync/jobs**

List sync jobs. Supports filtering by:
- `repository`: Repository full name
- `status`: Job status (queued, running, completed, failed)
- `limit`: Max jobs to return

**GET /sync/jobs/:id**

Get details for a specific sync job.

### Branch and Tag Management

**GET /repositories/:owner/:name/branches**

List branches for a repository.

**GET /repositories/:owner/:name/tags**

List tags for a repository.

### Reports and Metrics

**GET /reports/pr_metrics**

Generate PR metrics report.

Query parameters:
- `repository`: Filter by repository
- `start_date`: Filter PRs created after date (ISO 8601)
- `end_date`: Filter PRs created before date (ISO 8601)

Response:
```json
{
  "total_prs": 150,
  "merged_prs": 120,
  "open_prs": 15,
  "closed_prs": 15,
  "draft_prs": 5,
  "merge_rate": 80.0,
  "avg_merge_time_hours": 48.5
}
```

**GET /reports/issue_metrics**

Generate issue mirroring metrics.

**GET /export/pull_requests/csv**

Export pull requests as CSV.

Query parameters: Same as `/pull_requests`

## Custom Data Schema

The extension uses five custom data tables:

### repositories

Stores registered GitHub repositories.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| owner | string | Repository owner |
| name | string | Repository name |
| full_name | string | Full name (owner/repo) |
| installation_id | bigint | GitHub App installation ID |
| kiket_project_id | string | Associated Kiket project |
| sync_enabled | boolean | Whether sync is enabled |
| sync_issues | boolean | Sync issues |
| sync_prs | boolean | Sync pull requests |
| auto_link | boolean | Auto-link commits to issues |
| default_branch | string | Default branch name |
| registered_at | timestamp | Registration timestamp |
| last_synced_at | timestamp | Last successful sync |

### pull_requests

Stores synchronized pull requests.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| repository_id | bigint | Foreign key to repositories |
| pr_number | integer | GitHub PR number |
| title | text | PR title |
| state | string | PR state (open, closed) |
| author | string | PR author username |
| base_branch | string | Target branch |
| head_branch | string | Source branch |
| merged | boolean | Whether PR was merged |
| draft | boolean | Draft status |
| reviews_count | integer | Total reviews |
| approved_reviews | integer | Approved reviews |
| changes_requested | integer | Reviews requesting changes |
| checks_status | string | CI/CD checks status |
| kiket_issue_id | string | Linked Kiket issue |

### issue_mappings

Stores GitHub-Kiket issue mappings.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| repository_id | bigint | Foreign key to repositories |
| github_issue_number | integer | GitHub issue number |
| kiket_issue_id | string | Kiket issue ID |
| direction | string | Sync direction |
| sync_comments | boolean | Sync comments |
| sync_status | boolean | Sync status changes |
| sync_assignees | boolean | Sync assignees |
| sync_labels | boolean | Sync labels |

### webhook_deliveries

Logs GitHub webhook deliveries.

| Column | Type | Description |
|--------|------|-------------|
| id | string | Delivery ID from GitHub |
| event_type | string | GitHub event type |
| repository_id | bigint | Related repository |
| received_at | timestamp | Receipt timestamp |
| processed | boolean | Processing status |
| error | text | Error message if failed |

### sync_jobs

Tracks repository sync jobs.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| repository_id | bigint | Repository being synced |
| sync_type | string | Type of sync |
| status | string | Job status |
| items_processed | integer | Items processed |
| items_total | integer | Total items |
| started_at | timestamp | Job start time |
| completed_at | timestamp | Job completion time |

## Analytics Models

The extension provides three dbt models for analytics:

### pr_metrics_daily

Incremental model aggregating daily PR metrics.

Metrics:
- PRs opened, merged, closed
- Draft PRs
- Average time to merge
- Average reviews and approvals
- CI/CD check success rate
- Merge rate percentage

### repository_summary

Summary statistics per repository.

Metrics:
- Total PRs (all-time)
- Merged vs open PRs
- Unique contributors
- Mapped issues count
- Average merge time
- Merge rate percentage
- Last sync timestamps

### webhook_reliability

Webhook delivery success rates by event type.

Metrics:
- Total deliveries per day/event type
- Successful vs failed deliveries
- Deliveries with errors
- Success rate percentage

### Dashboard

The `github_overview` dashboard provides:
- Summary metrics (repos, open PRs, mapped issues, avg merge time)
- Daily PR activity trends (opened, merged, closed)
- Top repositories by PR volume and merge rate
- Webhook reliability table
- Active PRs awaiting review

## Command Palette

The extension contributes the following commands to Kiket's command palette (⌘K / Ctrl+K):

- **Sync GitHub Repository**: Trigger full repository sync
- **Link Pull Request**: Link a GitHub PR to current issue
- **Create GitHub Issue**: Create GitHub issue from Kiket issue
- **View Linked PRs**: View PRs linked to current issue
- **Export PR Metrics**: Export PR metrics as CSV

## Webhook Setup

### Configure GitHub Webhook

1. Go to your GitHub repository settings → Webhooks
2. Add webhook with URL: `https://your-kiket-extension.com/webhooks/github`
3. Content type: `application/json`
4. Secret: Use your `GITHUB_WEBHOOK_SECRET`
5. Events: Select individual events or "Send me everything"

### Recommended Events

- Pull requests
- Pull request reviews
- Check suites
- Check runs
- Issues
- Issue comments
- Pushes
- Branch/tag creation/deletion
- Releases

## Usage Examples

### Register a Repository

```bash
curl -X POST http://localhost:9393/repositories/register \
  -H "Content-Type: application/json" \
  -d '{
    "owner": "kiket-dev",
    "name": "kiket",
    "kiket_project_id": "proj-123",
    "installation_id": 12345
  }'
```

### Trigger Repository Sync

```bash
curl -X POST http://localhost:9393/sync/trigger \
  -H "Content-Type: application/json" \
  -d '{
    "repository": "kiket-dev/kiket",
    "sync_type": "full"
  }'
```

### Create Issue Mapping

```bash
curl -X POST http://localhost:9393/issues/mirror \
  -H "Content-Type: application/json" \
  -d '{
    "repository": "kiket-dev/kiket",
    "github_issue_number": 42,
    "kiket_issue_id": "ISSUE-123",
    "direction": "github_to_kiket"
  }'
```

### Get PR Metrics

```bash
curl "http://localhost:9393/reports/pr_metrics?repository=kiket-dev/kiket&start_date=2025-11-01&end_date=2025-11-30"
```

### Export PRs to CSV

```bash
curl "http://localhost:9393/export/pull_requests/csv?repository=kiket-dev/kiket&state=merged" \
  -o github_prs.csv
```

## Development

### Running Tests

```bash
bundle exec rspec
```

Test coverage includes:
- Repository registration and management
- PR synchronization
- Issue mirroring
- Webhook event processing
- Sync job management
- Metrics and reporting
- CSV export
- Error handling

### Linting

```bash
bundle exec rubocop
```

Auto-fix:
```bash
bundle exec rubocop -a
```

### Docker

Build:
```bash
docker build -t kiket-ext-github .
```

Run:
```bash
docker run -p 9393:9393 \
  -e RACK_ENV=production \
  -e GITHUB_APP_ID=your_id \
  -e GITHUB_APP_PRIVATE_KEY="$(cat private-key.pem)" \
  -e GITHUB_WEBHOOK_SECRET=your_secret \
  kiket-ext-github
```

## Troubleshooting

### Webhook Not Processing

- Verify webhook secret matches `GITHUB_WEBHOOK_SECRET`
- Check webhook delivery logs in GitHub settings
- Review `/webhooks/deliveries` endpoint for errors
- Ensure extension is publicly accessible

### PR Not Syncing

- Verify repository is registered via `/repositories`
- Check `sync_prs` is enabled for repository
- Review sync job status via `/sync/jobs`
- Verify GitHub App has PR permissions

### Issue Mapping Fails

- Ensure `sync_issues` is enabled for repository
- Verify GitHub App has issues permissions
- Check issue numbers are correct
- Review error in webhook deliveries

### Authentication Issues

- Verify GitHub App ID and private key
- Ensure installation ID is correct
- Check App permissions include required scopes
- Verify App is installed in repository

## Security

### Webhook Signature Verification

In production, webhook signatures are verified using HMAC-SHA256:

```ruby
def verify_webhook_signature(payload, signature)
  computed = "sha256=" + OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("sha256"),
    ENV["GITHUB_WEBHOOK_SECRET"],
    payload
  )
  Rack::Utils.secure_compare(computed, signature)
end
```

### Secret Management

- Store GitHub App private key in encrypted secrets
- Use environment variables for sensitive configuration
- Rotate webhook secrets periodically
- Limit GitHub App permissions to minimum required

## Permissions

The extension uses role-based access control:

- **user**: Can view repositories, PRs, and mappings for accessible projects
- **manager**: Can register repositories, create mappings, trigger syncs
- **admin**: Full access including deletion and webhook management

## Support

For issues and questions, please refer to the main Kiket documentation or open an issue in the repository.

## License

Part of the Kiket platform.