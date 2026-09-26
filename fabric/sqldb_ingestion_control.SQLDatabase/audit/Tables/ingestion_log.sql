CREATE TABLE [audit].[ingestion_log] (
    [ingestion_log_id]       BIGINT           IDENTITY (1, 1) NOT NULL,
    [ingestion_config_id]    INT              NULL,
    [batch_id]               UNIQUEIDENTIFIER NOT NULL,
    [pipeline_run_id]        NVARCHAR (100)   NOT NULL,
    [pipeline_name]          NVARCHAR (200)   NOT NULL,
    [run_type]               VARCHAR (20)     NOT NULL,
    [source_system]          NVARCHAR (100)   NULL,
    [source_schema]          NVARCHAR (128)   NULL,
    [source_object]          NVARCHAR (128)   NULL,
    [target_path]            NVARCHAR (1000)  NULL,
    [target_schema]          NVARCHAR (128)   NULL,
    [target_table]           NVARCHAR (128)   NULL,
    [load_strategy]          VARCHAR (20)     NULL,
    [watermark_field]        NVARCHAR (128)   NULL,
    [processing_lower_bound] DATETIME2 (3)    NULL,
    [processing_upper_bound] DATETIME2 (3)    NULL,
    [source_row_count]       BIGINT           NULL,
    [target_row_count]       BIGINT           NULL,
    [status]                 VARCHAR (20)     NOT NULL,
    [error_code]             NVARCHAR (100)   NULL,
    [error_message]          NVARCHAR (4000)  NULL,
    [start_time]             DATETIME2 (3)    NOT NULL,
    [end_time]               DATETIME2 (3)    NOT NULL,
    [duration_seconds]       INT              NOT NULL,
    [log_timestamp]          DATETIME2 (3)    CONSTRAINT [DF_ingestion_log_timestamp] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_ingestion_log] PRIMARY KEY CLUSTERED ([ingestion_log_id] ASC),
    CONSTRAINT [CK_ingestion_log_counts] CHECK (([source_row_count] IS NULL OR [source_row_count]>=(0)) AND ([target_row_count] IS NULL OR [target_row_count]>=(0))),
    CONSTRAINT [CK_ingestion_log_duration] CHECK ([duration_seconds]>=(0)),
    CONSTRAINT [CK_ingestion_log_run_type] CHECK ([run_type]='BACKFILL' OR [run_type]='RERUN' OR [run_type]='REGULAR'),
    CONSTRAINT [CK_ingestion_log_status] CHECK ([status]='CANCELLED' OR [status]='SKIPPED' OR [status]='WARN' OR [status]='FAILED' OR [status]='SUCCESS'),
    CONSTRAINT [CK_ingestion_log_time] CHECK ([end_time]>=[start_time]),
    CONSTRAINT [UQ_ingestion_log_pipeline_run] UNIQUE NONCLUSTERED ([pipeline_run_id] ASC)
);


GO

CREATE NONCLUSTERED INDEX [IX_ingestion_log_batch]
    ON [audit].[ingestion_log]([batch_id] ASC, [ingestion_log_id] ASC);


GO

CREATE NONCLUSTERED INDEX [IX_ingestion_log_config_time]
    ON [audit].[ingestion_log]([ingestion_config_id] ASC, [start_time] DESC);


GO

CREATE NONCLUSTERED INDEX [IX_ingestion_log_status_time]
    ON [audit].[ingestion_log]([status] ASC, [start_time] DESC);


GO

