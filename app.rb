# frozen_string_literal: true

require "sinatra/base"
require "json"
require "octokit"
require "jwt"
require "openssl"

class GitHubExtension < Sinatra::Base
  configure do
    set :show_exceptions, false
    set :raise_errors, false
  end

  # Store for GitHub data (in production, this would use custom_data tables)
  configure do
    set :repositories, {}
    set :pull_requests, {}
    set :issue_mappings, {}
    set :webhook_deliveries, []
    set :sync_jobs, []
  end

  # Health check
  get "/health" do
    content_type :json
    { status: "ok", extension: "github", version: "1.0.0" }.to_json
  end

  # Repository Management

  post "/repositories/register" do
    data = JSON.parse(request.body.read)

    repo_owner = data["owner"]
    repo_name = data["name"]
    installation_id = data["installation_id"]
    kiket_project_id = data["kiket_project_id"]

    halt 400, { error: "Missing required fields" }.to_json unless repo_owner && repo_name && kiket_project_id

    repo_key = "#{repo_owner}/#{repo_name}"

    settings.repositories[repo_key] = {
      id: settings.repositories.length + 1,
      owner: repo_owner,
      name: repo_name,
      full_name: repo_key,
      installation_id: installation_id,
      kiket_project_id: kiket_project_id,
      sync_enabled: data.fetch("sync_enabled", true),
      sync_issues: data.fetch("sync_issues", true),
      sync_prs: data.fetch("sync_prs", true),
      auto_link: data.fetch("auto_link", true),
      default_branch: data["default_branch"] || "main",
      registered_at: Time.now.utc.iso8601,
      last_synced_at: nil
    }

    content_type :json
    status 201
    { status: "registered", repository: settings.repositories[repo_key] }.to_json
  end

  get "/repositories" do
    project_id = params["kiket_project_id"]

    repos = if project_id
      settings.repositories.select { |_, r| r[:kiket_project_id] == project_id }
    else
      settings.repositories
    end

    content_type :json
    { repositories: repos.values }.to_json
  end

  get "/repositories/:owner/:name" do
    repo_key = "#{params[:owner]}/#{params[:name]}"
    repo = settings.repositories[repo_key]

    halt 404, { error: "Repository not found" }.to_json unless repo

    content_type :json
    { repository: repo }.to_json
  end

  delete "/repositories/:owner/:name" do
    repo_key = "#{params[:owner]}/#{params[:name]}"
    repo = settings.repositories.delete(repo_key)

    halt 404, { error: "Repository not found" }.to_json unless repo

    # Clean up associated data
    settings.pull_requests.delete_if { |_, pr| pr[:repository] == repo_key }
    settings.issue_mappings.delete_if { |_, m| m[:repository] == repo_key }

    content_type :json
    { status: "deleted" }.to_json
  end

  # Pull Request Management

  post "/pull_requests/sync" do
    data = JSON.parse(request.body.read)

    repo_key = data["repository"]
    pr_number = data["pr_number"]

    halt 400, { error: "Missing repository or pr_number" }.to_json unless repo_key && pr_number

    repo = settings.repositories[repo_key]
    halt 404, { error: "Repository not registered" }.to_json unless repo

    pr_key = "#{repo_key}##{pr_number}"

    settings.pull_requests[pr_key] = {
      id: settings.pull_requests.length + 1,
      repository: repo_key,
      pr_number: pr_number,
      title: data["title"],
      state: data["state"],
      html_url: data["html_url"],
      author: data["author"],
      base_branch: data["base_branch"],
      head_branch: data["head_branch"],
      mergeable: data["mergeable"],
      merged: data["merged"],
      draft: data.fetch("draft", false),
      reviews_count: data.fetch("reviews_count", 0),
      approved_reviews: data.fetch("approved_reviews", 0),
      changes_requested: data.fetch("changes_requested", 0),
      checks_status: data["checks_status"],
      created_at: data["created_at"],
      updated_at: data["updated_at"],
      merged_at: data["merged_at"],
      synced_at: Time.now.utc.iso8601,
      kiket_issue_id: data["kiket_issue_id"]
    }

    content_type :json
    { status: "synced", pull_request: settings.pull_requests[pr_key] }.to_json
  end

  get "/pull_requests" do
    repo_key = params["repository"]
    state = params["state"]

    prs = settings.pull_requests.values
    prs = prs.select { |pr| pr[:repository] == repo_key } if repo_key
    prs = prs.select { |pr| pr[:state] == state } if state

    content_type :json
    { pull_requests: prs }.to_json
  end

  get "/pull_requests/:owner/:name/:number" do
    repo_key = "#{params[:owner]}/#{params[:name]}"
    pr_key = "#{repo_key}##{params[:number]}"
    pr = settings.pull_requests[pr_key]

    halt 404, { error: "Pull request not found" }.to_json unless pr

    content_type :json
    { pull_request: pr }.to_json
  end

  # Issue Mirroring

  post "/issues/mirror" do
    data = JSON.parse(request.body.read)

    direction = data["direction"] # 'github_to_kiket' or 'kiket_to_github'
    repo_key = data["repository"]

    halt 400, { error: "Missing required fields" }.to_json unless direction && repo_key

    repo = settings.repositories[repo_key]
    halt 404, { error: "Repository not registered" }.to_json unless repo
    halt 400, { error: "Issue sync not enabled" }.to_json unless repo[:sync_issues]

    mapping_id = settings.issue_mappings.length + 1

    mapping = {
      id: mapping_id,
      repository: repo_key,
      github_issue_number: data["github_issue_number"],
      kiket_issue_id: data["kiket_issue_id"],
      direction: direction,
      sync_comments: data.fetch("sync_comments", true),
      sync_status: data.fetch("sync_status", true),
      sync_assignees: data.fetch("sync_assignees", true),
      sync_labels: data.fetch("sync_labels", true),
      created_at: Time.now.utc.iso8601,
      last_synced_at: Time.now.utc.iso8601
    }

    settings.issue_mappings[mapping_id] = mapping

    content_type :json
    status 201
    { status: "mirrored", mapping: mapping }.to_json
  end

  get "/issues/mappings" do
    repo_key = params["repository"]
    kiket_issue_id = params["kiket_issue_id"]
    github_issue = params["github_issue_number"]

    mappings = settings.issue_mappings.values
    mappings = mappings.select { |m| m[:repository] == repo_key } if repo_key
    mappings = mappings.select { |m| m[:kiket_issue_id] == kiket_issue_id } if kiket_issue_id
    mappings = mappings.select { |m| m[:github_issue_number].to_s == github_issue } if github_issue

    content_type :json
    { mappings: mappings }.to_json
  end

  delete "/issues/mappings/:id" do
    mapping_id = params[:id].to_i
    mapping = settings.issue_mappings.delete(mapping_id)

    halt 404, { error: "Mapping not found" }.to_json unless mapping

    content_type :json
    { status: "deleted" }.to_json
  end

  # Webhook Handling

  post "/webhooks/github" do
    payload = request.body.read
    signature = request.env["HTTP_X_HUB_SIGNATURE_256"]
    event_type = request.env["HTTP_X_GITHUB_EVENT"]
    delivery_id = request.env["HTTP_X_GITHUB_DELIVERY"]

    # In production, verify webhook signature
    # verify_webhook_signature(payload, signature)

    data = JSON.parse(payload)

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

    settings.webhook_deliveries << delivery

    content_type :json
    { status: "received", delivery_id: delivery_id }.to_json
  end

  get "/webhooks/deliveries" do
    limit = [ params.fetch("limit", "50").to_i, 100 ].min
    offset = params.fetch("offset", "0").to_i

    deliveries = settings.webhook_deliveries.reverse[offset, limit] || []

    content_type :json
    {
      deliveries: deliveries,
      total: settings.webhook_deliveries.length,
      limit: limit,
      offset: offset
    }.to_json
  end

  # Sync Jobs

  post "/sync/trigger" do
    data = JSON.parse(request.body.read)

    repo_key = data["repository"]
    sync_type = data["sync_type"] # 'full', 'issues', 'prs', 'incremental'

    halt 400, { error: "Missing required fields" }.to_json unless repo_key && sync_type

    repo = settings.repositories[repo_key]
    halt 404, { error: "Repository not registered" }.to_json unless repo
    halt 400, { error: "Sync not enabled" }.to_json unless repo[:sync_enabled]

    job_id = settings.sync_jobs.length + 1

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

    settings.sync_jobs << job

    # Simulate job processing
    job[:status] = "running"
    job[:started_at] = Time.now.utc.iso8601
    job[:items_total] = 10

    content_type :json
    status 202
    { status: "triggered", job: job }.to_json
  end

  get "/sync/jobs" do
    repo_key = params["repository"]
    status_filter = params["status"]
    limit = [ params.fetch("limit", "20").to_i, 100 ].min

    jobs = settings.sync_jobs
    jobs = jobs.select { |j| j[:repository] == repo_key } if repo_key
    jobs = jobs.select { |j| j[:status] == status_filter } if status_filter
    jobs = jobs.reverse.take(limit)

    content_type :json
    { jobs: jobs }.to_json
  end

  get "/sync/jobs/:id" do
    job_id = params[:id].to_i
    job = settings.sync_jobs.find { |j| j[:id] == job_id }

    halt 404, { error: "Job not found" }.to_json unless job

    content_type :json
    { job: job }.to_json
  end

  # Branch and Tag Management

  get "/repositories/:owner/:name/branches" do
    repo_key = "#{params[:owner]}/#{params[:name]}"
    repo = settings.repositories[repo_key]

    halt 404, { error: "Repository not found" }.to_json unless repo

    # Mock branch data
    branches = [
      { name: repo[:default_branch], protected: true, sha: "abc123" },
      { name: "develop", protected: false, sha: "def456" },
      { name: "feature/new-feature", protected: false, sha: "ghi789" }
    ]

    content_type :json
    { branches: branches }.to_json
  end

  get "/repositories/:owner/:name/tags" do
    repo_key = "#{params[:owner]}/#{params[:name]}"
    repo = settings.repositories[repo_key]

    halt 404, { error: "Repository not found" }.to_json unless repo

    # Mock tag data
    tags = [
      { name: "v1.0.0", sha: "abc123", created_at: "2025-11-01T10:00:00Z" },
      { name: "v1.1.0", sha: "def456", created_at: "2025-11-05T14:30:00Z" }
    ]

    content_type :json
    { tags: tags }.to_json
  end

  # Statistics and Reports

  get "/reports/pr_metrics" do
    repo_key = params["repository"]
    start_date = params["start_date"]
    end_date = params["end_date"]

    prs = settings.pull_requests.values
    prs = prs.select { |pr| pr[:repository] == repo_key } if repo_key

    if start_date
      prs = prs.select { |pr| pr[:created_at] && pr[:created_at] >= start_date }
    end

    if end_date
      prs = prs.select { |pr| pr[:created_at] && pr[:created_at] <= end_date }
    end

    total_prs = prs.length
    merged_prs = prs.count { |pr| pr[:merged] }
    open_prs = prs.count { |pr| pr[:state] == "open" }
    closed_prs = prs.count { |pr| pr[:state] == "closed" && !pr[:merged] }
    draft_prs = prs.count { |pr| pr[:draft] }

    merge_times = prs
      .select { |pr| pr[:merged] && pr[:created_at] && pr[:merged_at] }
      .map { |pr| Time.parse(pr[:merged_at]) - Time.parse(pr[:created_at]) }

    avg_merge_time = merge_times.empty? ? 0 : (merge_times.sum / merge_times.length)

    content_type :json
    {
      total_prs: total_prs,
      merged_prs: merged_prs,
      open_prs: open_prs,
      closed_prs: closed_prs,
      draft_prs: draft_prs,
      merge_rate: total_prs.zero? ? 0 : (merged_prs.to_f / total_prs * 100).round(2),
      avg_merge_time_hours: (avg_merge_time / 3600).round(2)
    }.to_json
  end

  get "/reports/issue_metrics" do
    repo_key = params["repository"]

    mappings = settings.issue_mappings.values
    mappings = mappings.select { |m| m[:repository] == repo_key } if repo_key

    content_type :json
    {
      total_mappings: mappings.length,
      github_to_kiket: mappings.count { |m| m[:direction] == "github_to_kiket" },
      kiket_to_github: mappings.count { |m| m[:direction] == "kiket_to_github" },
      sync_enabled: mappings.count { |m| m[:sync_status] }
    }.to_json
  end

  # Export

  get "/export/pull_requests/csv" do
    repo_key = params["repository"]

    prs = settings.pull_requests.values
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

    content_type "text/csv"
    attachment "github_pull_requests.csv"
    csv
  end

  # Error handling
  error 400 do
    content_type :json
    { error: "Bad request" }.to_json
  end

  error 404 do
    content_type :json
    { error: "Not found" }.to_json
  end

  error 500 do
    content_type :json
    { error: "Internal server error" }.to_json
  end

  private

  def handle_pull_request_event(data)
    action = data["action"]
    pr = data["pull_request"]
    repo = data["repository"]

    repo_key = repo["full_name"]
    pr_number = pr["number"]

    return unless settings.repositories[repo_key]

    case action
    when "opened", "reopened", "synchronize", "edited", "closed", "merged"
      sync_pull_request(repo_key, pr)
    end
  end

  def handle_pull_request_review_event(data)
    review = data["review"]
    pr = data["pull_request"]
    repo = data["repository"]

    repo_key = repo["full_name"]
    pr_key = "#{repo_key}##{pr["number"]}"

    return unless settings.repositories[repo_key]
    return unless settings.pull_requests[pr_key]

    # Update review counts
    case review["state"]
    when "approved"
      settings.pull_requests[pr_key][:approved_reviews] += 1
    when "changes_requested"
      settings.pull_requests[pr_key][:changes_requested] += 1
    end

    settings.pull_requests[pr_key][:reviews_count] += 1
  end

  def handle_check_event(data, event_type)
    repo = data["repository"]
    repo_key = repo["full_name"]

    return unless settings.repositories[repo_key]

    # Extract PR information from check suite/run
    prs = if event_type == "check_suite"
      data.dig("check_suite", "pull_requests") || []
    else
      data.dig("check_run", "pull_requests") || []
    end

    prs.each do |pr|
      pr_key = "#{repo_key}##{pr["number"]}"
      next unless settings.pull_requests[pr_key]

      # Update checks status
      status = if event_type == "check_suite"
        data.dig("check_suite", "conclusion") || data.dig("check_suite", "status")
      else
        data.dig("check_run", "conclusion") || data.dig("check_run", "status")
      end

      settings.pull_requests[pr_key][:checks_status] = status
    end
  end

  def handle_issue_event(data)
    action = data["action"]
    issue = data["issue"]
    repo = data["repository"]

    repo_key = repo["full_name"]

    return unless settings.repositories[repo_key]
    return unless settings.repositories[repo_key][:sync_issues]

    # Check if issue is already mapped
    mapping = settings.issue_mappings.values.find do |m|
      m[:repository] == repo_key && m[:github_issue_number] == issue["number"]
    end

    # Would trigger sync to Kiket here
  end

  def handle_issue_comment_event(data)
    issue = data["issue"]
    comment = data["comment"]
    repo = data["repository"]

    repo_key = repo["full_name"]

    return unless settings.repositories[repo_key]

    # Check if issue is mapped
    mapping = settings.issue_mappings.values.find do |m|
      m[:repository] == repo_key &&
      m[:github_issue_number] == issue["number"] &&
      m[:sync_comments]
    end

    # Would sync comment to Kiket here
  end

  def handle_push_event(data)
    repo = data["repository"]
    ref = data["ref"]
    commits = data["commits"]

    repo_key = repo["full_name"]

    return unless settings.repositories[repo_key]
    nil unless settings.repositories[repo_key][:auto_link]

    # Extract issue references from commit messages
    # Would link commits to Kiket issues here
  end

  def handle_ref_event(data, event_type)
    repo = data["repository"]
    ref = data["ref"]
    ref_type = data["ref_type"]

    repo_key = repo["full_name"]

    nil unless settings.repositories[repo_key]

    # Track branch/tag creation/deletion
  end

  def handle_release_event(data)
    action = data["action"]
    release = data["release"]
    repo = data["repository"]

    repo_key = repo["full_name"]

    nil unless settings.repositories[repo_key]

    # Track release events
  end

  def sync_pull_request(repo_key, pr_data)
    pr_key = "#{repo_key}##{pr_data["number"]}"

    settings.pull_requests[pr_key] = {
      id: settings.pull_requests[pr_key]&.[](:id) || settings.pull_requests.length + 1,
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
      reviews_count: settings.pull_requests[pr_key]&.[](:reviews_count) || 0,
      approved_reviews: settings.pull_requests[pr_key]&.[](:approved_reviews) || 0,
      changes_requested: settings.pull_requests[pr_key]&.[](:changes_requested) || 0,
      checks_status: nil,
      created_at: pr_data["created_at"],
      updated_at: pr_data["updated_at"],
      merged_at: pr_data["merged_at"],
      synced_at: Time.now.utc.iso8601,
      kiket_issue_id: settings.pull_requests[pr_key]&.[](:kiket_issue_id)
    }
  end

  def verify_webhook_signature(payload, signature)
    return unless signature

    secret = ENV["GITHUB_WEBHOOK_SECRET"]
    return unless secret

    computed_signature = "sha256=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      secret,
      payload
    )

    halt 401, { error: "Invalid signature" }.to_json unless Rack::Utils.secure_compare(computed_signature, signature)
  end
end
