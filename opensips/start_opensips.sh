#!/bin/bash
set -e
echo "=== Starting OpenSIPS Container ==="

# Substitute the values for PRESENCE_IP, IMS_DOMAIN, and MYSQL_IP in the configuration files
echo "Configuring OpenSIPS with PRESENCE_IP=$PRESENCE_IP, IMS_DOMAIN=$IMS_DOMAIN, MYSQL_IP=$MYSQL_IP"
sed -i 's|PRESENCE_IP|'$PRESENCE_IP'|g' /etc/opensips/opensips.cfg
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/opensips/opensipsctlrc
sed -i 's|MYSQL_IP|'$MYSQL_IP'|g' /etc/opensips/opensips.cfg

# Start syslog-ng with error handling
echo "Starting syslog-ng..."
if /etc/init.d/syslog-ng start 2>/dev/null; then
    echo "Syslog-ng started successfully"
else
    echo "WARNING: Syslog-ng failed to start (this is OK in Docker)"
fi

# Wait for external MySQL container
echo "Waiting for external MySQL container to be ready..."
COUNTER=0
MAX_TRIES=30
until mysqladmin ping -h ${MYSQL_IP} --silent 2>/dev/null; do
    COUNTER=$((COUNTER+1))
    if [ $COUNTER -gt $MAX_TRIES ]; then
        echo "ERROR: External MySQL not reachable after $MAX_TRIES seconds!"
        exit 1
    fi
    echo "Waiting for external MySQL at ${MYSQL_IP}... ($COUNTER/$MAX_TRIES)"
    sleep 1
done

echo "External MySQL is ready!"

# Setup OpenSIPS database
echo "Setting up OpenSIPS database..."
mysql -h ${MYSQL_IP} -u root -e "CREATE DATABASE IF NOT EXISTS opensips;" 2>/dev/null || echo "Database may already exist"

# Create user and grant privileges
mysql -h ${MYSQL_IP} -u root <<EOF 2>/dev/null || echo "User may already exist"
CREATE USER IF NOT EXISTS 'opensips'@'%' IDENTIFIED BY 'opensipsrw';
CREATE USER IF NOT EXISTS 'opensips'@'${PRESENCE_IP}' IDENTIFIED BY 'opensipsrw';
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'%';
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'${PRESENCE_IP}';
FLUSH PRIVILEGES;
EOF

# Check if tables exist
TABLE_COUNT=$(mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "SHOW TABLES;" 2>/dev/null | wc -l)
if [ "$TABLE_COUNT" -lt 2 ]; then
    echo "Creating OpenSIPS tables..."
    
    # Import standard tables
    mysql -h ${MYSQL_IP} -u root opensips < /usr/share/opensips/mysql/standard-create.sql
    
    echo "Standard tables created!"
fi

# CRITICAL: Ensure ALL presence tables exist (MySQL 8 compatible)
echo "Checking presence tables..."

# Check and create xcap table
if ! mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "DESCRIBE xcap;" >/dev/null 2>&1; then
    echo "Creating xcap table..."
    mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips << 'EOSQL'
CREATE TABLE xcap (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    username VARCHAR(64) NOT NULL,
    domain VARCHAR(64) NOT NULL,
    doc MEDIUMBLOB NOT NULL,
    doc_type INT(11) NOT NULL,
    etag VARCHAR(64) NOT NULL,
    source INT(11) NOT NULL,
    doc_uri VARCHAR(255) NOT NULL,
    port INT(11) NOT NULL,
    CONSTRAINT doc_uri_idx UNIQUE (doc_uri(50), doc_type, username, domain)
) ENGINE=InnoDB;
CREATE INDEX account_doc_type_idx ON xcap (username, domain, doc_type, doc_uri(50));
INSERT INTO version (table_name, table_version) VALUES ('xcap', 4) ON DUPLICATE KEY UPDATE table_version=4;
EOSQL
fi

# Check and create presentity table
if ! mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "DESCRIBE presentity;" >/dev/null 2>&1; then
    echo "Creating presentity table..."
    mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips << 'EOSQL'
CREATE TABLE presentity (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    username VARCHAR(64) NOT NULL,
    domain VARCHAR(64) NOT NULL,
    event VARCHAR(64) NOT NULL,
    etag VARCHAR(64) NOT NULL,
    expires INT(11) NOT NULL,
    received_time INT(11) NOT NULL,
    body BLOB NOT NULL,
    sender VARCHAR(128) NOT NULL,
    priority INT(11) DEFAULT 0 NOT NULL,
    CONSTRAINT presentity_idx UNIQUE (username, domain, event, etag)
) ENGINE=InnoDB;
CREATE INDEX presentity_expires ON presentity (expires);
INSERT INTO version (table_name, table_version) VALUES ('presentity', 5) ON DUPLICATE KEY UPDATE table_version=5;
EOSQL
fi

# Check and create active_watchers table
if ! mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "DESCRIBE active_watchers;" >/dev/null 2>&1; then
    echo "Creating active_watchers table..."
    mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips << 'EOSQL'
CREATE TABLE active_watchers (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    presentity_uri VARCHAR(128) NOT NULL,
    watcher_username VARCHAR(64) NOT NULL,
    watcher_domain VARCHAR(64) NOT NULL,
    to_user VARCHAR(64) NOT NULL,
    to_domain VARCHAR(64) NOT NULL,
    event VARCHAR(64) DEFAULT 'presence' NOT NULL,
    event_id VARCHAR(64),
    to_tag VARCHAR(128) NOT NULL,
    from_tag VARCHAR(128) NOT NULL,
    callid VARCHAR(255) NOT NULL,
    local_cseq INT(11) NOT NULL,
    remote_cseq INT(11) NOT NULL,
    contact VARCHAR(128) NOT NULL,
    record_route TEXT,
    expires INT(11) NOT NULL,
    status INT(11) DEFAULT 2 NOT NULL,
    reason VARCHAR(64),
    version INT(11) DEFAULT 0 NOT NULL,
    socket_info VARCHAR(128) NOT NULL,
    local_contact VARCHAR(128) NOT NULL,
    sharing_tag VARCHAR(64),
    CONSTRAINT active_watchers_idx UNIQUE (presentity_uri, callid, to_tag, from_tag)
) ENGINE=InnoDB;
CREATE INDEX active_watchers_expires ON active_watchers (expires);
INSERT INTO version (table_name, table_version) VALUES ('active_watchers', 11) ON DUPLICATE KEY UPDATE table_version=11;
EOSQL
fi

# Check and create watchers table
if ! mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "DESCRIBE watchers;" >/dev/null 2>&1; then
    echo "Creating watchers table..."
    mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips << 'EOSQL'
CREATE TABLE watchers (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    presentity_uri VARCHAR(128) NOT NULL,
    watcher_username VARCHAR(64) NOT NULL,
    watcher_domain VARCHAR(64) NOT NULL,
    event VARCHAR(64) DEFAULT 'presence' NOT NULL,
    status INT(11) NOT NULL,
    reason VARCHAR(64),
    inserted_time INT(11) NOT NULL,
    CONSTRAINT watchers_idx UNIQUE (presentity_uri, watcher_username, watcher_domain, event)
) ENGINE=InnoDB;
INSERT INTO version (table_name, table_version) VALUES ('watchers', 4) ON DUPLICATE KEY UPDATE table_version=4;
EOSQL
fi

# Check and create pua table
if ! mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips -e "DESCRIBE pua;" >/dev/null 2>&1; then
    echo "Creating pua table..."
    mysql -h ${MYSQL_IP} -u opensips -popensipsrw opensips << 'EOSQL'
CREATE TABLE pua (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    pres_uri VARCHAR(128) NOT NULL,
    pres_id VARCHAR(255) NOT NULL,
    event INT(11) NOT NULL,
    expires INT(11) NOT NULL,
    desired_expires INT(11) NOT NULL,
    flag INT(11) NOT NULL,
    etag VARCHAR(128) NOT NULL,
    tuple_id VARCHAR(64),
    watcher_uri VARCHAR(128) NOT NULL,
    call_id VARCHAR(255) NOT NULL,
    to_tag VARCHAR(128) NOT NULL,
    from_tag VARCHAR(128) NOT NULL,
    cseq INT(11) NOT NULL,
    record_route TEXT,
    contact VARCHAR(128) NOT NULL,
    remote_contact VARCHAR(128) NOT NULL,
    version INT(11) NOT NULL,
    extra_headers TEXT
) ENGINE=InnoDB;
CREATE INDEX pua_idx ON pua (pres_uri, pres_id);
INSERT INTO version (table_name, table_version) VALUES ('pua', 8) ON DUPLICATE KEY UPDATE table_version=8;
EOSQL
fi

echo "All presence tables verified/created!"

# Create necessary directories with proper permissions
echo "Creating OpenSIPS directories..."
mkdir -p /var/run/opensips
mkdir -p /var/log/opensips
touch /var/run/opensips/opensips.pid
touch /var/log/opensips.log

# Ensure opensips user exists
groupadd -f opensips 2>/dev/null || true
useradd -g opensips opensips 2>/dev/null || true

# Set ownership and permissions
chown -R opensips:opensips /var/run/opensips /var/log/opensips
chmod 755 /var/run/opensips /var/log/opensips
chmod 644 /var/run/opensips/opensips.pid /var/log/opensips.log

# Verify OpenSIPS configuration
echo "Verifying OpenSIPS configuration..."
if opensips -c -f /etc/opensips/opensips.cfg; then
    echo "✓ OpenSIPS configuration is valid"
else
    echo "✗ ERROR: OpenSIPS configuration has errors!"
    exit 1
fi

# Start OpenSIPS as root (simpler and works)
echo "Starting OpenSIPS..."
opensips -f /etc/opensips/opensips.cfg -P /var/run/opensips/opensips.pid -w /var/run/opensips 2>&1 | tee -a /var/log/opensips.log &

# Wait for OpenSIPS to create PID file
echo "Waiting for OpenSIPS to start..."
COUNTER=0
MAX_TRIES=15
until [ -f /var/run/opensips/opensips.pid ] && [ -s /var/run/opensips/opensips.pid ]; do
    COUNTER=$((COUNTER+1))
    if [ $COUNTER -gt $MAX_TRIES ]; then
        echo ""
        echo "========================================"
        echo "ERROR: OpenSIPS failed to start!"
        echo "========================================"
        echo ""
        echo "OpenSIPS logs (last 100 lines):"
        tail -n 100 /var/log/opensips.log 2>/dev/null || echo "No logs"
        echo ""
        echo "========================================"
        tail -f /dev/null
    fi
    echo "Waiting for OpenSIPS PID file... ($COUNTER/$MAX_TRIES)"
    sleep 1
done

PID=$(cat /var/run/opensips/opensips.pid)
echo ""
echo "========================================"
echo "✓ OpenSIPS started successfully!"
echo "========================================"
echo "PID: $PID"
echo "Listening on: udp:${PRESENCE_IP}:5065"
echo ""
ps aux | grep opensips | grep -v grep
echo "========================================"
echo ""

# Monitor logs
echo "Monitoring OpenSIPS logs..."
tail -f /var/log/opensips.log
