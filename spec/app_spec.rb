# frozen_string_literal: true

require "spec_helper"

RSpec.describe GitHubExtension do
  subject(:extension) { described_class.new }

  let(:context) { build_context }

  describe "#handle_register_repository" do
    let(:payload) do
      {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123",
        "installation_id" => 12345
      }
    end

    it "registers a new repository" do
      result = extension.send(:handle_register_repository, payload, context)

      expect(result[:status]).to eq("registered")
      expect(result[:repository][:full_name]).to eq("kiket-dev/kiket")
      expect(result[:repository][:kiket_project_id]).to eq("proj-123")
    end

    it "requires owner and name" do
      result = extension.send(:handle_register_repository, {
        "kiket_project_id" => "proj-123"
      }, context)

      expect(result[:error]).to be_present
    end
  end

  describe "#handle_list_repositories" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)
    end

    it "lists all repositories" do
      result = extension.send(:handle_list_repositories, {}, context)

      expect(result[:repositories]).to be_an(Array)
      expect(result[:repositories].length).to eq(1)
    end

    it "filters by project_id" do
      result = extension.send(:handle_list_repositories, {
        "kiket_project_id" => "proj-123"
      }, context)

      expect(result[:repositories].length).to eq(1)

      result = extension.send(:handle_list_repositories, {
        "kiket_project_id" => "unknown"
      }, context)

      expect(result[:repositories].length).to eq(0)
    end
  end

  describe "#handle_delete_repository" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)
    end

    it "deletes a repository" do
      result = extension.send(:handle_delete_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket"
      }, context)

      expect(result[:status]).to eq("deleted")

      list_result = extension.send(:handle_list_repositories, {}, context)
      expect(list_result[:repositories].length).to eq(0)
    end

    it "returns error for unknown repository" do
      result = extension.send(:handle_delete_repository, {
        "owner" => "unknown",
        "name" => "unknown"
      }, context)

      expect(result[:error]).to be_present
    end
  end

  describe "#handle_sync_pull_request" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)
    end

    let(:payload) do
      {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 42,
        "title" => "Add new feature",
        "state" => "open",
        "author" => "john",
        "base_branch" => "main",
        "head_branch" => "feature/new",
        "merged" => false,
        "draft" => false
      }
    end

    it "syncs a pull request" do
      result = extension.send(:handle_sync_pull_request, payload, context)

      expect(result[:status]).to eq("synced")
      expect(result[:pull_request][:pr_number]).to eq(42)
      expect(result[:pull_request][:title]).to eq("Add new feature")
    end

    it "updates existing pull request" do
      extension.send(:handle_sync_pull_request, payload, context)

      updated_payload = payload.merge("state" => "closed", "merged" => true)
      result = extension.send(:handle_sync_pull_request, updated_payload, context)

      expect(result[:status]).to eq("synced")
      expect(result[:pull_request][:state]).to eq("closed")
      expect(result[:pull_request][:merged]).to be true
    end
  end

  describe "#handle_list_pull_requests" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)

      extension.send(:handle_sync_pull_request, {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 1,
        "title" => "PR 1",
        "state" => "open",
        "author" => "john",
        "base_branch" => "main",
        "head_branch" => "feature/1"
      }, context)

      extension.send(:handle_sync_pull_request, {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 2,
        "title" => "PR 2",
        "state" => "closed",
        "merged" => true,
        "author" => "jane",
        "base_branch" => "main",
        "head_branch" => "feature/2"
      }, context)
    end

    it "lists all pull requests" do
      result = extension.send(:handle_list_pull_requests, {}, context)

      expect(result[:pull_requests]).to be_an(Array)
      expect(result[:pull_requests].length).to eq(2)
    end

    it "filters by state" do
      result = extension.send(:handle_list_pull_requests, { "state" => "open" }, context)

      expect(result[:pull_requests].length).to eq(1)
      expect(result[:pull_requests][0][:state]).to eq("open")
    end

    it "filters by author" do
      result = extension.send(:handle_list_pull_requests, { "author" => "jane" }, context)

      expect(result[:pull_requests].length).to eq(1)
      expect(result[:pull_requests][0][:author]).to eq("jane")
    end
  end

  describe "#handle_mirror_issue" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123",
        "sync_issues" => true
      }, context)
    end

    it "creates an issue mapping" do
      result = extension.send(:handle_mirror_issue, {
        "repository" => "kiket-dev/kiket",
        "github_issue_number" => 10,
        "kiket_issue_id" => "ISSUE-123",
        "direction" => "github_to_kiket"
      }, context)

      expect(result[:status]).to eq("mirrored")
      expect(result[:mapping][:github_issue_number]).to eq(10)
      expect(result[:mapping][:kiket_issue_id]).to eq("ISSUE-123")
    end
  end

  describe "#handle_receive_webhook" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)
    end

    it "handles pull_request webhook" do
      payload = {
        "event_type" => "pull_request",
        "delivery_id" => "12345",
        "payload" => {
          "action" => "opened",
          "pull_request" => {
            "number" => 42,
            "title" => "New PR",
            "state" => "open",
            "user" => { "login" => "john" },
            "base" => { "ref" => "main" },
            "head" => { "ref" => "feature" },
            "draft" => false,
            "merged" => false
          },
          "repository" => {
            "full_name" => "kiket-dev/kiket"
          }
        }
      }

      result = extension.send(:handle_receive_webhook, payload, context)

      expect(result[:status]).to eq("received")
      expect(result[:event_type]).to eq("pull_request")
    end
  end

  describe "#handle_trigger_sync" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)
    end

    it "triggers a sync job" do
      result = extension.send(:handle_trigger_sync, {
        "repository" => "kiket-dev/kiket",
        "sync_type" => "full"
      }, context)

      expect(result[:status]).to eq("triggered")
      expect(result[:job][:sync_type]).to eq("full")
      expect(result[:job][:state]).to eq("pending")
    end
  end

  describe "#handle_pr_metrics_report" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)

      extension.send(:handle_sync_pull_request, {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 1,
        "title" => "PR 1",
        "state" => "closed",
        "merged" => true,
        "created_at" => "2025-11-01T10:00:00Z",
        "merged_at" => "2025-11-02T10:00:00Z",
        "author" => "john",
        "base_branch" => "main",
        "head_branch" => "feature/1"
      }, context)

      extension.send(:handle_sync_pull_request, {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 2,
        "title" => "PR 2",
        "state" => "closed",
        "merged" => false,
        "author" => "jane",
        "base_branch" => "main",
        "head_branch" => "feature/2"
      }, context)
    end

    it "returns PR metrics" do
      result = extension.send(:handle_pr_metrics_report, {}, context)

      expect(result[:total_prs]).to eq(2)
      expect(result[:merged_prs]).to eq(1)
      expect(result[:merge_rate]).to eq(50.0)
    end
  end

  describe "#handle_export_prs_csv" do
    before do
      extension.send(:handle_register_repository, {
        "owner" => "kiket-dev",
        "name" => "kiket",
        "kiket_project_id" => "proj-123"
      }, context)

      extension.send(:handle_sync_pull_request, {
        "repository" => "kiket-dev/kiket",
        "pr_number" => 42,
        "title" => "Test PR",
        "state" => "open",
        "author" => "john",
        "base_branch" => "main",
        "head_branch" => "feature"
      }, context)
    end

    it "exports PRs as CSV" do
      result = extension.send(:handle_export_prs_csv, {}, context)

      expect(result[:content_type]).to eq("text/csv")
      expect(result[:data]).to include("Test PR")
      expect(result[:data]).to include("kiket-dev/kiket")
    end
  end
end
