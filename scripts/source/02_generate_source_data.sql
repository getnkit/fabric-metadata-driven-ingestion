/*
    02_generate_source_data.sql
    Target: Azure SQL Database (sql_ecommerce_db)
    Purpose: Populate the mock operational source tables with deterministic synthetic
             data for ingestion testing.

    Approximate volume:
      crm.customers                 5,000
      partner.merchants               200
      catalog.product_categories       20
      catalog.products               4,000
      sales.orders                  20,000
      sales.order_items             60,000 (3 items/order)

    Assumption:
      - updated_at is maintained by the source application.
      - updated_at is used as the watermark for all INCREMENTAL objects
        in this project.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CustomerCount INT = 5000;
DECLARE @MerchantCount INT = 200;
DECLARE @ProductCount INT = 4000;
DECLARE @OrderCount INT = 20000;
DECLARE @ItemsPerOrder INT = 3;
DECLARE @CategoryCount INT = 20;
DECLARE @BaseDate DATETIME2(3) = '2026-01-01T00:00:00.000';

BEGIN TRY
    BEGIN TRANSACTION;

    /* Reset project data in child-to-parent order. */
    DELETE FROM sales.order_items;
    DELETE FROM sales.orders;
    DELETE FROM catalog.products;
    DELETE FROM catalog.product_categories;
    DELETE FROM partner.merchants;
    DELETE FROM crm.customers;

    /*
       Reset identity seeds for readability only.
       FK generation below does not depend on these values being 1..N.
    */
    DBCC CHECKIDENT ('sales.order_items', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('sales.orders', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('catalog.products', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('catalog.product_categories', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('partner.merchants', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT ('crm.customers', RESEED, 0) WITH NO_INFOMSGS;

    /* 5,000 customers. */
    ;WITH N AS
    (
        SELECT TOP (@CustomerCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
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
    SELECT
        CONCAT(N'Customer', RIGHT(CONCAT('00000', n), 5)),
        CONCAT(N'User', RIGHT(CONCAT('00000', n), 5)),
        CONCAT('customer', RIGHT(CONCAT('00000', n), 5), '@example.com'),
        CONCAT('08', RIGHT(CONCAT('00000000', 10000000 + (n % 89999999)), 8)),
        CASE
            WHEN n % 50 = 0 THEN 'SUSPENDED'
            WHEN n % 20 = 0 THEN 'INACTIVE'
            ELSE 'ACTIVE'
        END,
        DATEADD(MINUTE, n % 1440, DATEADD(DAY, n % 210, @BaseDate)),
        DATEADD(
            HOUR,
            n % 72,
            DATEADD(MINUTE, n % 1440, DATEADD(DAY, n % 210, @BaseDate))
        )
    FROM N;

    /* 200 merchants. */
    ;WITH N AS
    (
        SELECT TOP (@MerchantCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT INTO partner.merchants
    (
        merchant_code,
        merchant_name,
        merchant_status,
        created_at,
        updated_at
    )
    SELECT
        CONCAT('MCH', RIGHT(CONCAT('0000', n), 4)),
        CONCAT(N'Merchant ', RIGHT(CONCAT('0000', n), 4)),
        CASE WHEN n % 25 = 0 THEN 'INACTIVE' ELSE 'ACTIVE' END,
        DATEADD(DAY, n % 180, @BaseDate),
        DATEADD(HOUR, n % 48, DATEADD(DAY, n % 180, @BaseDate))
    FROM N;

    /* 20 small reference categories: FULL load object. */
    INSERT INTO catalog.product_categories
    (
        category_code,
        category_name,
        is_active,
        created_at
    )
    VALUES
        ('CAT001', N'Electronics', 1, @BaseDate),
        ('CAT002', N'Computers & Accessories', 1, @BaseDate),
        ('CAT003', N'Mobile Phones', 1, @BaseDate),
        ('CAT004', N'Home Appliances', 1, @BaseDate),
        ('CAT005', N'Home & Living', 1, @BaseDate),
        ('CAT006', N'Kitchen', 1, @BaseDate),
        ('CAT007', N'Fashion - Men', 1, @BaseDate),
        ('CAT008', N'Fashion - Women', 1, @BaseDate),
        ('CAT009', N'Beauty & Personal Care', 1, @BaseDate),
        ('CAT010', N'Health & Wellness', 1, @BaseDate),
        ('CAT011', N'Sports & Outdoors', 1, @BaseDate),
        ('CAT012', N'Toys & Games', 1, @BaseDate),
        ('CAT013', N'Books & Stationery', 1, @BaseDate),
        ('CAT014', N'Automotive', 1, @BaseDate),
        ('CAT015', N'Pet Supplies', 1, @BaseDate),
        ('CAT016', N'Food & Grocery', 1, @BaseDate),
        ('CAT017', N'Baby & Kids', 1, @BaseDate),
        ('CAT018', N'Travel & Luggage', 1, @BaseDate),
        ('CAT019', N'Office Supplies', 1, @BaseDate),
        ('CAT020', N'Other', 1, @BaseDate);

    /*
       4,000 products distributed across the ACTUAL category/merchant IDs.
       We map a deterministic row number to each parent row instead of assuming
       category_id = 1..20 or merchant_id = 1..200.
    */
    ;WITH N AS
    (
        SELECT TOP (@ProductCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    Categories AS
    (
        SELECT
            category_id,
            ROW_NUMBER() OVER (ORDER BY category_id) AS rn
        FROM catalog.product_categories
    ),
    Merchants AS
    (
        SELECT
            merchant_id,
            ROW_NUMBER() OVER (ORDER BY merchant_id) AS rn
        FROM partner.merchants
    )
    INSERT INTO catalog.products
    (
        sku,
        product_name,
        category_id,
        merchant_id,
        unit_price,
        product_status,
        created_at,
        updated_at
    )
    SELECT
        CONCAT('SKU', RIGHT(CONCAT('000000', n.n), 6)),
        CONCAT(N'Product ', RIGHT(CONCAT('000000', n.n), 6)),
        c.category_id,
        m.merchant_id,
        CAST(25.00 + ((n.n * 37) % 250000) / 100.0 AS DECIMAL(12,2)),
        CASE
            WHEN n.n % 100 = 0 THEN 'DISCONTINUED'
            WHEN n.n % 40 = 0 THEN 'INACTIVE'
            ELSE 'ACTIVE'
        END,
        DATEADD(MINUTE, n.n % 1440, DATEADD(DAY, n.n % 220, @BaseDate)),
        DATEADD(
            HOUR,
            n.n % 96,
            DATEADD(MINUTE, n.n % 1440, DATEADD(DAY, n.n % 220, @BaseDate))
        )
    FROM N n
    JOIN Categories c
        ON c.rn = ((n.n - 1) % @CategoryCount) + 1
    JOIN Merchants m
        ON m.rn = ((n.n - 1) % @MerchantCount) + 1;

    /* 20,000 orders across the ACTUAL customer IDs. */
    ;WITH N AS
    (
        SELECT TOP (@OrderCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    Customers AS
    (
        SELECT
            customer_id,
            ROW_NUMBER() OVER (ORDER BY customer_id) AS rn
        FROM crm.customers
    )
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
    SELECT
        CONCAT('ORD', RIGHT(CONCAT('00000000', n.n), 8)),
        c.customer_id,
        CASE n.n % 6
            WHEN 0 THEN 'COMPLETED'
            WHEN 1 THEN 'SHIPPED'
            WHEN 2 THEN 'PROCESSING'
            WHEN 3 THEN 'PAID'
            WHEN 4 THEN 'PENDING'
            ELSE 'CANCELLED'
        END,
        DATEADD(SECOND, (n.n * 97) % 86400, DATEADD(DAY, n.n % 240, @BaseDate)),
        CAST(CASE WHEN n.n % 5 = 0 THEN 0 ELSE 40 + (n.n % 81) END AS DECIMAL(12,2)),
        CAST(CASE WHEN n.n % 7 = 0 THEN 50 + (n.n % 151) ELSE 0 END AS DECIMAL(12,2)),
        CAST(0 AS DECIMAL(14,2)),
        DATEADD(SECOND, (n.n * 97) % 86400, DATEADD(DAY, n.n % 240, @BaseDate)),
        DATEADD(
            HOUR,
            n.n % 72,
            DATEADD(SECOND, (n.n * 97) % 86400, DATEADD(DAY, n.n % 240, @BaseDate))
        )
    FROM N n
    JOIN Customers c
        ON c.rn = ((n.n - 1) % @CustomerCount) + 1;

    /*
       Exactly 3 line items/order = 60,000 rows.
       Resolve ACTUAL order/product IDs by row number; never assume IDs start at 1.
    */
    ;WITH N AS
    (
        SELECT TOP (@OrderCount * @ItemsPerOrder)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    OrderedOrders AS
    (
        SELECT
            order_id,
            created_at,
            updated_at,
            ROW_NUMBER() OVER (ORDER BY order_id) AS rn
        FROM sales.orders
    ),
    OrderedProducts AS
    (
        SELECT
            product_id,
            unit_price,
            ROW_NUMBER() OVER (ORDER BY product_id) AS rn
        FROM catalog.products
    ),
    ItemSeed AS
    (
        SELECT
            n,
            CAST(((n - 1) / @ItemsPerOrder) + 1 AS BIGINT) AS order_rn,
            ((n * 17 - 1) % @ProductCount) + 1 AS product_rn,
            ((n - 1) % 4) + 1 AS quantity
        FROM N
    )
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
        o.order_id,
        p.product_id,
        s.quantity,
        p.unit_price,
        CAST(s.quantity * p.unit_price AS DECIMAL(14,2)),
        o.created_at,
        o.updated_at
    FROM ItemSeed s
    JOIN OrderedOrders o
        ON o.rn = s.order_rn
    JOIN OrderedProducts p
        ON p.rn = s.product_rn;

    /* Derive the order total from its line items. */
    ;WITH Totals AS
    (
        SELECT
            oi.order_id,
            SUM(oi.line_amount) AS item_total
        FROM sales.order_items oi
        GROUP BY oi.order_id
    )
    UPDATE o
    SET order_total =
        CAST(
            CASE
                WHEN t.item_total + o.shipping_amount - o.discount_amount < 0 THEN 0
                ELSE t.item_total + o.shipping_amount - o.discount_amount
            END
            AS DECIMAL(14,2)
        )
    FROM sales.orders o
    JOIN Totals t
        ON t.order_id = o.order_id;

    /* Defensive validation before commit. */
    IF (SELECT COUNT(*) FROM crm.customers) <> @CustomerCount
        THROW 51001, 'Customer row-count validation failed.', 1;

    IF (SELECT COUNT(*) FROM partner.merchants) <> @MerchantCount
        THROW 51002, 'Merchant row-count validation failed.', 1;

    IF (SELECT COUNT(*) FROM catalog.product_categories) <> @CategoryCount
        THROW 51003, 'Category row-count validation failed.', 1;

    IF (SELECT COUNT(*) FROM catalog.products) <> @ProductCount
        THROW 51004, 'Product row-count validation failed.', 1;

    IF (SELECT COUNT(*) FROM sales.orders) <> @OrderCount
        THROW 51005, 'Order row-count validation failed.', 1;

    IF (SELECT COUNT(*) FROM sales.order_items) <> (@OrderCount * @ItemsPerOrder)
        THROW 51006, 'Order-item row-count validation failed.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

/* Validation summary. */
SELECT 'crm.customers' AS source_object, COUNT_BIG(*) AS row_count,
       MIN(updated_at) AS min_updated_at, MAX(updated_at) AS max_updated_at
FROM crm.customers
UNION ALL
SELECT 'partner.merchants', COUNT_BIG(*), MIN(updated_at), MAX(updated_at)
FROM partner.merchants
UNION ALL
SELECT 'catalog.product_categories', COUNT_BIG(*), NULL, NULL
FROM catalog.product_categories
UNION ALL
SELECT 'catalog.products', COUNT_BIG(*), MIN(updated_at), MAX(updated_at)
FROM catalog.products
UNION ALL
SELECT 'sales.orders', COUNT_BIG(*), MIN(updated_at), MAX(updated_at)
FROM sales.orders
UNION ALL
SELECT 'sales.order_items', COUNT_BIG(*), MIN(updated_at), MAX(updated_at)
FROM sales.order_items;
GO