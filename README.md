# ISTM 622 -- Denormalization & Materialized Views

Author: Jeremy Henderson\
Generated: 2026-03-05 04:32:45

------------------------------------------------------------------------

## Project Overview

This project implements database denormalization techniques to improve
query performance for a retail application.

Key features include:

-   SQL views for simplified queries
-   Materialized views for fast lookups
-   Triggers for automatic synchronization
-   EC2 infrastructure automation

------------------------------------------------------------------------

## Repository Structure

    /docs
        AI-Prompt-Handbook.md
        AI-Prompt-Log.md
        AI-Prompt-Notebook.md
    README.md

------------------------------------------------------------------------

## Database Objects

-   v_ProductBuyers
-   mv_ProductBuyers
-   PriceHistory trigger
-   Orderline triggers

------------------------------------------------------------------------

## Verification

Run the following queries to validate the system:

``` sql
SHOW CREATE VIEW v_ProductBuyers;
SHOW CREATE TABLE mv_ProductBuyers;
SHOW TRIGGERS;
SELECT * FROM mv_ProductBuyers LIMIT 5;
```
