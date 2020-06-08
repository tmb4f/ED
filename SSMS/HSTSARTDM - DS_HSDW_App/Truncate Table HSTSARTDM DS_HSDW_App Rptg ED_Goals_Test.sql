USE [DS_HSDW_App]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

DECLARE @RC INT
DECLARE @schema VARCHAR(100)
DECLARE @Table VARCHAR(100)

SET @schema = 'Rptg'
SET @Table = 'ED_Goals_Test'

EXECUTE @RC = [dbo].[usp_TruncateTable] 
   @schema
  ,@Table

GO


