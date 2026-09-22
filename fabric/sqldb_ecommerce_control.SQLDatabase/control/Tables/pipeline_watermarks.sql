CREATE TABLE [control].[pipeline_watermarks] (
    [ingestion_config_id]             INT              NOT NULL,
    [watermark_field]                 NVARCHAR (128)   NOT NULL,
    [last_watermark_value]            DATETIME2 (3)    NOT NULL,
    [last_successful_batch_id]        UNIQUEIDENTIFIER NULL,
    [last_successful_pipeline_run_id] NVARCHAR (100)   NULL,
    [watermark_updated_at]            DATETIME2 (3)    CONSTRAINT [DF_pipeline_watermarks_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_pipeline_watermarks] PRIMARY KEY CLUSTERED ([ingestion_config_id] ASC),
    CONSTRAINT [FK_pipeline_watermarks_config] FOREIGN KEY ([ingestion_config_id]) REFERENCES [control].[ingestion_config] ([ingestion_config_id])
);


GO

