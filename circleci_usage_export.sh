#!/bin/bash

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --org_id \"ORG_ID\"    Organization ID(s) (comma-separated)"
  echo "                      Example: --org_id \"org_id_1,org_id_2\" or --org_id \"org_id_1, org_id_2\""
  echo "  --token TOKEN        CircleCI API Token (not required if CIRCLE_TOKEN is set locally)"
  echo "  --start START_DATE   Start date in YYYY-MM-DD format or with time (required unless START_DATE env var is set)"
  echo "  --end END_DATE       End date in YYYY-MM-DD format or with time (required unless END_DATE env var is set)"
  echo "  --output DIR         Output directory (default: current directory)"
  echo "  --debug              Enable debug mode for detailed API responses"
  echo "  --help               Display this help message"
  exit 1
}

# Default values
OUTPUT_DIR="."
DEBUG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org_id)
      ORG_ID="$2"
      shift 2
      ;;
    --token)
      CIRCLE_TOKEN="$2"
      shift 2
      ;;
    --start)
      START_DATE="$2"
      shift 2
      ;;
    --end)
      END_DATE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Check required parameters
if [ -z "$ORG_ID" ]; then
  echo "Error: Organization ID is required. Use --org_id or set ORG_ID environment variable."
  usage
fi

if [ -z "$CIRCLE_TOKEN" ]; then
  echo "Error: CircleCI API Token is required. Use --token or set CIRCLE_TOKEN environment variable."
  usage
fi

if [ -z "$START_DATE" ]; then
  echo "Error: Start date is required. Use --start or set START_DATE environment variable."
  usage
fi

if [ -z "$END_DATE" ]; then
  echo "Error: End date is required. Use --end or set END_DATE environment variable."
  usage
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Validate date format
validate_date() {
  local date_str="$1"
  local name="$2"
  
  # Basic validation for YYYY-MM-DD format with optional leading zeros
  if ! [[ "$date_str" =~ ^[0-9]{4}-(0?[1-9]|1[0-2])-(0?[1-9]|[12][0-9]|3[01])(T[0-9:]+Z)?$ ]]; then
    echo "Error: $name date format is invalid. Please use YYYY-MM-DD or YYYY-MM-DDThh:mm:ssZ"
    echo "Examples: 2025-4-15, 2025-04-15, or 2025-04-15T00:00:00Z"
    exit 1
  fi
  
  # Ensure month and day have leading zeros
  if [[ "$date_str" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})$ ]]; then
    year="${BASH_REMATCH[1]}"
    month=$(printf "%02d" "${BASH_REMATCH[2]}")
    day=$(printf "%02d" "${BASH_REMATCH[3]}")
    echo "${year}-${month}-${day}"
  else
    echo "$date_str"
  fi
}

# Format dates if they don't include time
format_date() {
  local date_str="$1"
  local date_type="$2"
  
  if [[ "$date_str" == *"T"* ]]; then
    echo "$date_str"
  else
    # Different time formatting for start and end dates
    if [[ "$date_type" == "start" ]]; then
      echo "${date_str}T00:00:00Z"
    else
      echo "${date_str}T23:59:59Z"
    fi
  fi
}

# Validate and standardize date formats
START_DATE=$(validate_date "$START_DATE" "Start")
END_DATE=$(validate_date "$END_DATE" "End")

# Format dates if needed
START_DATE_FORMATTED=$(format_date "$START_DATE" "start")
END_DATE_FORMATTED=$(format_date "$END_DATE" "end")

echo "Using organization ID(s): $ORG_ID"
echo "Date range: $START_DATE_FORMATTED to $END_DATE_FORMATTED"

# Convert comma-separated org IDs into JSON array format
# Remove all spaces, then trim
ORG_ID_CLEANED=$(echo "$ORG_ID" | tr -d ' ' | sed 's/^\s*//;s/\s*$//')
IFS=',' read -ra ORG_IDS <<< "$ORG_ID_CLEANED"
ORG_IDS_JSON=$(printf '"%s",' "${ORG_IDS[@]}" | sed 's/,$//')

# Prepare API payload
API_PAYLOAD="{\"start\":\"${START_DATE_FORMATTED}\",\"end\":\"${END_DATE_FORMATTED}\",\"shared_org_ids\":[${ORG_IDS_JSON}]}"
echo "API Payload: $API_PAYLOAD"

# Get the first org ID from the array for the API URL
FIRST_ORG_ID="${ORG_IDS[0]}"

# Make the first API call to create the usage export job
echo "Creating usage export job..."
API_RESPONSE=$(curl --silent --request POST \
  --url "https://circleci.com/api/v2/organizations/${FIRST_ORG_ID}/usage_export_job" \
  --header "Circle-Token: ${CIRCLE_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "$API_PAYLOAD")

if [ "$DEBUG" = true ]; then
  echo "Debug - API response:"
  echo "$API_RESPONSE" | jq
fi

# Check if the API response contains an error message
if [[ $(echo "$API_RESPONSE" | jq -r 'has("message")') == "true" ]]; then
  echo "Error from CircleCI API: $(echo "$API_RESPONSE" | jq -r '.message')"
  echo "Full response: $API_RESPONSE"
  exit 1
fi

usage_export_job_id=$(echo "$API_RESPONSE" | jq -r '.usage_export_job_id // "null"')

# Check if the job ID was retrieved successfully
if [ -z "$usage_export_job_id" ] || [ "$usage_export_job_id" == "null" ]; then
  echo "Failed to create usage export job. Response:"
  echo "$API_RESPONSE" | jq
  exit 1
fi
echo "Usage export job created with ID: $usage_export_job_id"

# Initialize variables for polling
max_attempts=10
attempt=0
job_state="processing"

# Poll for job status until it's no longer "processing" or max attempts reached
while [[ "$job_state" == "processing" && $attempt -lt $max_attempts ]]; do
  # Make the second API call to get the status of the usage export job
  job_status=$(curl --silent --request GET \
    --url "https://circleci.com/api/v2/organizations/${FIRST_ORG_ID}/usage_export_job/${usage_export_job_id}" \
    --header "Circle-Token: ${CIRCLE_TOKEN}")
  
  # Check for API errors
  if [[ $(echo "$job_status" | jq -r 'has("message")') == "true" ]]; then
    echo "Error checking job status: $(echo "$job_status" | jq -r '.message')"
    if [ "$DEBUG" = true ]; then
      echo "Full response: $job_status"
    fi
    exit 1
  fi
  
  # Output the job status
  echo "Job status:"
  echo "$job_status" | jq
  
  # Extract the value of the 'state' key
  job_state=$(echo "$job_status" | jq -r '.state // "null"')
  
  if [ -z "$job_state" ] || [ "$job_state" == "null" ]; then
    echo "Error: Could not determine job state. Response:"
    echo "$job_status" | jq
    exit 1
  fi
  
  echo "Job state: $job_state"
  
  # Increment the attempt counter
  attempt=$((attempt + 1))
  
  # Sleep for a while before the next check
  if [[ "$job_state" == "processing" ]]; then
    echo "Job is still processing. Waiting for 30 seconds before checking again... (Attempt $attempt/$max_attempts)"
    sleep 30
  fi
done

# Check if the job has completed
if [[ "$job_state" == "completed" ]]; then
  echo "Job has completed. Downloading files..."
  
  # Extract download URLs
  download_urls=$(echo "$job_status" | jq -r '.download_urls[]')
  
  # Generate a timestamp for the filename
  timestamp=$(date +"%Y%m%d_%H%M%S")
  
  # Format dates for filename
  start_date_filename=$(echo "$START_DATE" | tr ':' '-' | tr 'T' '_')
  end_date_filename=$(echo "$END_DATE" | tr ':' '-' | tr 'T' '_')
  
  # Download each file
  for url in $download_urls; do
    echo "Downloading $url..."
    
    # File name for the compressed file
    gz_file="${OUTPUT_DIR}/usage_report_$(basename "$url")"
    
    # Download the file
    curl -L -o "$gz_file" "$url"
    
    if [ $? -eq 0 ]; then
      # Unzip the downloaded .csv.gz file and create final filename
      output_file="${OUTPUT_DIR}/usage_report_${start_date_filename}_to_${end_date_filename}_${ORG_ID}.csv"
      echo "Unzipping to $output_file..."
      gunzip -c "$gz_file" > "$output_file"
      echo "Successfully created $output_file"
      
      # Remove the compressed file unless user requests to keep it
      rm "$gz_file"
    else
      echo "Failed to download $url"
    fi
  done
  
  echo "All files downloaded and processed."
else
  echo "Job has finished with state: $job_state"
  if [[ "$job_state" == "processing" ]]; then
    echo "Max attempts reached. Job is still processing."
  fi
  exit 1
fi

echo "CircleCI usage report generation completed successfully!"