USE [DS_HSDW_App]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO

--ALTER PROCEDURE [Rptg].[usp_Src_Dash_PatExp_ED]
--AS
/**********************************************************************************************************************
WHAT: Stored procedure for Patient Experience Dashboard - Emergency Department
WHO : Chris Mitchell
WHEN: 5/18/2018
WHY : Produce surveys results for EMERGENCY DEPARTMENT patient experience dashboard
-----------------------------------------------------------------------------------------------------------------------
INFO: 
      INPUTS:	DS_HSDW_Prod.dbo.Fact_PressGaney_Responses
				DS_HSDW_Prod.rptg.Balanced_Scorecard_Mapping
				DS_HSDW_Prod.dbo.Dim_PG_Question
				DS_HSDW_Prod.dbo.Fact_Pt_Acct
				DS_HSDW_Prod.dbo.Dim_Pt
				DS_HSDW_Prod.dbo.Dim_Physcn
				DS_HSDW_Prod.dbo.Dim_Date
				DS_HSDW_App.Rptg.[PG_Extnd_Attr]
                  
      OUTPUTS:  ED Survey Results
   
------------------------------------------------------------------------------------------------------------------------
MODS: 	3/16/18 -- flag custom_question questions to remove them from mean calculations
        10/01/2019 -- TMB: changed logic that assigns targets to domains
***********************************************************************************************************************/

SET NOCOUNT ON

IF OBJECT_ID('tempdb..#surveys_er ') IS NOT NULL
DROP TABLE #surveys_er

IF OBJECT_ID('tempdb..#surveys_er2 ') IS NOT NULL
DROP TABLE #surveys_er2

IF OBJECT_ID('tempdb..#surveys_er3 ') IS NOT NULL
DROP TABLE #surveys_er3

IF OBJECT_ID('tempdb..#ED ') IS NOT NULL
DROP TABLE #ED

DECLARE @currdate AS DATE;
DECLARE @startdate AS DATE;
DECLARE @enddate AS DATE;


    SET @currdate=CAST(GETDATE() AS DATE);

    IF @startdate IS NULL
        AND @enddate IS NULL
        BEGIN
            SET @startdate = CAST(DATEADD(MONTH,DATEDIFF(MONTH,0,DATEADD(MONTH,-24,GETDATE())),0) AS DATE); 
            SET @enddate= CAST(EOMONTH(GETDATE()) AS DATE); 
        END; 


SELECT DISTINCT
	 Resp.SURVEY_ID
	,Resp.sk_Fact_Pt_Acct
	,Resp.RECDATE
	,Resp.DISDATE
	,ddte.Fyear_num AS REC_FY
	,phys.DisplayName AS Phys_Name
	,phys.DEPT AS Phys_Dept
	,phys.Division AS Phys_Div
	,'Emergency Department' AS UNIT
	,CAST(Resp.VALUE AS NVARCHAR(500)) AS VALUE -- prevents Tableau from erroring out on import data source
	,CASE WHEN Resp.VALUE IS NOT NULL THEN 1 ELSE 0 END AS VAL_COUNT
	,extd.DOMAIN
	,extd.DOMAIN AS Domain_Goals -- see line below
	--,CASE WHEN resp.sk_Dim_PG_Question = '7' THEN 'Quietness' WHEN Resp.sk_Dim_PG_Question = '6' THEN 'Cleanliness' ELSE DOMAIN END AS Domain_Goals is there an er equivalent of this?
	,CASE WHEN resp.sk_Dim_PG_Question <> '326' THEN -- Age
			CASE WHEN Resp.VALUE = '5' THEN 100
				WHEN Resp.VALUE = '4' THEN 75
				WHEN Resp.VALUE = '3' THEN 50
				WHEN Resp.VALUE = '2' THEN 25
				WHEN Resp.VALUE = '1' THEN 0
				ELSE CAST(Resp.VALUE AS NVARCHAR(500))
			END
	 END AS VALUE_Rptg -- Restated response to accomodate Press Ganey's translation of the 1-5 to 0-100 scale
	,CASE WHEN Resp.sk_Dim_PG_Question IN ('433','436','1213','1212','435','437','1214') THEN 1 ELSE 0 END AS custom_question -- these questions are not included in means
    ,CASE WHEN VALUE = 5 THEN 1 ELSE 0 END AS TOP_BOX
	,qstn.VARNAME
	,qstn.sk_Dim_PG_Question
	,extd.QUESTION_TEXT_ALIAS -- Short form of question text
	,CASE WHEN Resp_Age.AGE < 18 THEN 'Peds' WHEN Resp_Age.AGE >= 18 THEN 'Adult' ELSE NULL END AS AGE_STATUS
	INTO #surveys_er
	FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses AS Resp
	INNER JOIN DS_HSDW_Prod.dbo.Dim_PG_Question AS qstn
		ON Resp.sk_Dim_PG_Question = qstn.sk_Dim_PG_Question
	INNER JOIN DS_HSDW_Prod.Rptg.vwDim_Date ddte
	    ON ddte.day_date = Resp.RECDATE
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Fact_Pt_Acct AS fpa -- LEFT OUTER, including -1 or survey counts won't match press ganey
		ON Resp.sk_Fact_Pt_Acct = fpa.sk_Fact_Pt_Acct
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Dim_Pt AS pat
		ON Resp.sk_Dim_Pt = pat.sk_Dim_Pt
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Dim_Physcn AS phys
		ON Resp.sk_Dim_Physcn = phys.sk_Dim_Physcn
	LEFT OUTER JOIN
	(
		SELECT SURVEY_ID, CAST(MAX(VALUE) AS NVARCHAR(500)) AS AGE FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses
		WHERE sk_Dim_PG_Question = '326'-- Age question for ER
		--AND sk_Fact_Pt_Acct > 0  
		GROUP BY SURVEY_ID
	) Resp_Age
		ON Resp.SURVEY_ID = Resp_Age.SURVEY_ID 
	LEFT OUTER JOIN
	(
		SELECT DISTINCT sk_Dim_PG_Question, DOMAIN, QUESTION_TEXT_ALIAS FROM DS_HSDW_App.Rptg.PG_Extnd_Attr
	) extd
		ON RESP.sk_Dim_PG_Question = extd.sk_Dim_PG_Question
	WHERE  Resp.Svc_Cde='ER' AND qstn.sk_Dim_PG_Question IN
	(
		'323','324','326','327','328','329','330','332','378','379','380','382','383','384','385','388',
		'389','396','397','398','399','400','401','429','431','433','434','435','436','437','440','441',
		'442','446','449','450','1212','1213','1214'
	)
    AND resp.RECDATE >= '7/1/2019 00:00 AM'

------------------------------------------------------------------------------------------

SELECT DISTINCT
    SERVICE_LINE,
    UNIT,
    DOMAIN
FROM DS_HSDW_App.Rptg.PX_Goal_Setting
WHERE Service = 'ED'
AND SERVICE_LINE =  'Emergency'
AND UNIT = 'Emergency'
ORDER BY SERVICE_LINE
       , UNIT
	   , DOMAIN

SELECT DISTINCT
	resp.Domain_Goals
FROM #surveys_er resp
WHERE resp.Domain_Goals IS NOT NULL
ORDER BY resp.Domain_Goals

------------------------------------------------------------------------------------------

SELECT DISTINCT
    SERVICE_LINE
FROM DS_HSDW_App.Rptg.PX_Goal_Setting
WHERE Service = 'ED'
ORDER BY SERVICE_LINE

------------------------------------------------------------------------------------------

SELECT DISTINCT
    UNIT
FROM DS_HSDW_App.Rptg.PX_Goal_Setting
WHERE Service = 'ED'
ORDER BY UNIT

SELECT DISTINCT
	resp.AGE_STATUS
FROM #surveys_er resp
ORDER BY resp.AGE_STATUS

GO


