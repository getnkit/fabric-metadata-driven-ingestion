CREATE TABLE [control].[ingestion_config] (
    [ingestion_config_id] INT            IDENTITY (1, 1) NOT NULL,
    [source_system]       NVARCHAR (100) NOT NULL,
    [source_schema]       NVARCHAR (128) NOT NULL,
    [source_object]       NVARCHAR (128) NOT NULL,
    [target_folder]       NVARCHAR (500) NOT NULL,
    [target_schema]       NVARCHAR (128) NOT NULL,
    [target_table]        NVARCHAR (128) NOT NULL,
    [load_strategy]       VARCHAR (20)   NOT NULL,
    [watermark_field]     NVARCHAR (128) NULL,
    [is_active]           BIT            CONSTRAINT [DF_ingestion_config_is_active] DEFAULT ((1)) NOT NULL,
    [created_at]          DATETIME2 (3)  CONSTRAINT [DF_ingestion_config_created_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [updated_at]          DATETIME2 (3)  CONSTRAINT [DF_ingestion_config_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_ingestion_config] PRIMARY KEY CLUSTERED ([ingestion_config_id] ASC),
    CONSTRAINT [CK_ingestion_config_strategy] CHECK ([load_strategy]='INCREMENTAL' OR [load_strategy]='FULL'),
    CONSTRAINT [CK_ingestion_config_watermark] CHECK ([load_strategy]='FULL' AND [watermark_field] IS NULL OR [load_strategy]='INCREMENTAL' AND [watermark_field] IS NOT NULL),
    CONSTRAINT [UQ_ingestion_config_source] UNIQUE NONCLUSTERED ([source_system] ASC, [source_schema] ASC, [source_object] ASC)
);


GO

