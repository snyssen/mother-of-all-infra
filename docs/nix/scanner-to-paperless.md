# Scanner to Paperless Integration

## Overview

This guide explains how to set up automatic document ingestion from a scanner directly into Paperless-ngx using the `printing` NixOS module configured on your laptop (sninful).

## Architecture

```
┌──────────────┐
│   Scanner    │
│  (Hardware)  │
└──────┬───────┘
       │ USB/Network
       │
┌──────▼────────────────────────┐
│  NixOS (sninful laptop)       │
├───────────────────────────────┤
│ • SANE (scanner drivers)      │
│ • scanservjs (web UI)         │
│   - Scans documents to PDF    │
│   - Provides action menu      │
│ • Paperless action (optional) │
│   - User-triggered via UI     │
│ • paperless-upload script     │
│   - Called by action          │
└───────────────┬───────────────┘
                │ HTTPS
                │ API Token Auth
┌───────────────▼───────────────┐
│  Paperless-ngx (Server)       │
│  API: /api/documents/...      │
└───────────────────────────────┘
```

## How It Works

1. **Scanning**: Use scanservjs web interface to scan documents
2. **PDF Generation**: scanservjs saves the scanned document as a PDF
3. **Action Selection**: After scanning, choose "Upload to Paperless" from the available actions
4. **Manual Trigger**: The action is user-triggered (you can scan without uploading if desired)
5. **Auto-Upload**: When selected, the paperless-upload script is executed with the PDF file path
6. **Processing**: Paperless receives the document and processes it (OCR, tagging, etc.)

## Components

### scanservjs
- **Web Interface**: Access at `http://localhost:8080` (when enabled)
- **Purpose**: Provides a user-fwith a customizable action menu
- **Custom Actions**: Displays "Upload to Paperless" as a post-scan action

### Paperless Upload Action
- **Type**: scanservjs custom action
- **Trigger**: Manually selected by user after scanning (from action menu)
- **Execution**: Calls the paperless-upload script with the scanned file
- **Flexibility**: Can be applied selectively (scan without uploading if desired)

### paperless-upload Script
- **Location**: Available in system PATH when enabled
- **Purpose**: Uploads PDFs to Paperless API with authentication
- **Features**: Error handling, logging, timeout protection
- **Called By**: Paperless Upload action
- **Logging**: View with `journalctl -u scanservjs-paperless-watcher -f`

## Configuration

The configuration is in `/nix/hosts/sninful/configuration.nix`:

```nix
printing = {
  enable = true;
  scanner = {
    enable = true;
    paperless = {
      enable = false;  # Set to true after setting up secrets
      url = "https://paperless.snyssen.be";
      # Only reference the secret path when enabled
      apiTokenPath =
        if config.printing.scanner.paperless.enable
        then config.sops.secrets."paperless/api-token".path
        else "/dev/null";
    };
  };
};
```

## Setup Instructions

### Step 1: Generate Paperless API Token

1. Go to your Paperless instance: https://paperless.snyssen.be
2. Log in with your account
3. Navigate to **Settings** → **API Tokens**
4. Click **Create New Token**
5. Give it a descriptive name (e.g., "Scanner Upload - sninful")
6. Copy the generated token - you'll need it in the next step

### Step 2: Create Encrypted Secrets File

1. Copy the template to create your secrets file:
   ```bash
   cd nix/hosts/sninful/data
   cp secrets.yaml.template secrets.yaml
   ```

2. Edit the file with SOPS (auto-encrypts on save):
   ```bash
   just sops-update
   # Navigate to nix/hosts/sninful/data/secrets.yaml when prompted
   ```

3. Replace `REPLACE_WITH_YOUR_PAPERLESS_API_TOKEN` with your actual token from Step 1

4. Save and exit - the file will be automatically encrypted

### Step 3: Enable Paperless Integration

Edit `/nix/hosts/sninful/configuration.nix` and change:

```nix
    if config.printing.scanner.paperless.enable
    then config.sops.secrets."paperless/api-token".path
    else "/dev/null"
paperless = {
  enable = true;  # Changed from false
  url = "https://paperless.snyssen.be";
  apiTokenPath = config.sops.secrets."paperless/api-token".path;
};
```

### Step 4: Build and Deploy

```bash
nh os switch -H sninful
```

This will:
- Install and configure scanservjs
- Add the "Upload to Paperless" action
- Make the upload script available
- Configure SANE scanner drivers

### Step 5: Test the Setup

1. **Test scanner access**:
   ```bash
   scanimage -L
   ```
   Should show your connected scanner.

2. **Test scanservjs**:
   - Open http://localhost:8080 in your browser
   - Perform a test scan
   - Check the action menu available after the scan completes

3. **Test the Paperless Upload Action**:
   - After your test scan, you should see "Upload to Paperless" in the action menu
   - Click it to upload the scanned document
   - Check scanservjs logs for confirmation:
     ```bash
     journalctl -u scanservjs -n 20
     ```

4. **Verify in Paperless**:
   - Go to https://paperless.snyssen.be
   - Check if the document appears in your inbox

## Usage

### Scanning and Uploading via Web Interface

1. Open http://localhost:8080 in your browser
2. Adjust scan settings (resolution, color mode, etc.) as needed
3. Click **Scan** to initiate the scan
4. Wait for the scan to complete
5. Once complete, you'll see the scanned file with available actions
6. Click **Upload to Paperless** to upload the document
7. The document will be sent to your Paperless instance
8. Alternatively, click another action or download the file

### Scanning Without Uploading

Simply don't select the "Upload to Paperless" action. Your scanned documents will be saved locally and can be processed later.

### Manual Upload

You can also manually upload PDFs from the command line:

```bash
paperless-upload /path/to/document.pdf
```

## Monitoring

### Check scanservjs Service Status

```bash
systemctl status scanservjs
```

### View scanservjs Logs (includes action execution)

```bash
journalctl -u scanservjs -f
```

### Check Recent Action Logs

```bash
journalctl -u scanservjs -n 30
```

## Troubleshooting

### Scanner Not Detected

1. Check USB connection or network settings
2. Verify SANE can see the scanner:
   ```bash
   scanimage -L
   ```
3. Check if drivers are loaded:
   ```bash
   lsusb  # For USB scanners
   ```

### Upload Fails

1. **Check API token**:
   - Verify the token is correct in secrets.yaml
   - Check token permissions in Paperless

2. **Test connectivity**:
   ```bash
   curl -I https://paperless.snyssen.be
   ```

3. **Manual test upload**:
   ```bash
   paperless-upload /path/to/test.pdf
   ```

4. **Check service logs**:
   ```bash
   journalctl -u scanservjs -n 50
   ```

### Service Won't Start

1. Check scanservjs service status:
   ```bash
   systemctl status scanservjs
   ```

2. Verify secrets file exists and is readable (when Paperless integration enabled):
   ```bash
   ls -l /run/secrets/paperless/api-token
   ```

3. Check scanservjs service logs:
   ```bash
   journalctl -u scanservjs -n 50
   ```

## Security Notes

- **API Token**: Stored encrypted with SOPS, only readable by root
- **Transport**: All communication with Paperless uses HTTPS
- **File Permissions**: Scanner output directory is restricted to scanservjs user
- **Token Rotation**: Regenerate token periodically in Paperless settings
- **Action Execution**: Actions run as the scanservjs user with appropriate permissions

## Future Enhancements

Potential improvements not yet implemented:

- **Physical Scan Button**: Support for hardware scan button via `scanbd` or `insaned`
- **Notifications**: Push notifications via ntfy on successful/failed uploads
- **Retry Logic**: Automatic retry for failed uploads
- **Multiple Targets**: Support uploading to multiple Paperless instances
- **Document Naming**: Auto-naming based on date, tags, or document type
- **Email Integration**: Optional email notifications on upload status

## Related Documentation

- [Paperless Stack](../ansible/stacks/paperless.md)
- [SOPS Secrets Management](secrets-management.md)
- [NixOS Printing Module](../nix/modules/printing.md)

## Module Options Reference

### `printing.enable`
- **Type**: boolean
- **Default**: `true`
- **Description**: Enable printing support (CUPS, HP drivers)

### `printing.scanner.enable`
- **Type**: boolean
- **Default**: `false`
- **Description**: Enable scanner support with scanservjs

### `printing.scanner.paperless.enable`
- **Type**: boolean
- **Default**: `false`optional upload action
- **Description**: Enable automatic upload to Paperless-ngx

### `printing.scanner.paperless.url`
- **Type**: string
- **Example**: `"https://paperless.snyssen.be"`
- **Description**: Paperless-ngx instance URL (without trailing slash)

### `printing.scanner.paperless.apiTokenPath`
- **Type**: path
- **Description**: Path to file containing the Paperless API token (provided by SOPS)
