# Getting Started with GitHub Integration

Connect your GitHub repositories to Kiket for seamless issue mirroring, PR tracking, and workflow automation.

## Prerequisites

- GitHub organization or personal account with admin access
- A Kiket project ready for integration

## Step 1: Create a GitHub App

1. Go to **GitHub Settings → Developer settings → GitHub Apps**
2. Click **New GitHub App**
3. Configure the app:
   - **Name**: "Kiket Integration" (or your preferred name)
   - **Homepage URL**: `https://kiket.dev`
   - **Webhook URL**: Your Kiket webhook endpoint (shown in extension settings)
   - **Webhook secret**: Generate a secure random string

4. Set permissions:
   - **Repository permissions**:
     - Issues: Read & write
     - Pull requests: Read & write
     - Contents: Read-only
     - Metadata: Read-only
   - **Organization permissions**:
     - Members: Read-only (optional, for team mentions)

5. Subscribe to events:
   - Issues
   - Issue comment
   - Pull request
   - Pull request review
   - Check suite
   - Check run
   - Push

6. Click **Create GitHub App**
7. Generate and download a private key

## Step 2: Install the GitHub App

1. On your GitHub App page, click **Install App**
2. Select your organization or account
3. Choose repositories to grant access (all or specific repos)
4. Note the **Installation ID** from the URL after installation

## Step 3: Configure in Kiket

1. Go to **Organization Settings → Extensions → GitHub**
2. Enter your credentials:
   - **App ID**: Found on your GitHub App's settings page
   - **Private Key**: Paste the contents of the downloaded `.pem` file
   - **Webhook Secret**: The secret you generated earlier
   - **Installation ID**: From the installation URL

3. Click **Save** and **Test Connection**

## Step 4: Link a Repository

1. Go to **Project Settings → Integrations → GitHub**
2. Click **Add Repository**
3. Select from available repositories
4. Configure sync options:
   - **Sync Mode**: Full, PRs only, or Issues only
   - **Auto-link commits**: Enable to link commits mentioning issue keys
   - **PR Status Sync**: Keep check statuses synchronized

## Step 5: Set Up Workflow Automations

Example: Auto-transition issues when PRs are merged:

```yaml
automations:
  - name: close_on_pr_merge
    trigger:
      event: github.pull_request.merged
    conditions:
      - field: pull_request.linked_issues
        operator: not_empty
    actions:
      - type: transition
        to: done
        comment: "Closed via PR #{{ pull_request.number }}"
```

## Next Steps

- [View example workflows](./examples/)
- Set up branch protection rules
- Configure PR review requirements
- Enable commit message validation
