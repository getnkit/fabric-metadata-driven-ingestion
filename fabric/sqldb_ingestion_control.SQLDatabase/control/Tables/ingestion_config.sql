CREATE TABLE [control].[ingestion_config] (
    [ingestion_config_id] INT             IDENTITY (1, 1) NOT NULL,
    [source_system]       NVARCHAR (100)  NOT NULL,
    [source_conn_ref]     NVARCHAR (100)  NOT NULL,
    [source_schema]       NVARCHAR (128)  NULL,
    [source_object]       NVARCHAR (128)  NOT NULL,
    [source_path]         NVARCHAR (1000) NULL,
    [ingestion_pattern]   VARCHAR (20)    NOT NULL,
    [source_options]      NVARCHAR (MAX)  NULL,
    [copy_options]        NVARCHAR (MAX)  NULL,
    [landing_path]        NVARCHAR (1000) NULL,
    [target_conn_ref]     NVARCHAR (100)  NOT NULL,
    [target_schema]       NVARCHAR (128)  NOT NULL,
    [target_table]        NVARCHAR (128)  NOT NULL,
    [load_strategy]       VARCHAR (20)    NOT NULL,
    [watermark_field]     NVARCHAR (128)  NULL,
    [is_active]           BIT             CONSTRAINT [DF_ingestion_config_is_active] DEFAULT ((1)) NOT NULL,
    [created_at]          DATETIME2 (3)   CONSTRAINT [DF_ingestion_config_created_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [updated_at]          DATETIME2 (3)   CONSTRAINT [DF_ingestion_config_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [file_format]         VARCHAR (30)    NULL,
    CONSTRAINT [PK_ingestion_config] PRIMARY KEY CLUSTERED ([ingestion_config_id] ASC),
    CONSTRAINT [CK_ingestion_config_copy_options_json] CHECK ([copy_options] IS NULL OR isjson([copy_options])=(1)),
    CONSTRAINT [CK_ingestion_config_file_format] CHECK ([ingestion_pattern]='FILE' AND ([file_format]='JSON' OR [file_format]='PARQUET' OR [file_format]='DELIMITED_TEXT') OR ([ingestion_pattern]='API' OR [ingestion_pattern]='DATABASE') AND [file_format] IS NULL),
    CONSTRAINT [CK_ingestion_config_landing_path] CHECK ([ingestion_pattern]<>'FILE' OR [landing_path] IS NOT NULL),
    CONSTRAINT [CK_ingestion_config_pattern] CHECK ([ingestion_pattern]='API' OR [ingestion_pattern]='FILE' OR [ingestion_pattern]='DATABASE'),
    CONSTRAINT [CK_ingestion_config_source_options_json] CHECK ([source_options] IS NULL OR isjson([source_options])=(1)),
    CONSTRAINT [CK_ingestion_config_source_path] CHECK ([ingestion_pattern]<>'FILE' OR [source_path] IS NOT NULL),
    CONSTRAINT [CK_ingestion_config_source_schema] CHECK ([ingestion_pattern]<>'DATABASE' OR [source_schema] IS NOT NULL),
    CONSTRAINT [CK_ingestion_config_strategy] CHECK ([load_strategy]='INCREMENTAL' OR [load_strategy]='FULL'),
    CONSTRAINT [CK_ingestion_config_watermark] CHECK ([load_strategy]='FULL' AND [watermark_field] IS NULL OR [load_strategy]='INCREMENTAL' AND [watermark_field] IS NOT NULL),
    CONSTRAINT [FK_ingestion_config_source_connection] FOREIGN KEY ([source_conn_ref]) REFERENCES [control].[connection_settings] ([connection_ref]),
    CONSTRAINT [FK_ingestion_config_target_connection] FOREIGN KEY ([target_conn_ref]) REFERENCES [control].[connection_settings] ([connection_ref]),
    CONSTRAINT [UQ_ingestion_config_source] UNIQUE NONCLUSTERED ([source_system] ASC, [source_schema] ASC, [source_object] ASC)
);


GO

