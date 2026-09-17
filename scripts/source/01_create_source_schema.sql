/*
    01_create_source_schema.sql
    Target: Azure SQL Database (mock operational source)
    Purpose: Create a small but realistic e-commerce OLTP source model.

    WARNING:
    - This script DROPS the project tables if they already exist.
    - Run only against the mock/project database, never against a real system.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('crm') IS NULL EXEC('CREATE SCHEMA crm');
IF SCHEMA_ID('partner') IS NULL EXEC('CREATE SCHEMA partner');
IF SCHEMA_ID('catalog') IS NULL EXEC('CREATE SCHEMA catalog');
IF SCHEMA_ID('sales') IS NULL EXEC('CREATE SCHEMA sales');
GO

/* Drop in child-to-parent order so FK dependencies do not block the reset. */
IF OBJECT_ID('sales.order_items', 'U') IS NOT NULL DROP TABLE sales.order_items;
IF OBJECT_ID('sales.orders', 'U') IS NOT NULL DROP TABLE sales.orders;
IF OBJECT_ID('catalog.products', 'U') IS NOT NULL DROP TABLE catalog.products;
IF OBJECT_ID('catalog.product_categories', 'U') IS NOT NULL DROP TABLE catalog.product_categories;
IF OBJECT_ID('partner.merchants', 'U') IS NOT NULL DROP TABLE partner.merchants;
IF OBJECT_ID('crm.customers', 'U') IS NOT NULL DROP TABLE crm.customers;
GO

CREATE TABLE crm.customers
(
    customer_id      INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_customers PRIMARY KEY,
    first_name       NVARCHAR(100) NOT NULL,
    last_name        NVARCHAR(100) NOT NULL,
    email            NVARCHAR(255) NOT NULL,
    phone_number     NVARCHAR(30) NULL,
    customer_status  VARCHAR(20) NOT NULL,
    created_at       DATETIME2(3) NOT NULL,
    updated_at       DATETIME2(3) NOT NULL,

    CONSTRAINT UQ_customers_email UNIQUE (email),
    CONSTRAINT CK_customers_status
        CHECK (customer_status IN ('ACTIVE','INACTIVE','SUSPENDED')),
    CONSTRAINT CK_customers_timestamp
        CHECK (updated_at >= created_at)
);
GO

CREATE INDEX IX_customers_updated_at
    ON crm.customers(updated_at, customer_id);
GO

CREATE TABLE partner.merchants
(
    merchant_id      INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_merchants PRIMARY KEY,
    merchant_code    VARCHAR(30) NOT NULL,
    merchant_name    NVARCHAR(200) NOT NULL,
    merchant_status  VARCHAR(20) NOT NULL,
    created_at       DATETIME2(3) NOT NULL,
    updated_at       DATETIME2(3) NOT NULL,

    CONSTRAINT UQ_merchants_code UNIQUE (merchant_code),
    CONSTRAINT CK_merchants_status
        CHECK (merchant_status IN ('ACTIVE','INACTIVE')),
    CONSTRAINT CK_merchants_timestamp
        CHECK (updated_at >= created_at)
);
GO

CREATE INDEX IX_merchants_updated_at
    ON partner.merchants(updated_at, merchant_id);
GO

CREATE TABLE catalog.product_categories
(
    category_id      INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_product_categories PRIMARY KEY,
    category_code    VARCHAR(30) NOT NULL,
    category_name    NVARCHAR(150) NOT NULL,
    is_active        BIT NOT NULL
        CONSTRAINT DF_product_categories_is_active DEFAULT (1),
    created_at       DATETIME2(3) NOT NULL,

    CONSTRAINT UQ_product_categories_code UNIQUE (category_code)
);
GO

CREATE TABLE catalog.products
(
    product_id       INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_products PRIMARY KEY,
    sku              VARCHAR(50) NOT NULL,
    product_name     NVARCHAR(250) NOT NULL,
    category_id      INT NOT NULL,
    merchant_id      INT NOT NULL,
    unit_price       DECIMAL(12,2) NOT NULL,
    product_status   VARCHAR(20) NOT NULL,
    created_at       DATETIME2(3) NOT NULL,
    updated_at       DATETIME2(3) NOT NULL,

    CONSTRAINT UQ_products_sku UNIQUE (sku),
    CONSTRAINT FK_products_category
        FOREIGN KEY (category_id)
        REFERENCES catalog.product_categories(category_id),
    CONSTRAINT FK_products_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES partner.merchants(merchant_id),
    CONSTRAINT CK_products_price CHECK (unit_price >= 0),
    CONSTRAINT CK_products_status
        CHECK (product_status IN ('ACTIVE','INACTIVE','DISCONTINUED')),
    CONSTRAINT CK_products_timestamp
        CHECK (updated_at >= created_at)
);
GO

CREATE INDEX IX_products_updated_at
    ON catalog.products(updated_at, product_id);
GO

CREATE TABLE sales.orders
(
    order_id          BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_orders PRIMARY KEY,
    order_number      VARCHAR(40) NOT NULL,
    customer_id       INT NOT NULL,
    order_status      VARCHAR(30) NOT NULL,
    order_date        DATETIME2(3) NOT NULL,
    shipping_amount   DECIMAL(12,2) NOT NULL,
    discount_amount   DECIMAL(12,2) NOT NULL,
    order_total       DECIMAL(14,2) NOT NULL,
    created_at        DATETIME2(3) NOT NULL,
    updated_at        DATETIME2(3) NOT NULL,

    CONSTRAINT UQ_orders_order_number UNIQUE (order_number),
    CONSTRAINT FK_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES crm.customers(customer_id),
    CONSTRAINT CK_orders_status
        CHECK (order_status IN ('PENDING','PAID','PROCESSING','SHIPPED','COMPLETED','CANCELLED')),
    CONSTRAINT CK_orders_amounts
        CHECK (shipping_amount >= 0 AND discount_amount >= 0 AND order_total >= 0),
    CONSTRAINT CK_orders_timestamp
        CHECK (updated_at >= created_at)
);
GO

CREATE INDEX IX_orders_updated_at
    ON sales.orders(updated_at, order_id);
GO

CREATE INDEX IX_orders_customer
    ON sales.orders(customer_id, order_date);
GO

CREATE TABLE sales.order_items
(
    order_item_id    BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_order_items PRIMARY KEY,
    order_id         BIGINT NOT NULL,
    product_id       INT NOT NULL,
    quantity         INT NOT NULL,
    unit_price       DECIMAL(12,2) NOT NULL,
    line_amount      DECIMAL(14,2) NOT NULL,
    created_at       DATETIME2(3) NOT NULL,
    updated_at       DATETIME2(3) NOT NULL,

    CONSTRAINT FK_order_items_order
        FOREIGN KEY (order_id)
        REFERENCES sales.orders(order_id),
    CONSTRAINT FK_order_items_product
        FOREIGN KEY (product_id)
        REFERENCES catalog.products(product_id),
    CONSTRAINT CK_order_items_quantity CHECK (quantity > 0),
    CONSTRAINT CK_order_items_amounts
        CHECK (unit_price >= 0 AND line_amount >= 0),
    CONSTRAINT CK_order_items_timestamp
        CHECK (updated_at >= created_at)
);
GO

CREATE INDEX IX_order_items_updated_at
    ON sales.order_items(updated_at, order_item_id);
GO

CREATE INDEX IX_order_items_order
    ON sales.order_items(order_id, order_item_id);
GO

PRINT 'Operational e-commerce source schema created successfully.';
GO