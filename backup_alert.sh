#!/bin/bash

# ==================== CONFIGURATION ====================

# Emails
TO_EMAIL="your-email@example.com"
CC_EMAIL="cc-email@example.com"
FROM_EMAIL="backupfail@yourdomain.com"

# ZeptoMail API Key (ENV VAR – REQUIRED)
API_KEY="$ZEPTO_API_KEY"

# Exit if API key is missing
if [ -z "$API_KEY" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: ZEPTO_API_KEY not set" | tee -a "$HOME/backup-test/backup_email.log"
  exit 1
fi

# ==================== DATE HANDLING ====================

# Yesterday (for filename & email)
YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
YEAR=$(date -d "yesterday" '+%Y')
MONTH=$(date -d "yesterday" '+%b' | tr '[:lower:]' '[:upper:]')   # JAN, FEB

# ==================== PATHS ====================

BASE_PATH="/home/ubuntu/DBBACKUPLOGS/LOCAL"
CSV_DIR="${BASE_PATH}/${YEAR}/${MONTH}"

LOG_FILE="$HOME/backup-test/backup_email.log"

# ==================== FIND LATEST CSV ====================

RECENT_FILE=$(ls -t "${CSV_DIR}/LOCAL_${YESTERDAY}"_*.csv 2>/dev/null | head -1)

if [ -z "$RECENT_FILE" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - No backup failure CSV found for ${YESTERDAY}" | tee -a "$LOG_FILE"
  exit 0
fi

# ==================== EMAIL SUBJECT ====================

SUBJECT="Urgent: Failed Database Backup on Local server Clients on Date $(date -d 'yesterday' '+%m/%d/%Y')"

# ==================== EMAIL BODY (PLAIN TEXT) ====================

BODY=$(cat <<EOF
Dear Team,

I hope you're doing well. We've identified some issues with database backups failing on several local server clients on Date $(date -d 'yesterday' '+%m/%d/%Y') as detailed in the attached Excel sheet.

Could you please investigate the cause of these failures and take the necessary steps to resolve them?

Your prompt attention to this matter is crucial to ensure data integrity and avoid any potential disruptions.

Please let me know if you need any additional information.

Regards,
DevOps Team
EOF
)

# ==================== ATTACHMENT ====================

FILENAME=$(basename "$RECENT_FILE")
FILEBASE64=$(base64 "$RECENT_FILE" | tr -d '\n')

ATTACHMENTS=$(jq -n \
  --arg name "$FILENAME" \
  --arg content "$FILEBASE64" \
  --arg mime "text/csv" \
  '[{name:$name, content:$content, mime_type:$mime}]')

# ==================== SEND EMAIL ====================

RESPONSE=$(curl -s -X POST "https://api.zeptomail.com/v1.1/email" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: $API_KEY" \
  -d "$(jq -n \
    --arg from "$FROM_EMAIL" \
    --arg to "$TO_EMAIL" \
    --arg cc "$CC_EMAIL" \
    --arg subject "$SUBJECT" \
    --arg textbody "$BODY" \
    --argjson attachments "$ATTACHMENTS" \
    '{
      from: {address: $from},
      to: [{email_address: {address: $to}}],
      cc: [{email_address: {address: $cc}}],
      subject: $subject,
      textbody: $textbody,
      attachments: $attachments
    }')")

# ==================== LOG RESULT ====================

if echo "$RESPONSE" | grep -q '"message":"OK"'; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Email sent successfully with attachment $RECENT_FILE" | tee -a "$LOG_FILE"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR sending email: $RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi
