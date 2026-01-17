# frozen_string_literal: true

require "kiket_sdk"
require "json"
require "octokit"
require "jwt"
require "openssl"
require "logger"

# GitHub Integration Extension
# Manages GitHub repositories, PRs, issues mirroring, and webhooks
class GitHubExtension
  REQUIRED_READ_SCOPES = %w[repositories:read].freeze
  REQUIRED_WRITE_SCOPES = %w[repositories:write].freeze
  REQUIRED_WEBHOOK_SCOPES = %w[webhooks:receive].freeze
  REQUIRED_SYNC_SCOPES = %w[sync:execute].freeze
  REQUIRED_ISSUES_SCOPES = %w[issues:write].freeze

  def initialize
    @sdk = KiketSDK.new
    @logger = Logger.new($stdout)

    # In-memory storage (production would use custom_data tables)
    @repositories = {}
    @pull_requests = {}
    @issue_mappings = {}
    @webhook_deliveries = []
    @sync_jobs = []

    setup_handlers
  end

  def app
    @sdk
  end

  private

  def setup_handlers
    # Repository Management
    @sdk.register("github.repositories.register", version: "v1", required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_register_repository(payload, context)
    end

    @sdk.register("github.repositories.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_repositories(payload, context)
    end

    @sdk.register("github.repositories.get", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_get_repository(payload, context)
    end

    @sdk.register("github.repositories.delete", version: "v1", required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_delete_repository(payload, context)
    end

    # Pull Request Management
    @sdk.register("github.pull_requests.sync", version: "v1", required_scopes: REQUIRED_SYNC_SCOPES) do |payload, context|
      handle_sync_pull_request(payload, context)
    end

    @sdk.register("github.pull_requests.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_pull_requests(payload, context)
    end

    @sdk.register("github.pull_requests.get", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_get_pull_request(payload, context)
    end

    # Issue Mirroring
    @sdk.register("github.issues.mirror", version: "v1", required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_mirror_issue(payload, context)
    end

    @sdk.register("github.issues.mappings.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_issue_mappings(payload, context)
    end

    @sdk.register("github.issues.mappings.delete", version: "v1", required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_delete_issue_mapping(payload, context)
    end

    # Webhook Handling
    @sdk.register("github.webhooks.receive", version: "v1", required_scopes: REQUIRED_WEBHOOK_SCOPES) do |payload, context|
      handle_webhook(payload, context)
    end

    @sdk.register("github.webhooks.deliveries", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_webhook_deliveries(payload, context)
    end

    # Sync Jobs
    @sdk.register("github.sync.trigger", version: "v1", required_scopes: REQUIRED_SYNC_SCOPES) do |payload, context|
      handle_trigger_sync(payload, context)
    end

    @sdk.register("github.sync.jobs.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_sync_jobs(payload, context)
    end

    @sdk.register("github.sync.jobs.get", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_get_sync_job(payload, context)
    end

    # Branch/Tag Management
    @sdk.register("github.branches.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_branches(payload, context)
    end

    @sdk.register("github.tags.list", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_tags(payload, context)
    end

    # Reports
    @sdk.register("github.reports.pr_metrics", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_pr_metrics(payload, context)
    end

    @sdk.register("github.reports.issue_metrics", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_issue_metrics(payload, context)
    end

    @sdk.register("github.export.pull_requests", version: "v1", required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_export_pull_requests(payload, context)
    end
  end

  # Repository Handlers

  def handle_register_repository(payload, context)
    repo_owner = payload["owner"]
    repo_name = payload["name"]
    installation_id = payload["installation_id"]
    kiket_project_id = payload["kiket_project_id"]

    raise ArgumentError, "Missing required fields: owner, name, kiket_project_id" unless repo_owner && repo_name && kiket_project_id

    repo_key = "#{repo_owner}/#{repo_name}"

    @repositories[repo_key] = {
      id: @repositories.length + 1,
      owner: repo_owner,
      name: repo_name,
      full_name: repo_key,
      installation_id: installation_id,
      kiket_project_id: kiket_project_id,
      sync_enabled: payload.fetch("sync_enabled", true),
      sync_issues: payload.fetch("sync_issues", true),
      sync_prs: payload.fetch("sync_prs", true),
      auto_link: payload.fetch("auto_link", true),
      default_branch: payload["default_branch"] || "main",
      registered_at: Time.now.utc.iso8601,
      last_synced_at: nil,
      org_id: context[:auth][:org_id]
    }

    context[:endpoints].log_event("github.repository.registered", {
      repository: repo_key,
      org_id: context[:auth][:org_id]
    })

    { status: "registered", repository: @repositories[repo_key] }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_repositories(payload, context)
    project_id = payload["kiket_project_id"]
    org_id = context[:auth][:org_id]

    repos = @repositories.select { |_, r| r[:org_id] == org_id }
    repos = repos.select { |_, r| r[:kiket_project_id] == project_id } if project_id

    { repositories: repos.values }
  end

  def handle_get_repository(payload, context)
    repo_key = "#{payload['owner']}/#{payload['name']}"
    repo = @repositories[repo_key]

    return { error: "Repository not found" } unless repo

    { repository: repo }
  end

  def handle_delete_repository(payload, context)
    repo_key = "#{payload['owner']}/#{payload['name']}"
    repo = @repositories.delete(repo_key)

    return { error: "Repository not found" } unless repo

    # Clean up associated data
    @pull_requests.delete_if { |_, pr| pr[:repository] == repo_key }
    @issue_mappings.delete_if { |_, m| m[:repository] == repo_key }

    context[:endpoints].log_event("github.repository.deleted", {
      repository: repo_key,
      org_id: context[:auth][:org_id]
    })

    { status: "deleted" }
  end

  # Pull Request Handlers

  def handle_sync_pull_request(payload, context)
    repo_key = payload["repository"]
    pr_number = payload["pr_number"]

    raise ArgumentError, "Missing repository or pr_number" unless repo_key && pr_number

    repo = @repositories[repo_key]
    return { error: "Repository not registered" } unless repo

    pr_key = "#{repo_key}##{pr_number}"

    @pull_requests[pr_key] = {
      id: @pull_requests.length + 1,
      repository: repo_key,
      pr_number: pr_number,
      title: payload["title"],
      state: payload["state"],
      html_url: payload["html_url"],
      author: payload["author"],
      base_branch: payload["base_branch"],
      head_branch: payload["head_branch"],
      mergeable: payload["mergeable"],
      merged: payload["merged"],
      draft: payload.fetch("draft", false),
      reviews_count: payload.fetch("reviews_count", 0),
      approved_reviews: payload.fetch("approved_reviews", 0),
      changes_requested: payload.fetch("changes_requested", 0),
      checks_status: payload["checks_status"],
      created_at: payload["created_at"],
      updated_at: payload["updated_at"],
      merged_at: payload["merged_at"],
      synced_at: Time.now.utc.iso8601,
      kiket_issue_id: payload["kiket_issue_id"]
    }

    { status: "synced", pull_request: @pull_requests[pr_key] }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_pull_requests(payload, context)
    repo_key = payload["repository"]
    state = payload["state"]

    prs = @pull_requests.values
    prs = prs.select { |pr| pr[:repository] == repo_key } if repo_key
    prs = prs.select { |pr| pr[:state] == state } if state

    { pull_requests: prs }
  end

  def handle_get_pull_request(payload, context)
    repo_key = "#{payload['owner']}/#{payload['name']}"
    pr_key = "#{repo_key}##{payload['number']}"
    pr = @pull_requests[pr_key]

    return { error: "Pull request not found" } unless pr

    { pull_request: pr }
  end

  # Issue Mirroring Handlers

  def handle_mirror_issue(payload, context)
    direction = payload["direction"]
    repo_key = payload["repository"]

    raise ArgumentError, "Missing required fields: direction, repository" unless direction && repo_key

    repo = @repositories[repo_key]
    return { error: "Repository not registered" } unless repo
    return { error: "Issue sync not enabled" } unless repo[:sync_issues]

    mapping_id = @issue_mappings.length + 1

    mapping = {
      id: mapping_id,
      repository: repo_key,
      github_issue_number: payload["github_issue_number"],
      kiket_issue_id: payload["kiket_issue_id"],
      direction: direction,
      sync_comments: payload.fetch("sync_comments", true),
      sync_status: payload.fetch("sync_status", true),
      sync_assignees: payload.fetch("sync_assignees", true),
      sync_labels: payload.fetch("sync_labels", true),
      created_at: Time.now.utc.iso8601,
      last_synced_at: Time.now.utc.iso8601
    }

    @issue_mappings[mapping_id] = mapping

    context[:endpoints].log_event("github.issue.mirrored", {
      repository: repo_key,
      direction: direction,
      org_id: context[:auth][:org_id]
    })

    { status: "mirrored", mapping: mapping }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_issue_mappings(payload, context)
    repo_key = payload["repository"]
    kiket_issue_id = payload["kiket_issue_id"]
    github_issue = payload["github_issue_number"]

    mappings = @issue_mappings.values
    mappings = mappings.select { |m| m[:repository] == repo_key } if repo_key
    mappings = mappings.select { |m| m[:kiket_issue_id] == kiket_issue_id } if kiket_issue_id
    mappings = mappings.select { |m| m[:github_issue_number].to_s == github_issue.to_s } if github_issue

    { mappings: mappings }
  end

  def handle_delete_issue_mapping(payload, context)
    mapping_id = payload["id"].to_i
    mapping = @issue_mappings.delete(mapping_id)

    return { error: "Mapping not found" } unless mapping

    { status: "deleted" }
  end

  # Webhook Handlers

  def handle_webhook(payload, context)
    raw_payload = payload["raw_payload"]
    signature = payload["signature"]
    event_type = payload["event_type"]
    delivery_id = payload["delivery_id"]

    # Verify webhook signature
    webhook_secret = context[:secret].call("GITHUB_WEBHOOK_SECRET")
    if webhook_secret && signature
      verify_webhook_signature(raw_payload, signature, webhook_secret)
    end

    data = raw_payload.is_a?(String) ? JSON.parse(raw_payload) : raw_payload

    delivery = {
      id: delivery_id,
      event_type: event_type,
      received_at: Time.now.utc.iso8601,
      processed: false,
      error: nil
    }

    begin
      case event_type
      when "pull_request"
        handle_pull_request_event(data)
      when "pull_request_review"
        handle_pull_request_review_event(data)
      when "check_suite", "check_run"
        handle_check_event(data, event_type)
      when "issues"
        handle_issue_event(data)
      when "issue_comment"
        handle_issue_comment_event(data)
      when "push"
        handle_push_event(data)
      when "create", "delete"
        handle_ref_event(data, event_type)
      when "release"
        handle_release_event(data)
      else
        delivery[:error] = "Unsupported event type: #{event_type}"
      end

      delivery[:processed] = true
    rescue StandardError => e
      delivery[:error] = e.message
      delivery[:processed] = false
    end

    @webhook_deliveries << delivery

    context[:endpoints].log_event("github.webhook.received", {
      event_type: event_type,
      delivery_id: delivery_id,
      org_id: context[:auth][:org_id]
    })

    { status: "received", delivery_id: delivery_id }
  end

  def handle_list_webhook_deliveries(payload, context)
    limit = [payload.fetch("limit", 50).to_i, 100].min
    offset = payload.fetch("offset", 0).to_i

    deliveries = @webhook_deliveries.reverse[offset, limit] || []

    {
      deliveries: deliveries,
      total: @webhook_deliveries.length,
      limit: limit,
      offset: offset
    }
  end

  # Sync Job Handlers

  def handle_trigger_sync(payload, context)
    repo_key = payload["repository"]
    sync_type = payload["sync_type"]

    raise ArgumentError, "Missing required fields: repository, sync_type" unless repo_key && sync_type

    repo = @repositories[repo_key]
    return { error: "Repository not registered" } unless repo
    return { error: "Sync not enabled" } unless repo[:sync_enabled]

    job_id = @sync_jobs.length + 1

    job = {
      id: job_id,
      repository: repo_key,
      sync_type: sync_type,
      status: "queued",
      items_processed: 0,
      items_total: nil,
      started_at: nil,
      completed_at: nil,
      error: nil,
      created_at: Time.now.utc.iso8601
    }

    @sync_jobs << job

    # Simulate job processing start
    job[:status] = "running"
    job[:started_at] = Time.now.utc.iso8601
    job[:items_total] = 10

    context[:endpoints].log_event("github.sync.triggered", {
      repository: repo_key,
      sync_type: sync_type,
      job_id: job_id,
      org_id: context[:auth][:org_id]
    })

    { status: "triggered", job: job }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_sync_jobs(payload, context)
    repo_key = payload["repository"]
    status_filter = payload["status"]
    limit = [payload.fetch("limit", 20).to_i, 100].min

    jobs = @sync_jobs
    jobs = jobs.select { |j| j[:repository] == repo_key } if repo_key
    jobs = jobs.select { |j| j[:status] == status_filter } if status_filter
    jobs = jobs.reverse.take(limit)

    { jobs: jobs }
  end

  def handle_get_sync_job(payload, context)
    job_id = payload["id"].to_i
    job = @sync_jobs.find { |j| j[:id] == job_id }

    return { error: "Job not found" } unless job

    { job: job }
  end

  # Branch/Tag Handlers

  def handle_list_branches(payload, context)
    repo_key = "#{payload['owner']}/#{payload['name']}"
    repo = @repositories[repo_key]

    return { error: "Repository not found" } unless repo

    # In production, would fetch from GitHub API
    branches = [
      { name: repo[:default_branch], protected: true, sha: "abc123" },
      { name: "develop", protected: false, sha: "def456" },
      { name: "feature/new-feature", protected: false, sha: "ghi789" }
    ]

    { branches: branches }
  end

  def handle_list_tags(payload, context)
    repo_key = "#{payload['owner']}/#{payload['name']}"
    repo = @repositories[repo_key]

    return { error: "Repository not found" } unless repo

    # In production, would fetch from GitHub API
    tags = [
      { name: "v1.0.0", sha: "abc123", created_at: "2025-11-01T10:00:00Z" },
      { name: "v1.1.0", sha: "def456", created_at: "2025-11-05T14:30:00Z" }
    ]

    { tags: tags }
  end

  # Report Handlers

  def handle_pr_metrics(payload, context)
    repo_key = payload["repository"]
    start_date = payload["start_date"]
    end_date = payload["end_date"]

    prs = @pull_requests.values
    prs = prs.select { |pr| pr[:repository] == repo_key } if repo_key
    prs = prs.select { |pr| pr[:created_at] && pr[:created_at] >= start_date } if start_date
    prs = prs.select { |pr| pr[:created_at] && pr[:created_at] <= end_date } if end_date

    total_prs = prs.length
    merged_prs = prs.count { |pr| pr[:merged] }
    open_prs = prs.count { |pr| pr[:state] == "open" }
    closed_prs = prs.count { |pr| pr[:state] == "closed" && !pr[:merged] }
    draft_prs = prs.count { |pr| pr[:draft] }

    merge_times = prs
      .select { |pr| pr[:merged] && pr[:created_at] && pr[:merged_at] }
      .map { |pr| Time.parse(pr[:merged_at]) - Time.parse(pr[:created_at]) }

    avg_merge_time = merge_times.empty? ? 0 : (merge_times.sum / merge_times.length)

    {
      total_prs: total_prs,
      merged_prs: merged_prs,
      open_prs: open_prs,
      closed_prs: closed_prs,
      draft_prs: draft_prs,
      merge_rate: total_prs.zero? ? 0 : (merged_prs.to_f / total_prs * 100).round(2),
      avg_merge_time_hours: (avg_merge_time / 3600).round(2)
    }
  end

  def handle_issue_metrics(payload, context)
    repo_key = payload["repository"]

    mappings = @issue_mappings.values
    mappings = mappings.select { |m| m[:repository] == repo_key } if repo_key

    {
      total_mappings: mappings.length,
      github_to_kiket: mappings.count { |m| m[:direction] == "github_to_kiket" },
      kiket_to_github: mappings.count { |m| m[:direction] == "kiket_to_github" },
      sync_enabled: mappings.count { |m| m[:sync_status] }
    }
  end

  def handle_export_pull_requests(payload, context)
    repo_key = payload["repository"]

    prs = @pull_requests.values
    prs = prs.select { |pr| pr[:repository] == repo_key } if repo_key

    csv = "ID,Repository,PR Number,Title,State,Author,Base Branch,Head Branch,Merged,Draft,Reviews,Approved,Changes Requested,Checks,Created At,Updated At,Merged At,Kiket Issue\n"

    prs.each do |pr|
      csv += [
        pr[:id],
        pr[:repository],
        pr[:pr_number],
        pr[:title],
        pr[:state],
        pr[:author],
        pr[:base_branch],
        pr[:head_branch],
        pr[:merged],
        pr[:draft],
        pr[:reviews_count],
        pr[:approved_reviews],
        pr[:changes_requested],
        pr[:checks_status],
        pr[:created_at],
        pr[:updated_at],
        pr[:merged_at],
        pr[:kiket_issue_id]
      ].map { |v| "\"#{v}\"" }.join(",") + "\n"
    end

    { format: "csv", content: csv, filename: "github_pull_requests.csv" }
  end

  # Private webhook event handlers

  def handle_pull_request_event(data)
    action = data["action"]
    pr = data["pull_request"]
    repo = data["repository"]

    repo_key = repo["full_name"]
    return unless @repositories[repo_key]

    case action
    when "opened", "reopened", "synchronize", "edited", "closed", "merged"
      sync_pull_request_from_webhook(repo_key, pr)
    end
  end

  def handle_pull_request_review_event(data)
    review = data["review"]
    pr = data["pull_request"]
    repo = data["repository"]

    repo_key = repo["full_name"]
    pr_key = "#{repo_key}##{pr['number']}"

    return unless @repositories[repo_key]
    return unless @pull_requests[pr_key]

    case review["state"]
    when "approved"
      @pull_requests[pr_key][:approved_reviews] += 1
    when "changes_requested"
      @pull_requests[pr_key][:changes_requested] += 1
    end

    @pull_requests[pr_key][:reviews_count] += 1
  end

  def handle_check_event(data, event_type)
    repo = data["repository"]
    repo_key = repo["full_name"]

    return unless @repositories[repo_key]

    prs = if event_type == "check_suite"
      data.dig("check_suite", "pull_requests") || []
    else
      data.dig("check_run", "pull_requests") || []
    end

    prs.each do |pr|
      pr_key = "#{repo_key}##{pr['number']}"
      next unless @pull_requests[pr_key]

      status = if event_type == "check_suite"
        data.dig("check_suite", "conclusion") || data.dig("check_suite", "status")
      else
        data.dig("check_run", "conclusion") || data.dig("check_run", "status")
      end

      @pull_requests[pr_key][:checks_status] = status
    end
  end

  def handle_issue_event(data)
    issue = data["issue"]
    repo = data["repository"]

    repo_key = repo["full_name"]

    return unless @repositories[repo_key]
    return unless @repositories[repo_key][:sync_issues]

    # Would trigger sync to Kiket here
  end

  def handle_issue_comment_event(data)
    issue = data["issue"]
    repo = data["repository"]

    repo_key = repo["full_name"]

    return unless @repositories[repo_key]

    # Would sync comment to Kiket here
  end

  def handle_push_event(data)
    repo = data["repository"]
    repo_key = repo["full_name"]

    return unless @repositories[repo_key]
    return unless @repositories[repo_key][:auto_link]

    # Would extract issue references from commit messages here
  end

  def handle_ref_event(data, event_type)
    repo = data["repository"]
    repo_key = repo["full_name"]

    return unless @repositories[repo_key]

    # Would track branch/tag creation/deletion here
  end

  def handle_release_event(data)
    repo = data["repository"]
    repo_key = repo["full_name"]

    return unless @repositories[repo_key]

    # Would track release events here
  end

  def sync_pull_request_from_webhook(repo_key, pr_data)
    pr_key = "#{repo_key}##{pr_data['number']}"

    @pull_requests[pr_key] = {
      id: @pull_requests[pr_key]&.[](:id) || @pull_requests.length + 1,
      repository: repo_key,
      pr_number: pr_data["number"],
      title: pr_data["title"],
      state: pr_data["state"],
      html_url: pr_data["html_url"],
      author: pr_data.dig("user", "login"),
      base_branch: pr_data.dig("base", "ref"),
      head_branch: pr_data.dig("head", "ref"),
      mergeable: pr_data["mergeable"],
      merged: pr_data["merged"],
      draft: pr_data.fetch("draft", false),
      reviews_count: @pull_requests[pr_key]&.[](:reviews_count) || 0,
      approved_reviews: @pull_requests[pr_key]&.[](:approved_reviews) || 0,
      changes_requested: @pull_requests[pr_key]&.[](:changes_requested) || 0,
      checks_status: nil,
      created_at: pr_data["created_at"],
      updated_at: pr_data["updated_at"],
      merged_at: pr_data["merged_at"],
      synced_at: Time.now.utc.iso8601,
      kiket_issue_id: @pull_requests[pr_key]&.[](:kiket_issue_id)
    }
  end

  def verify_webhook_signature(payload, signature, secret)
    payload_string = payload.is_a?(String) ? payload : payload.to_json
    computed_signature = "sha256=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      secret,
      payload_string
    )

    unless Rack::Utils.secure_compare(computed_signature, signature)
      raise ArgumentError, "Invalid webhook signature"
    end
  end
end

# Run the extension
if __FILE__ == $PROGRAM_NAME
  extension = GitHubExtension.new

  Rack::Handler::Puma.run(
    extension.app,
    Host: ENV.fetch("HOST", "0.0.0.0"),
    Port: ENV.fetch("PORT", 8080).to_i,
    Threads: "0:16"
  )
end
