---
name: gmail
description: "Manage Gmail emails via Gmail API. Use for reading, sending, and organizing emails."
metadata:
  {
    "openclaw": {
      "emoji": "📧",
      "requires": { "bins": ["gcloud"] },
      "install": [
        {
          "id": "brew",
          "kind": "brew",
          "formula": "google-cloud-sdk",
          "bins": ["gcloud"],
          "label": "Install Google Cloud SDK (brew)"
        },
        {
          "id": "apt",
          "kind": "apt",
          "package": "google-cloud-cli",
          "bins": ["gcloud"],
          "label": "Install Google Cloud SDK (apt)"
        },
        {
          "id": "manual",
          "kind": "script",
          "label": "Download from cloud.google.com/sdk",
          "url": "https://cloud.google.com/sdk/docs/install"
        }
      ]
    }
  }
}

# Gmail Skill

Use Gmail API through `gcloud` CLI for email management.

## Prerequisites

1. Install Google Cloud SDK (`gcloud`)
2. Enable Gmail API in Google Cloud Console
3. Configure OAuth consent screen (if needed)
4. Authenticate with your Gmail account

## Authentication

First-time setup (interactive):

```bash
gcloud auth login --no-browser
gcloud auth application-default login --no-browser
```

This will open a URL. Copy it to browser, authorize, and paste the verification code back.

## Common Operations

### List recent emails

```bash
gcloud auth print-access-token | xargs -I {} curl -H "Authorization: Bearer {}" "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10"
```

### Read an email

```bash
EMAIL_ID="xxx"
gcloud auth print-access-token | xargs -I {} curl -H "Authorization: Bearer {}" "https://gmail.googleapis.com/gmail/v1/users/me/messages/$EMAIL_ID?format=full"
```

### Send an email

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
EMAIL_CONTENT="From: me\nTo: recipient@example.com\nSubject: Test\n\nThis is the body"
ENCODED=$(echo -e "$EMAIL_CONTENT" | base64 | tr -d '\n')
curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d "{\"raw\":\"$ENCODED\"}" \
  "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
```

### Search emails

```bash
QUERY="from:someone@example.com"
gcloud auth print-access-token | xargs -I {} curl -H "Authorization: Bearer {}" "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=$(urlencode "$QUERY")&maxResults=10"
```

## Configuration

- Credentials are stored in `~/.config/gcloud/`
- The Gmail API scope: `https://mail.google.com/` or `https://www.googleapis.com/auth/gmail.readonly` etc.
- Primary account: `gcloud config get-value account`

## Notes

- First Gmail API call may require enabling API in Google Cloud Console
- OAuth token expires after 1 hour; `gcloud auth print-access-token` refreshes automatically if logged in
- For service account / background automation, use `gcloud auth activate-service-account` with a key file
