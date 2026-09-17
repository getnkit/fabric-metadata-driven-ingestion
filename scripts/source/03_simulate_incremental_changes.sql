/*
    03_simulate_incremental_changes.sql
    Target: Azure SQL Database (mock operational source)
    Purpose: Create a small set of source changes AFTER an initial ingestion run.

    Use this script repeatedly during incremental testing.
    Each execution creates a fresh timestamp using SYSUTCDATETIME().
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ChangeTs DATETIME2(3) = SYSUTCDATETIME();
DECLARE @NewCustomerId INT;
DECLARE @ExistingCustomerId INT;
DECLARE @NewOrderId BIGINT;
DECLARE @Product1 INT;
DECLARE @Product2 INT;
DECLARE @Product3 INT;

/* Resolve actual existing IDs before changing data. */
SELECT TOP (1)
    @ExistingCustomerId = customer_id
FROM crm.customers
ORDER BY customer_id;

;WITH P AS
(
    SELECT TOP (3)
        product_id,
        ROW_NUMBER() OVER (ORDER BY product_id) AS rn
    FROM catalog.products
    ORDER BY product_id
)
SELECT
    @Product1 = MAX(CASE WHEN rn = 1 THEN product_id END),
    @Product2 = MAX(CASE WHEN rn = 2 THEN product_id END),
    @Product3 = MAX(CASE WHEN rn = 3 THEN product_id END)
FROM P;

IF @ExistingCustomerId IS NULL
    THROW 51101, 'No existing customer found. Run 02_generate_source_data.sql first.', 1;

IF @Product1 IS NULL OR @Product2 IS NULL OR @Product3 IS NULL
    THROW 51102, 'At least three products are required. Run 02_generate_source_data.sql first.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    /* 1) Insert a new customer. */
    INSERT INTO crm.customers
    (
        first_name,
        last_name,
        email,
        phone_number,
        customer_status,
        created_at,
        updated_at
    )
    VALUES
    (
        N'Incremental',
        N'Customer',
        CONCAT('incremental.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), '@example.com'),
        '0899999999',
        'ACTIVE',
        @ChangeTs,
        @ChangeTs
    );

    SET @NewCustomerId = CONVERT(INT, SCOPE_IDENTITY());

    /* 2) Update one actual existing customer. */
    UPDATE crm.customers
    SET
        phone_number = '0812345678',
        updated_at = @ChangeTs
    WHERE customer_id = @ExistingCustomerId;

    /* 3) Update one actual existing product. */
    UPDATE catalog.products
    SET
        unit_price = unit_price + 25.00,
        updated_at = @ChangeTs
    WHERE product_id = @Product1;

    /* 4) Create a new order for the newly-created customer. */
    INSERT INTO sales.orders
    (
        order_number,
        customer_id,
        order_status,
        order_date,
        shipping_amount,
        discount_amount,
        order_total,
        created_at,
        updated_at
    )
    VALUES
    (
        CONCAT('ORD-INC-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')),
        @NewCustomerId,
        'PAID',
        @ChangeTs,
        50.00,
        0.00,
        0.00,
        @ChangeTs,
        @ChangeTs
    );

    SET @NewOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    /* 5) Add three order-item rows using actual product IDs. */
    INSERT INTO sales.order_items
    (
        order_id,
        product_id,
        quantity,
        unit_price,
        line_amount,
        created_at,
        updated_at
    )
    SELECT
        @NewOrderId,
        p.product_id,
        x.quantity,
        p.unit_price,
        CAST(x.quantity * p.unit_price AS DECIMAL(14,2)),
        @ChangeTs,
        @ChangeTs
    FROM
    (
        VALUES
            (@Product1, 1),
            (@Product2, 2),
            (@Product3, 1)
    ) x(product_id, quantity)
    JOIN catalog.products p
        ON p.product_id = x.product_id;

    UPDATE o
    SET
        order_total = t.item_total + o.shipping_amount - o.discount_amount,
        updated_at = @ChangeTs
    FROM sales.orders o
    CROSS APPLY
    (
        SELECT SUM(oi.line_amount) AS item_total
        FROM sales.order_items oi
        WHERE oi.order_id = o.order_id
    ) t
    WHERE o.order_id = @NewOrderId;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    @ChangeTs AS change_timestamp_utc,
    @NewCustomerId AS new_customer_id,
    @ExistingCustomerId AS updated_customer_id,
    @Product1 AS updated_product_id,
    @NewOrderId AS new_order_id;

/* Quick proof of the new watermark range. */
SELECT 'crm.customers' AS source_object, MAX(updated_at) AS max_updated_at FROM crm.customers
UNION ALL
SELECT 'catalog.products', MAX(updated_at) FROM catalog.products
UNION ALL
SELECT 'sales.orders', MAX(updated_at) FROM sales.orders
UNION ALL
SELECT 'sales.order_items', MAX(updated_at) FROM sales.order_items;
GO