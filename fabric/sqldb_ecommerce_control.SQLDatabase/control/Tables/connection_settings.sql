CREATE TABLE [control].[connection_settings] (
    [connection_ref]      NVARCHAR (100) NOT NULL,
    [connection_type]     VARCHAR (50)   NOT NULL,
    [connection_settings] NVARCHAR (MAX) NOT NULL,
    [created_at]          DATETIME2 (3)  CONSTRAINT [DF_connection_settings_created_at] DEFAULT (sysutcdatetime()) NOT NULL,
    [updated_at]          DATETIME2 (3)  CONSTRAINT [DF_connection_settings_updated_at] DEFAULT (sysutcdatetime()) NOT NULL,
    CONSTRAINT [PK_connection_settings] PRIMARY KEY CLUSTERED ([connection_ref] ASC),
    CONSTRAINT [CK_connection_settings_json] CHECK (isjson([connection_settings])=(1))
);


GO

