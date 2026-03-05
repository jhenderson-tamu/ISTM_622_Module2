# AI Prompt / Result Handbook

## ISTM 622 -- Denormalization & Materialized Views

Author: Jeremy Henderson\
Generated: 2026-03-05 04:32:45

------------------------------------------------------------------------

# Overview

This handbook summarizes prompts and results used during development of
the ISTM 622 Denormalization milestone.

------------------------------------------------------------------------

## Key Database Objects

  -----------------------------------------------------------------------
  Object                              Purpose
  ----------------------------------- -----------------------------------
  v_ProductBuyers                     Logical view listing customers who
                                      purchased products

  mv_ProductBuyers                    Materialized view (table snapshot)
                                      for fast lookup

  PriceHistory Trigger                Logs product price changes

  Orderline Triggers                  Maintain materialized view
                                      consistency
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## Example View

``` sql
CREATE OR REPLACE VIEW v_ProductBuyers AS
SELECT
  p.id AS productID,
  p.name AS productName,
  IFNULL(
    GROUP_CONCAT(
      DISTINCT CONCAT(c.id,' ',c.firstName,' ',c.lastName)
      ORDER BY c.id
      SEPARATOR ', '
    ),
    ''
  ) AS customers
FROM Product p
LEFT JOIN Orderline ol ON p.id = ol.product_id
LEFT JOIN `Order` o ON ol.order_id = o.id
LEFT JOIN Customer c ON o.customer_id = c.id
GROUP BY p.id, p.name
ORDER BY p.id;
```

------------------------------------------------------------------------

## Materialized View

``` sql
DROP TABLE IF EXISTS mv_ProductBuyers;

CREATE TABLE mv_ProductBuyers AS
SELECT * FROM v_ProductBuyers;

CREATE INDEX idx_mv_productID
ON mv_ProductBuyers(productID);
```

------------------------------------------------------------------------

## Verification Commands

``` sql
SHOW CREATE VIEW v_ProductBuyers;
SHOW CREATE TABLE mv_ProductBuyers;
SELECT * FROM mv_ProductBuyers LIMIT 5;
```
