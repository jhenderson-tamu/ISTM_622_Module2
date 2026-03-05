#!/bin/bash

#On my honor, as an Aggie, I have neither given nor received unauthorized assistance on this assignment. 
#I further affirm that I have not and will not provide this code to any person, platform, or repository, 
#without the express written permission of Dr. Gomillion. 
#I understand that any violation of these standards will have serious repercussions.

# -----------------------------------------------------------
# SCRIPT EXECUTION CONTROLS (Logging, Non-Interactive Mode, Error Handling)
# -----------------------------------------------------------

# Redirect all script output to log file, system logger, and console for debugging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Disable interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# Exit immediately if any command fails
set -e

# Display the line number if the script encounters an error
trap 'echo "ERROR: Script failed at line $LINENO. Check /var/log/user-data.log"' ERR

# ----------------------------
# REQUIRED VARIABLES
# ----------------------------

LINUX_USER="jhenderson"
UIN="737003891"
ZIP_URL="https://622.gomillion.org/data/${UIN}.zip"
USER_HOME="/home/${LINUX_USER}"
ZIP_PATH="${USER_HOME}/${UIN}.zip"
ETL_PATH="${USER_HOME}/etl.sql"
VIEWS_PATH="${USER_HOME}/views.sql"
DB_NAME="POS"
ROOT_PW="1qaz!QAZ2wsx@WSX"
DB_PASS='3edc#EDC4rfv$RFV'

echo "Starting MariaDB installation..."

# -----------------------------------------------------------
# STEP 1: Update the system
# -----------------------------------------------------------

# Update package index so the system knows about the latest packages.
echo "Updating system..."
apt update -y -qq

# Upgrade currently installed packages to the latest versions.
# This helps ensure security patches are applied.
apt upgrade -y -qq

# -----------------------------------------------------------
# STEP 2: Install required dependencies
# -----------------------------------------------------------

# Install tools needed to securely add the MariaDB repository.
echo "Installing required packages..."
apt install -y curl ca-certificates gnupg lsb-release unzip wget -qq

# -----------------------------------------------------------
# STEP 3: Add MariaDB official repository
# -----------------------------------------------------------

# Create directory to store repository signing keys.
echo "Creating keyring directory..."
mkdir -p /etc/apt/keyrings

# Download MariaDB's official signing key.
echo "Downloading MariaDB GPG key..."
curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp \
  -o /etc/apt/keyrings/mariadb-keyring.pgp

# Set proper read permissions for apt to use the key.
chmod 644 /etc/apt/keyrings/mariadb-keyring.pgp

# Create a new MariaDB repository definition file.
echo "Adding MariaDB repository..."
cat <<EOF > /etc/apt/sources.list.d/mariadb.sources
X-Repolib-Name: MariaDB
Types: deb
URIs: https://deb.mariadb.org/11.8/ubuntu
Suites: $(lsb_release -cs)
Components: main main/debug
Signed-By: /etc/apt/keyrings/mariadb-keyring.pgp
EOF

# Update package index again to include the new MariaDB repository.
apt update -y -qq

# -----------------------------------------------------------
# STEP 4: Install MariaDB Server
# -----------------------------------------------------------

# Install the MariaDB server package from the newly added repository.
echo "Installing MariaDB server..."
apt install -y mariadb-server

# -----------------------------------------------------------
# STEP 5: Enable and Start MariaDB Service
# -----------------------------------------------------------

# Enable MariaDB so it starts automatically on boot.
echo "Enabling and starting MariaDB service..."
systemctl enable mariadb

# Start MariaDB service immediately.
systemctl start mariadb

# Verify that MariaDB client is installed and accessible.
echo "Checking MariaDB version..."
mariadb --version

echo "MariaDB installation complete."

# -----------------------------------------------------------
# STEP 6: Harden MariaDB (Replacement for mysql_secure_installation)
# -----------------------------------------------------------

echo "Hardening MariaDB (SQL-based)..."

# Ensure MariaDB service is running before executing SQL.
systemctl start mariadb || true

# Execute security-related SQL commands automatically.
mariadb -u root <<SQL

-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PW}';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disable remote root login
DELETE FROM mysql.user 
WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Apply changes
FLUSH PRIVILEGES;

SQL

echo "MariaDB hardening complete."

# -----------------------------------------------------------
# STEP 7: Create Unprivileged Linux User
# -----------------------------------------------------------

# Create a dedicated Linux user that will own the ETL files
# and execute the database loading process. Running ETL as a
# non-root user follows the principle of least privilege and
# prevents accidental system-level changes.

echo "Creating Linux user (unprivileged)..."

# Check whether the user already exists to avoid script failure
# if the script is re-run on the same instance.
if id "${LINUX_USER}" >/dev/null 2>&1; then
  echo "User ${LINUX_USER} already exists (ok)."
else
  # Create the user with a home directory and Bash shell.
  useradd -m -s /bin/bash "${LINUX_USER}"
  echo "Created user ${LINUX_USER}."
fi

# Ensure the home directory exists and is owned by the user.
# This directory will store CSV files and ETL scripts.
mkdir -p "${USER_HOME}"
chown -R "${LINUX_USER}:${LINUX_USER}" "${USER_HOME}"

# -----------------------------------------------------------
# STEP 8: Create Matching MariaDB User and Credentials
# -----------------------------------------------------------

# Create a MariaDB user that corresponds to the Linux user.
# This allows the ETL process to authenticate with the database
# without using the root account.

echo "Creating MariaDB user matching Linux user..."

# Execute SQL commands to create the database and user.
# The user is granted only the privileges required to build
# schema objects and perform ETL operations.

mariadb -u root -p"${ROOT_PW}" <<SQL

CREATE USER IF NOT EXISTS '${LINUX_USER}'@'localhost'
IDENTIFIED BY '${DB_PASS}';

GRANT SELECT, INSERT, UPDATE, DELETE, ALTER, INDEX, CREATE, DROP, REFERENCES,
      CREATE VIEW, SHOW VIEW, TRIGGER
ON ${DB_NAME}.* TO '${LINUX_USER}'@'localhost';

FLUSH PRIVILEGES;
SQL

# -----------------------------------------------------------
# STEP 9: Download and Extract Source Data
# -----------------------------------------------------------

# Download the dataset ZIP file provided for the ETL process.
# The download is executed as the unprivileged user so the
# extracted files are automatically owned by that user.

echo "Downloading ZIP as ${LINUX_USER}..."
sudo -u "${LINUX_USER}" bash -lc "wget -O '${ZIP_PATH}' '${ZIP_URL}'"

# Verify that the file downloaded successfully and is not empty.
# If the file is missing or zero bytes, the ETL cannot proceed.

echo "Verifying download..."
if [ ! -s "${ZIP_PATH}" ]; then
  echo "ERROR: ZIP download failed or file is empty: ${ZIP_PATH}"
  ls -l "${USER_HOME}" || true
  exit 1
fi

ls -l "${ZIP_PATH}"

# Extract the CSV files from the ZIP archive into the user's home
# directory where the ETL process will access them.

echo "Unzipping CSVs into ${USER_HOME} as ${LINUX_USER}..."
sudo -u "${LINUX_USER}" bash -lc "unzip -o '${ZIP_PATH}' -d '${USER_HOME}'"

# Confirm that CSV files were successfully extracted.

echo "Verifying CSV extraction..."
CSV_COUNT="$(find "${USER_HOME}" -maxdepth 1 -type f -name '*.csv' | wc -l | tr -d ' ')"
echo "CSV files found: ${CSV_COUNT}"
ls -l "${USER_HOME}" || true

# Stop execution if no CSV files were extracted.
if [ "${CSV_COUNT}" -lt 1 ]; then
  echo "ERROR: No CSV files found after unzip. ETL cannot continue."
  exit 1
fi

# -----------------------------------------------------------
# STEP 10: Generate ETL SQL Script
# -----------------------------------------------------------

# Create an SQL script that performs the full ETL workflow.
# This includes:
#   1. Creating the relational schema
#   2. Loading raw CSV data into staging tables
#   3. Transforming and inserting data into normalized tables
#   4. Cleaning up staging tables

echo "Generating ETL SQL: ${ETL_PATH}..."

# Define expected CSV file locations. Linux filenames are
# case-sensitive, so exact matches are required.

CUSTOMERS_CSV="${USER_HOME}/customers.csv"
ORDERS_CSV="${USER_HOME}/orders.csv"
ORDERLINES_CSV="${USER_HOME}/orderlines.csv"
PRODUCTS_CSV="${USER_HOME}/products.csv"

# Verify expected CSV files exist before ETL execution.

for f in "${CUSTOMERS_CSV}" "${ORDERS_CSV}" "${ORDERLINES_CSV}" "${PRODUCTS_CSV}"; do
  if [ ! -f "$f" ]; then
    echo "WARNING: Expected CSV not found: $f"
  fi
done

# Generate the ETL SQL script dynamically.
# The SQL file will later be executed by the database user.

cat <<EOF > "${ETL_PATH}"
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME};
USE ${DB_NAME};

-- ----------------------------
-- Final schema (as required)
-- ----------------------------
CREATE TABLE City (
  zip DECIMAL(5,0) ZEROFILL PRIMARY KEY,
  city VARCHAR(32),
  state VARCHAR(4)
);

CREATE TABLE Customer (
  id SERIAL PRIMARY KEY,
  firstName VARCHAR(32),
  lastName VARCHAR(30),
  email VARCHAR(128),
  address1 VARCHAR(100),
  address2 VARCHAR(50),
  phone VARCHAR(32),
  birthdate DATE,
  zip DECIMAL(5,0) ZEROFILL,
  CONSTRAINT fk_customer_city FOREIGN KEY (zip) REFERENCES City(zip)
);

CREATE TABLE Product (
  id SERIAL PRIMARY KEY,
  name VARCHAR(128),
  currentPrice DECIMAL(6,2),
  availableQuantity INT
);

-- SERIAL in MariaDB => BIGINT UNSIGNED, so FK uses BIGINT UNSIGNED
CREATE TABLE \`Order\` (
  id SERIAL PRIMARY KEY,
  datePlaced DATE,
  dateShipped DATE,
  customer_id BIGINT UNSIGNED,
  CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES Customer(id)
);

CREATE TABLE Orderline (
  order_id BIGINT UNSIGNED,
  product_id BIGINT UNSIGNED,
  quantity INT,
  PRIMARY KEY (order_id, product_id),
  CONSTRAINT fk_ol_order FOREIGN KEY (order_id) REFERENCES \`Order\`(id),
  CONSTRAINT fk_ol_product FOREIGN KEY (product_id) REFERENCES Product(id)
);

CREATE TABLE PriceHistory (
  id SERIAL PRIMARY KEY,
  oldPrice DECIMAL(6,2),
  newPrice DECIMAL(6,2),
  ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  product_id BIGINT UNSIGNED,
  CONSTRAINT fk_ph_product FOREIGN KEY (product_id) REFERENCES Product(id)
);

-- ----------------------------
-- Staging tables (match CSVs)
-- ----------------------------
CREATE TABLE stg_customers (
  CustomerID_txt VARCHAR(50),
  FirstName VARCHAR(32),
  LastName VARCHAR(30),
  City VARCHAR(32),
  State VARCHAR(4),
  Zip_txt VARCHAR(50),
  address1 VARCHAR(100),
  address2 VARCHAR(50),
  email VARCHAR(128),
  birthdate_txt VARCHAR(50)
);

CREATE TABLE stg_orders (
  OrderID_txt VARCHAR(50),
  CustomerID_txt VARCHAR(50),
  OrderedDate_txt VARCHAR(50),
  ShippedDate_txt VARCHAR(50)
);

CREATE TABLE stg_orderlines (
  OrderID_txt VARCHAR(50),
  ProductID_txt VARCHAR(50)
);

CREATE TABLE stg_products (
  ID_txt VARCHAR(50),
  Name VARCHAR(128),
  Price_txt VARCHAR(50),
  QuantityOnHand_txt VARCHAR(50)
);

-- ----------------------------
-- Load CSVs (LOCAL reads from user's home directory)
-- ----------------------------
LOAD DATA LOCAL INFILE '${CUSTOMERS_CSV}'
INTO TABLE stg_customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(CustomerID_txt, FirstName, LastName, City, State, Zip_txt, address1, address2, email, birthdate_txt);

LOAD DATA LOCAL INFILE '${ORDERS_CSV}'
INTO TABLE stg_orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(OrderID_txt, CustomerID_txt, OrderedDate_txt, ShippedDate_txt);

LOAD DATA LOCAL INFILE '${ORDERLINES_CSV}'
INTO TABLE stg_orderlines
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(OrderID_txt, ProductID_txt);

LOAD DATA LOCAL INFILE '${PRODUCTS_CSV}'
INTO TABLE stg_products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(ID_txt, Name, Price_txt, QuantityOnHand_txt);

-- ----------------------------
-- Transform + insert into final tables
-- City derived from Customers.csv
-- ----------------------------
INSERT INTO City (zip, city, state)
SELECT DISTINCT
  CAST(NULLIF(Zip_txt,'') AS DECIMAL(5,0)),
  NULLIF(City,''),
  NULLIF(State,'')
FROM stg_customers
WHERE NULLIF(Zip_txt,'') IS NOT NULL;

INSERT INTO Customer (id, firstName, lastName, email, address1, address2, phone, birthdate, zip)
SELECT
  CAST(NULLIF(CustomerID_txt,'') AS UNSIGNED),
  NULLIF(FirstName,''),
  NULLIF(LastName,''),
  NULLIF(email,''),
  NULLIF(address1,''),
  NULLIF(address2,''),
  NULL, -- phone not provided in Customers.csv
  CASE
    WHEN birthdate_txt IS NULL OR birthdate_txt = '' OR birthdate_txt = '0000-00-00' THEN NULL
    WHEN birthdate_txt LIKE '%/%' THEN STR_TO_DATE(birthdate_txt, '%m/%d/%Y')
    ELSE STR_TO_DATE(birthdate_txt, '%Y-%m-%d')
  END,
  CAST(NULLIF(Zip_txt,'') AS DECIMAL(5,0))
FROM stg_customers;

INSERT INTO Product (id, name, currentPrice, availableQuantity)
SELECT
  CAST(NULLIF(ID_txt,'') AS UNSIGNED),
  NULLIF(Name,''),
  CAST(NULLIF(REPLACE(REPLACE(Price_txt,'$',''),',',''),'') AS DECIMAL(6,2)),
  CAST(NULLIF(QuantityOnHand_txt,'') AS SIGNED)
FROM stg_products;

INSERT INTO \`Order\` (id, datePlaced, dateShipped, customer_id)
SELECT
  CAST(NULLIF(OrderID_txt,'') AS UNSIGNED),

  CASE
    WHEN OrderedDate_txt IS NULL THEN NULL
    WHEN LOWER(TRIM(OrderedDate_txt)) IN ('', 'cancelled', 'canceled', 'null', 'n/a', 'na', 'none') THEN NULL
    WHEN TRIM(OrderedDate_txt) LIKE '%:%'
      THEN DATE(STR_TO_DATE(TRIM(OrderedDate_txt), '%Y-%m-%d %H:%i:%s'))
    ELSE STR_TO_DATE(TRIM(OrderedDate_txt), '%Y-%m-%d')
  END,

  CASE
    WHEN ShippedDate_txt IS NULL THEN NULL
    WHEN LOWER(TRIM(ShippedDate_txt)) IN ('', 'cancelled', 'canceled', 'null', 'n/a', 'na', 'none') THEN NULL
    WHEN TRIM(ShippedDate_txt) LIKE '%:%'
      THEN DATE(STR_TO_DATE(TRIM(ShippedDate_txt), '%Y-%m-%d %H:%i:%s'))
    ELSE STR_TO_DATE(TRIM(ShippedDate_txt), '%Y-%m-%d')
  END,

  CAST(NULLIF(CustomerID_txt,'') AS UNSIGNED)
FROM stg_orders;

-- quantity is not in the file; derive it by counting duplicate pairs
INSERT INTO Orderline (order_id, product_id, quantity)
SELECT
  CAST(NULLIF(OrderID_txt,'') AS UNSIGNED),
  CAST(NULLIF(ProductID_txt,'') AS UNSIGNED),
  COUNT(*) AS quantity
FROM stg_orderlines
WHERE NULLIF(OrderID_txt,'') IS NOT NULL
  AND NULLIF(ProductID_txt,'') IS NOT NULL
GROUP BY OrderID_txt, ProductID_txt;

-- PriceHistory: table required, but no source file provided; leaving empty.

DROP TABLE stg_customers;
DROP TABLE stg_orders;
DROP TABLE stg_orderlines;
DROP TABLE stg_products;
EOF

# Ensure the ETL script is owned by the ETL user and secured.
chown "${LINUX_USER}:${LINUX_USER}" "${ETL_PATH}"
chmod 600 "${ETL_PATH}"

echo "ETL SQL generated at ${ETL_PATH}..."
ls -l "${ETL_PATH}"

# -----------------------------------------------------------
# STEP 11: Generate views.sql (View + Materialized View + Triggers)
# -----------------------------------------------------------

echo "Generating Views SQL: ${VIEWS_PATH}..."

cat <<EOF > "${VIEWS_PATH}"
-- Master script for Denormalization milestone
-- Option B (Best practice): treat etl.sql as an imported library
SOURCE ${ETL_PATH};

USE ${DB_NAME};

-- -----------------------------------------------------------
-- 1) View: v_ProductBuyers
-- Requirements:
--  - include ALL products (LEFT JOIN)
--  - customers = "ID First Last" comma-separated
--  - DISTINCT to avoid duplicates
--  - ORDER BY customer id inside GROUP_CONCAT
--  - final output sorted by productID
-- -----------------------------------------------------------

CREATE OR REPLACE VIEW v_ProductBuyers AS
SELECT
  p.id AS productID,
  p.name AS productName,
  IFNULL(
    GROUP_CONCAT(
      DISTINCT CONCAT(c.id, ' ', c.firstName, ' ', c.lastName)
      ORDER BY c.id
      SEPARATOR ', '
    ),
    ''
  ) AS customers
FROM Product p
LEFT JOIN Orderline ol
  ON p.id = ol.product_id
LEFT JOIN \`Order\` o
  ON ol.order_id = o.id
LEFT JOIN Customer c
  ON o.customer_id = c.id
GROUP BY p.id, p.name
ORDER BY p.id;

-- -----------------------------------------------------------
-- 2) Materialized View Simulation: mv_ProductBuyers (physical table)
-- -----------------------------------------------------------

DROP TABLE IF EXISTS mv_ProductBuyers;

CREATE TABLE mv_ProductBuyers AS
SELECT * FROM v_ProductBuyers;

-- Optimization: add standard INDEX (not PRIMARY KEY) on productID
CREATE INDEX idx_mv_ProductBuyers_productID ON mv_ProductBuyers(productID);

-- -----------------------------------------------------------
-- 3) Triggers: Eager Updates for mv_ProductBuyers
-- Only update the affected product row by recalculating GROUP_CONCAT
-- -----------------------------------------------------------

DROP TRIGGER IF EXISTS trg_orderline_after_insert_mvbuyers;
DELIMITER //
CREATE TRIGGER trg_orderline_after_insert_mvbuyers
AFTER INSERT ON Orderline
FOR EACH ROW
BEGIN
  UPDATE mv_ProductBuyers mv
  SET mv.customers = (
    SELECT IFNULL(
      GROUP_CONCAT(
        DISTINCT CONCAT(c.id, ' ', c.firstName, ' ', c.lastName)
        ORDER BY c.id
        SEPARATOR ', '
      ),
      ''
    )
    FROM Orderline ol
    JOIN \`Order\` o ON ol.order_id = o.id
    JOIN Customer c ON o.customer_id = c.id
    WHERE ol.product_id = NEW.product_id
  )
  WHERE mv.productID = NEW.product_id;
END//
DELIMITER ;

DROP TRIGGER IF EXISTS trg_orderline_after_delete_mvbuyers;
DELIMITER //
CREATE TRIGGER trg_orderline_after_delete_mvbuyers
AFTER DELETE ON Orderline
FOR EACH ROW
BEGIN
  UPDATE mv_ProductBuyers mv
  SET mv.customers = (
    SELECT IFNULL(
      GROUP_CONCAT(
        DISTINCT CONCAT(c.id, ' ', c.firstName, ' ', c.lastName)
        ORDER BY c.id
        SEPARATOR ', '
      ),
      ''
    )
    FROM Orderline ol
    JOIN \`Order\` o ON ol.order_id = o.id
    JOIN Customer c ON o.customer_id = c.id
    WHERE ol.product_id = OLD.product_id
  )
  WHERE mv.productID = OLD.product_id;
END//
DELIMITER ;

-- -----------------------------------------------------------
-- 4) Trigger: PriceHistory logging on Product price changes only
-- -----------------------------------------------------------

DROP TRIGGER IF EXISTS trg_product_pricehistory;
DELIMITER //
CREATE TRIGGER trg_product_pricehistory
AFTER UPDATE ON Product
FOR EACH ROW
BEGIN
  IF OLD.currentPrice <> NEW.currentPrice THEN
    INSERT INTO PriceHistory (oldPrice, newPrice, product_id)
    VALUES (OLD.currentPrice, NEW.currentPrice, OLD.id);
  END IF;
END//
DELIMITER ;

EOF

chown "${LINUX_USER}:${LINUX_USER}" "${VIEWS_PATH}"
chmod 600 "${VIEWS_PATH}"

echo "Views SQL generated at ${VIEWS_PATH}..."
ls -l "${VIEWS_PATH}"

# -----------------------------------------------------------
# STEP 12: Execute ETL Process
# -----------------------------------------------------------

# Run the ETL SQL script using the unprivileged database user.
# The --local-infile option allows the MariaDB client to read
# CSV files from the user's home directory and stream them to
# the server during LOAD DATA LOCAL INFILE operations.

echo "Executing ETL as Linux user: ${LINUX_USER}..."

sudo -u "${LINUX_USER}" bash -lc \
"mariadb --local-infile=1 -u '${LINUX_USER}' -p'${DB_PASS}' < '${VIEWS_PATH}'"

# Verify the ETL completed successfully by listing tables
# created in the target database.

echo "ETL complete. Verifying tables exist in ${DB_NAME}..."
mariadb -u root -p"${ROOT_PW}" -e "SHOW TABLES FROM ${DB_NAME};"

# Final message directing administrators where to check logs
# if the script encountered any failures.

echo "DONE. If something failed, SSH in and run: cat /var/log/user-data.log..."