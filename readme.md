# CircleCI Usage Export Script

This script programmatically creates a usage export using the CircleCI v2 API and downloads related usage export reports locally. 

## Prerequisites

The following are required to run this script:
- `curl` and `jq` installed on the system
- A valid CircleCI API token ([Generate API token][token-link])
- CircleCI organization ID(s) (found in [organization settings][org-settings])

Additional information about CircleCI API tokens is available in the [documentation on managing API tokens][api-docs].

## Quick Start

1. **Download the script**:
   ```bash
   curl -LJO https://raw.githubusercontent.com/CircleCI-Public/generate_cci_usage_report/main/circleci_usage_export.sh
   ```

2. **Make the script executable**:

   ```bash
   chmod +x circleci_usage_export.sh
   ```

## Usage

The script can be run using either command line arguments or environment variables:

### Command Line Options

```bash
./circleci_usage_export.sh [options]
```

Available options:

- `--org_id "ORG_ID"` - Organization ID(s) (comma-separated)
- `--token TOKEN` - (not required if CIRCLE_TOKEN is set locally)
- `--start START_DATE` - Start date in YYYY-MM-DD format
- `--end END_DATE` - End date in YYYY-MM-DD format
- `--output DIR` - Output directory (default: current directory)
- `--debug` - Enable debug mode
- `--help` - Display help message

Example:

```bash
./circleci_usage_export.sh \
  --org_id "xxx-1xx, xxx-2xx" \
  --token "your-circle-token" \
  --start "2025-04-01" \
  --end "2025-04-30" \
  --output "./reports"
```

### Environment Variables and Defaults

The script accepts the following environment variables:
- `CIRCLE_TOKEN` - CircleCI API Token
- `ORG_ID` - Organization ID(s)
- `START_DATE` - Start date for the report
- `END_DATE` - End date for the report

Default values can be added to and configured by modifying the script's default section:

```bash
# Default values
OUTPUT_DIR="."     # Default output directory
DEBUG=false        # Default debug mode setting
```

## Date Formats

Supported date formats:

- Simple date: `2025-4-15` or `2025-04-15`
- Date with time: `2025-04-15T00:00:00Z`

## Output

The script generates CSV files in the specified output directory with the naming format:

```text
usage_report_START-DATE_to_END-DATE_ORG-ID.csv
```

## Debug Mode

For detailed API responses, use the debug flag:

```bash
./circleci_usage_export.sh --debug [other options]
```

[token-link]: https://app.circleci.com/settings/user/tokens
[org-settings]: https://circleci.com/docs/introduction-to-the-circleci-web-app/#organization-settings
[api-docs]: https://circleci.com/docs/managing-api-tokens/#creating-a-personal-api-token
