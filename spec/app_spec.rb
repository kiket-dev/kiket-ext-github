# frozen_string_literal: true

require "spec_helper"

RSpec.describe GitHubExtension do
  describe "GET /health" do
    it "returns health status" do
      get "/health"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
      expect(body["extension"]).to eq("github")
    end
  end

  describe "POST /repositories/register" do
    it "registers a new repository" do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123",
        installation_id: 12345
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("registered")
      expect(body["repository"]["full_name"]).to eq("kiket-dev/kiket")
    end

    it "requires owner and name" do
      post "/repositories/register", JSON.generate({
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(400)
    end
  end

  describe "GET /repositories" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "lists all repositories" do
      get "/repositories"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["repositories"]).to be_an(Array)
      expect(body["repositories"].length).to eq(1)
    end

    it "filters by project_id" do
      get "/repositories?kiket_project_id=proj-123"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["repositories"].length).to eq(1)
    end
  end

  describe "DELETE /repositories/:owner/:name" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "deletes a repository" do
      delete "/repositories/kiket-dev/kiket"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("deleted")
    end
  end

  describe "POST /pull_requests/sync" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "syncs a pull request" do
      post "/pull_requests/sync", JSON.generate({
        repository: "kiket-dev/kiket",
        pr_number: 42,
        title: "Add new feature",
        state: "open",
        author: "john",
        base_branch: "main",
        head_branch: "feature/new",
        merged: false,
        draft: false
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("synced")
      expect(body["pull_request"]["pr_number"]).to eq(42)
    end
  end

  describe "GET /pull_requests" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"

      post "/pull_requests/sync", JSON.generate({
        repository: "kiket-dev/kiket",
        pr_number: 42,
        title: "PR 1",
        state: "open",
        author: "john",
        base_branch: "main",
        head_branch: "feature/new"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "lists pull requests" do
      get "/pull_requests"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["pull_requests"]).to be_an(Array)
      expect(body["pull_requests"].length).to eq(1)
    end

    it "filters by state" do
      get "/pull_requests?state=open"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["pull_requests"].length).to eq(1)
    end
  end

  describe "POST /issues/mirror" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123",
        sync_issues: true
      }), "CONTENT_TYPE" => "application/json"
    end

    it "creates an issue mapping" do
      post "/issues/mirror", JSON.generate({
        repository: "kiket-dev/kiket",
        github_issue_number: 10,
        kiket_issue_id: "ISSUE-123",
        direction: "github_to_kiket"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("mirrored")
      expect(body["mapping"]["github_issue_number"]).to eq(10)
    end
  end

  describe "POST /webhooks/github" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "handles pull_request webhook" do
      payload = {
        action: "opened",
        pull_request: {
          number: 42,
          title: "New PR",
          state: "open",
          user: { login: "john" },
          base: { ref: "main" },
          head: { ref: "feature" },
          draft: false,
          merged: false,
          html_url: "https://github.com/kiket-dev/kiket/pull/42"
        },
        repository: {
          full_name: "kiket-dev/kiket"
        }
      }

      post "/webhooks/github", JSON.generate(payload),
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_GITHUB_EVENT" => "pull_request",
        "HTTP_X_GITHUB_DELIVERY" => "12345-67890"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("received")
    end
  end

  describe "POST /sync/trigger" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "triggers a sync job" do
      post "/sync/trigger", JSON.generate({
        repository: "kiket-dev/kiket",
        sync_type: "full"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(202)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("triggered")
      expect(body["job"]["sync_type"]).to eq("full")
    end
  end

  describe "GET /reports/pr_metrics" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"

      post "/pull_requests/sync", JSON.generate({
        repository: "kiket-dev/kiket",
        pr_number: 1,
        title: "PR 1",
        state: "closed",
        merged: true,
        created_at: "2025-11-01T10:00:00Z",
        merged_at: "2025-11-02T10:00:00Z",
        author: "john",
        base_branch: "main",
        head_branch: "feature/1"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "returns PR metrics" do
      get "/reports/pr_metrics"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["total_prs"]).to eq(1)
      expect(body["merged_prs"]).to eq(1)
      expect(body["merge_rate"]).to eq(100.0)
    end
  end

  describe "GET /export/pull_requests/csv" do
    before do
      post "/repositories/register", JSON.generate({
        owner: "kiket-dev",
        name: "kiket",
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"

      post "/pull_requests/sync", JSON.generate({
        repository: "kiket-dev/kiket",
        pr_number: 42,
        title: "Test PR",
        state: "open",
        author: "john",
        base_branch: "main",
        head_branch: "feature"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "exports PRs as CSV" do
      get "/export/pull_requests/csv"

      expect(last_response).to be_ok
      expect(last_response.content_type).to include("text/csv")
      expect(last_response.body).to include("Test PR")
    end
  end
end
