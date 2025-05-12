#!/bin/bash

# --------- CONFIG ---------
GMAIL_ADDRESS="rushikesh.softvan@gmail.com"
GMAIL_APP_PASSWORD="qgdl tzpr dtbh slwa"  # Replace this!
EMAIL_TO="rushikeshmalvadkar200@gmail.com"
MYSQL_CONTAINER="mysql2"
MYSQL_USER="root"
MYSQL_PASS="root"
MYSQL_DB="crone"
TMP_DUMP_DIR="/tmp/mysql_dumps"
LOG_FILE="/var/log/mysql_dump_monitor.log"

# --------- Step 1: Install required packages ---------
echo "🔧 Installing required packages..."
sudo apt update && sudo apt install -y msmtp msmtp-mta mutt

# --------- Step 2: Configure msmtp if not exists ---------
if [ ! -f ~/.msmtprc ]; then
  echo "⚙️ Configuring msmtp..."
  cat <<EOF > ~/.msmtprc
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           $GMAIL_ADDRESS
user           $GMAIL_ADDRESS
password       $GMAIL_APP_PASSWORD

account default : gmail
EOF

  chmod 600 ~/.msmtprc
  echo "✅ Gmail SMTP configured."
else
  echo "✅ msmtp already configured. Skipping email setup."
fi

# --------- Step 3: Configure mutt to use msmtp ---------
mkdir -p ~/.mutt
cat <<EOF > ~/.muttrc
set sendmail="/usr/bin/msmtp"
set use_from=yes
set realname="MySQL Monitor"
set from=$GMAIL_ADDRESS
EOF

# --------- Step 4: Create folders ---------
mkdir -p "$TMP_DUMP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# --------- Logging helper ---------
log() {
  echo "$(date +'%F %T') - $1" | tee -a "$LOG_FILE"
}

# --------- CSV & Email Function ---------
csv_and_email() {
  TIMESTAMP=$(date +%F_%H-%M-%S)
  CSV_FILE="${TMP_DUMP_DIR}/${MYSQL_DB}_${TIMESTAMP}.csv"
  EMAIL_BODY="/tmp/email_body_${TIMESTAMP}.txt"

  log "📊 Generating CSV from database in container $MYSQL_CONTAINER..."

  RETRIES=10
  until docker exec $MYSQL_CONTAINER mysqladmin ping -u$MYSQL_USER -p$MYSQL_PASS --silent &>/dev/null || [ $RETRIES -eq 0 ]; do
    log "⏳ Waiting for MySQL to be ready..."
    sleep 3
    ((RETRIES--))
  done

  if [ $RETRIES -eq 0 ]; then
    log "❌ MySQL not ready."
    return 1
  fi

  # Get all tables in the database
  TABLES=$(docker exec $MYSQL_CONTAINER mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e "SELECT TABLE_NAME FROM information_schema.tables WHERE table_schema='$MYSQL_DB';")

  if [ -z "$TABLES" ]; then
    log "❌ No tables found in database $MYSQL_DB."
    return 1
  fi

  # Create CSV file
  : > "$CSV_FILE"
  for TABLE in $TABLES; do
    log "📝 Processing table: $TABLE"
    # Get column names for header
    COLUMNS=$(docker exec $MYSQL_CONTAINER mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e "SELECT GROUP_CONCAT(COLUMN_NAME) FROM information_schema.columns WHERE table_schema='$MYSQL_DB' AND table_name='$TABLE';")
    
    # Add table name and headers to CSV
    echo "Table: $TABLE" >> "$CSV_FILE"
    echo "$COLUMNS" >> "$CSV_FILE"
    
    # Get table data and append to CSV
    docker exec $MYSQL_CONTAINER mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e "SELECT * FROM $TABLE;" $MYSQL_DB | sed 's/\t/,/g' >> "$CSV_FILE"
    echo "" >> "$CSV_FILE"  # Add newline between tables
  done

  if [[ ! -s "$CSV_FILE" ]]; then
    log "❌ CSV generation failed or empty."
    return 1
  fi

  log "✅ CSV created: $CSV_FILE"

  echo "Attached is the MySQL database CSV created on $TIMESTAMP after container restart." > "$EMAIL_BODY"

  mutt -s "MySQL CSV on Restart" -a "$CSV_FILE" -- "$EMAIL_TO" < "$EMAIL_BODY"

  if [[ $? -eq 0 ]]; then
    log "📧 Email sent to $EMAIL_TO"
    # Truncate all tables after successful email
    for TABLE in $TABLES; do
      log "🗑️ Truncating table: $TABLE"
      docker exec $MYSQL_CONTAINER mysql -u$MYSQL_USER -p$MYSQL_PASS -e "TRUNCATE TABLE $TABLE;" $MYSQL_DB
      if [[ $? -eq 0 ]]; then
        log "✅ Table $TABLE truncated successfully."
      else
        log "❌ Failed to truncate table $TABLE."
      fi
    done
  else
    log "❌ Email failed, skipping table truncation."
  fi

  rm -f "$EMAIL_BODY"
}

# --------- Step 5: Listen for Docker restart ---------
log "👀 Monitoring restarts of container: $MYSQL $MYSQL_CONTAINER"
docker events --filter container="$MYSQL_CONTAINER" --filter event=restart |
while read -r event; do
  log "🔁 Container restarted"
  csv_and_email
done
