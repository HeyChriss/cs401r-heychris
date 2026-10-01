## Data Contract: processed/customers

### Producer
Team / process: Glue ETL job `northstar-dev-transform`

The job reads the crawler-registered table `northstar_dev.customers`, casts types, imputes nulls, drops rows with no `customer_id`, and keeps one row per `transaction_id`. It writes Parquet to `s3://northstar-dev-data-{account-id}/processed/customers/`.

### Consumers
- Feature engineering job `northstar-dev-feature-engineer`
- (Future) Direct model training in Lab 3

### Grain
One row per transaction. A customer appears on many rows. Collapsing to one row per customer is the feature engineering job's responsibility, not this dataset's.

### Schema
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| transaction_id | string | no | Natural key. Form `TXN-` plus 12 alphanumeric characters. Unique in this dataset. |
| customer_id | string | no | Customer key. Form `CUST-` plus 8 digits. Repeats across rows by design. |
| purchase_date | date | no | Calendar date of the purchase, ISO 8601 (`yyyy-MM-dd`). Range 2025-04-01 through 2026-06-30 inclusive. |
| order_value | double | no | Gross order amount in USD. |
| num_items | int | no | Number of line items in the order. |
| payment_method | string | no | One of `credit_card`, `debit_card`, `gift_card`, `cash`. |
| channel | string | no | `store` or `online`. |
| store_id | string | no | `STORE-` plus 3 digits, or `ONLINE`. |
| product_category | string | no | One of Apparel, Beauty, Electronics, Footwear, Grocery, Home, Outdoor, Toys. Missing raw values are the sentinel `unknown`. |

Parquet physical types: `purchase_date` is a date, `order_value` is a double, `num_items` is a 32-bit integer, and the other columns are strings.

### Quality Guarantees
- `customer_id` is never null, and every value matches `CUST-` followed by 8 digits.
- No duplicate `transaction_id` rows. A `customer_id` repeating across rows is expected, not a defect. The current publish has 157,627 rows and 9,999 distinct customers.
- `order_value` is in the closed range [15.00, 620.00] USD. `num_items` is an integer in the closed range [1, 9]. Neither column contains nulls; the producer fills numeric nulls with that column's median before writing.
- `purchase_date` is a valid ISO 8601 calendar date, with no nulls, and every value falls on or between 2025-04-01 and 2026-06-30.
- `payment_method`, `channel`, `store_id`, and `product_category` are never null. A missing string is written as `unknown` rather than left empty.

### SLA
- Data is available in `processed/customers/` within 2 hours of landing in `raw/customers/`.

### Versioning
- Schema changes require a new S3 prefix (e.g., `processed/customers/v2/`).
- Breaking changes require consumer notification 5 business days in advance.
