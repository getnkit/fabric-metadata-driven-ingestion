CREATE TABLE [control].[file_ingestion_config] (
    [ingestion_config_id]  INT            NOT NULL,
    [source_folder]        NVARCHAR (500) NOT NULL,
    [file_name_pattern]    NVARCHAR (255) NOT NULL,
    [file_format]          VARCHAR (20)   NOT NULL,
    [delimiter]            NVARCHAR (10)  NULL,
    [has_header]           BIT            NULL,
    [encoding]             VARCHAR (30)   NULL,
    [expected_schema_json] NVARCHAR (MAX) NOT NULL,
    [quarantine_folder]    NVARCHAR (500) NOT NULL,
    [created_at]           DATETIME2 (3)  CONSTRAINT [DF_file_ingestion_config_created_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [updated_at]           DATETIME2 (3)  CONSTRAINT [DF_file_ingestion_config_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_file_ingestion_config] PRIMARY KEY CLUSTERED ([ingestion_config_id] ASC),
    CONSTRAINT [FK_file_ingestion_config_ingestion_config] FOREIGN KEY ([ingestion_config_id]) REFERENCES [control].[ingestion_config] ([ingestion_config_id]),
    CONSTRAINT [CK_file_ingestion_config_format] CHECK ([file_format]='PARQUET' OR [file_format]='JSON' OR [file_format]='CSV'),
    CONSTRAINT [CK_file_ingestion_config_schema_json] CHECK (isjson([expected_schema_json])=(1)),
    CONSTRAINT [CK_file_ingestion_config_csv_options] CHECK ([file_format]<>'CSV' OR [delimiter] IS NOT NULL AND [has_header] IS NOT NULL)
);


GO
