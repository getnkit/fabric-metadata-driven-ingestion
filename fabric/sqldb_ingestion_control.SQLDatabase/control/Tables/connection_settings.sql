CREATE TABLE [control].[connection_settings] (
    [connection_ref]      NVARCHAR (100) NOT NULL,
    [connection_type]     VARCHAR (50)   NOT NULL,
    [connection_settings] NVARCHAR (MAX) NOT NULL,
    [created_at]          DATETIME2 (3)  CONSTRAINT [DF_connection_settings_created_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [updated_at]          DATETIME2 (3)  CONSTRAINT [DF_connection_settings_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_connection_settings] PRIMARY KEY CLUSTERED ([connection_ref] ASC),
    CONSTRAINT [CK_connection_settings_json] CHECK (ISJSON([connection_settings], OBJECT) = 1),
    CONSTRAINT [CK_connection_settings_ref_not_blank] CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM [connection_ref])) > 0),
    CONSTRAINT [CK_connection_settings_type] CHECK ([connection_type]='LAKEHOUSE' OR [connection_type]='SFTP' OR [connection_type]='AZURE_SQL')
);


GO

