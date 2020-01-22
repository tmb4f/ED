USE [DS_HSDW_App]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO

DECLARE @StartDate SMALLDATETIME
       ,@EndDate SMALLDATETIME

--SET @StartDate = NULL
--SET @EndDate = NULL
SET @StartDate = '7/1/2018'
--SET @EndDate = '12/29/2019'
--SET @StartDate = '7/1/2019'
SET @EndDate = '1/5/2020'

--CREATE PROCEDURE [Rptg].[uspSrc_Dash_PatExp_ED_Response_Summary]
--    (
--     @StartDate SMALLDATETIME = NULL,
--     @EndDate SMALLDATETIME = NULL
--    )
--AS
/**********************************************************************************************************************
WHAT: Stored procedure for Patient Experience Dashboard - Emergency Department - Response Summary
WHO : Tom Burgan
WHEN: 1/6/2020
WHY : Report survey response summary for EMERGENCY DEPARTMENT patient experience dashboard
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
MODS: 	1/6/2020 - Create stored procedure
***********************************************************************************************************************/

SET NOCOUNT ON

---------------------------------------------------
---Default date range is the first day of FY 19 (7/1/2018) to yesterday's date
DECLARE @currdate AS SMALLDATETIME;
--DECLARE @startdate AS DATE;
--DECLARE @enddate AS DATE;

    SET @currdate=CAST(CAST(GETDATE() AS DATE) AS SMALLDATETIME);

    IF @StartDate IS NULL
        AND @EndDate IS NULL
        BEGIN
            SET @StartDate = CAST(CAST('7/1/2018' AS DATE) AS SMALLDATETIME);
            SET @EndDate= CAST(DATEADD(DAY, -1, CAST(GETDATE() AS DATE)) AS SMALLDATETIME); 
        END; 

----------------------------------------------------
DECLARE @locstartdate SMALLDATETIME,
        @locenddate SMALLDATETIME

SET @locstartdate = @startdate
SET @locenddate   = @enddate

IF OBJECT_ID('tempdb..#er_resp ') IS NOT NULL
DROP TABLE #er_resp

IF OBJECT_ID('tempdb..#surveys_er ') IS NOT NULL
DROP TABLE #surveys_er

IF OBJECT_ID('tempdb..#surveys_er2 ') IS NOT NULL
DROP TABLE #surveys_er2

IF OBJECT_ID('tempdb..#surveys_er3 ') IS NOT NULL
DROP TABLE #surveys_er3

IF OBJECT_ID('tempdb..#ED ') IS NOT NULL
DROP TABLE #ED

IF OBJECT_ID('tempdb..#surveys_er_sum ') IS NOT NULL
DROP TABLE #surveys_er_sum

SELECT
	SURVEY_ID
	,sk_Dim_PG_Question
	,sk_Fact_Pt_Acct
	,sk_Dim_Pt
	,Svc_Cde
	,RECDATE
	,DISDATE
	,CAST(VALUE AS NVARCHAR(500)) AS VALUE
	,CASE WHEN sk_Dim_Clrt_DEPt = 0 THEN 378 ELSE sk_Dim_Clrt_DEPt END AS sk_Dim_Clrt_DEPt
	,sk_Dim_Physcn
INTO #er_resp
FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses
WHERE sk_Dim_PG_Question IN
(
	'323','324','326','327','328','329','330','332','378','379','380','382','383','384','385','388',
	'389','396','397','398','399','400','401','429','431','433','434','435','436','437','440','441',
	'442','446','449','450','1212','1213','1214'
)
	AND RECDATE BETWEEN @locstartdate AND @locenddate

SELECT DISTINCT
	 Resp.SURVEY_ID
	,Resp.sk_Fact_Pt_Acct
	,Resp.RECDATE
	,Resp.DISDATE
	,ddte.Fyear_num AS REC_FY
	,phys.DisplayName AS Phys_Name
	,phys.DEPT AS Phys_Dept
	,phys.Division AS Phys_Div
	,Resp.sk_Dim_Clrt_DEPt
	,CAST(COALESCE(dept.DEPARTMENT_ID,'Unknown') AS VARCHAR(255)) AS Survey_Department_Id
	,dept.Clrt_DEPt_Nme AS Survey_Department_Name
	 ,loc_master.EPIC_DEPARTMENT_ID
	 ,loc_master.epic_department_name
	 ,loc_master.SERVICE_LINE_ID
	 ,CASE WHEN loc_master.opnl_service_name = 'Emergency Department' AND (loc_master.service_line IS NULL OR loc_master.SERVICE_LINE = 'Unknown') THEN 'Emergency Department'
		   WHEN loc_master.service_line IS NULL OR loc_master.service_line = 'Unknown' THEN 'Other'
		   ELSE loc_master.service_line END AS Survey_Service_Line
	 ,CASE WHEN loc_master.opnl_service_name = 'Emergency Department' AND (loc_master.service_line IS NULL OR loc_master.SERVICE_LINE = 'Unknown') THEN 'Emergency Department'
		   WHEN loc_master.service_line IS NULL OR loc_master.service_line = 'Unknown' THEN 'Other'
		   ELSE loc_master.service_line END AS SERVICE_LINE
	,'Emergency Department' AS UNIT
	,'Emergency Department' AS Survey_Unit
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
	,ddte.quarter_name
	,ddte.month_num
	,ddte.month_short_name
	,ddte.year_num
	INTO #surveys_er
    FROM #er_resp AS Resp
	--FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses AS Resp
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
    LEFT OUTER JOIN DS_HSDW_Prod.Rptg.vwDim_Clrt_DEPt dept
	    ON Resp.sk_Dim_Clrt_DEPt = dept.sk_Dim_Clrt_DEPt
    LEFT OUTER JOIN DS_HSDW_Prod.Rptg.vwRef_MDM_Location_Master_EpicSvc AS loc_master
	    ON dept.DEPARTMENT_ID = loc_master.EPIC_DEPARTMENT_ID
	--WHERE  Resp.Svc_Cde='ER' AND qstn.sk_Dim_PG_Question IN
	--(
	--	'323','324','326','327','328','329','330','332','378','379','380','382','383','384','385','388',
	--	'389','396','397','398','399','400','401','429','431','433','434','435','436','437','440','441',
	--	'442','446','449','450','1212','1213','1214'
	--)

------------------------------------------------------------------------------------------
--- JOIN TO DIM_DATE

 SELECT
	'Emergency Department' AS Event_Type
	,SURVEY_ID
	,sk_Fact_Pt_Acct
	,rec.day_date AS Event_Date
	,dis.day_date AS Event_Date_Disch
	,rec.Fyear_num AS Event_FY
	,sk_Dim_PG_Question
	,VARNAME
	,QUESTION_TEXT_ALIAS
	,#surveys_er.Domain
	,Domain_Goals
	,RECDATE AS Recvd_Date
	,DISDATE AS Discharge_Date
	,Phys_Name
	,Phys_Dept
	,Phys_Div
	,goals.GOAL
	,goals_overall.GOAL AS GOAL_OVERALL
	,#surveys_er.UNIT
	,VALUE
	,VALUE_Rptg
	,custom_question
	,TOP_BOX
	,VAL_COUNT
	,#surveys_er.AGE_STATUS
	,#surveys_er.quarter_name
	,#surveys_er.month_num
	,#surveys_er.month_short_name
	,#surveys_er.year_num
    ,Survey_Unit
	,Survey_Service_Line
	,service_line_id
	,#surveys_er.SERVICE_LINE
	,Survey_Department_Id
	,Survey_Department_Name
	,#surveys_er.epic_department_id
	,#surveys_er.epic_department_name
INTO #surveys_er2
FROM (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @locstartdate AND day_date <= @locenddate) rec
LEFT OUTER JOIN #surveys_er
ON rec.day_date = #surveys_er.RECDATE
FULL OUTER JOIN (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @locstartdate AND day_date <= @locenddate) dis -- Need to report by both the discharge date on the survey as well as the received date of the survey
ON dis.day_date = #surveys_er.DISDATE
LEFT OUTER JOIN DS_HSDW_App.Rptg.ED_Goals goals
ON #surveys_er.REC_FY = goals.GOAL_FISCAL_YR AND #surveys_er.AGE_STATUS = goals.AGE_STATUS AND #surveys_er.Domain_Goals = goals.DOMAIN
LEFT OUTER JOIN
(
	SELECT GOAL_FISCAL_YR, AGE_STATUS, GOAL FROM DS_HSDW_App.Rptg.ED_Goals WHERE DOMAIN = 'Overall Mean'
) goals_overall
ON goals_overall.GOAL_FISCAL_YR = #surveys_er.REC_FY AND goals_overall.AGE_STATUS = #surveys_er.AGE_STATUS
ORDER BY Event_Date, SURVEY_ID, sk_Dim_PG_Question

------------------------------------------------------------------------------------------------------------------------------------

SELECT * INTO #surveys_er3
FROM #surveys_er2
UNION ALL

(
	SELECT
		 all_age.Event_Type
		,all_age.SURVEY_ID
		,all_age.sk_Fact_Pt_Acct
		,all_age.Event_Date
		,all_age.Event_Date_Disch
		,all_age.Event_FY
		,all_age.sk_Dim_PG_Question
		,all_age.VARNAME
		,all_age.QUESTION_TEXT_ALIAS
		,all_age.DOMAIN
		,all_age.Domain_Goals
		,all_age.Recvd_Date
		,all_age.Discharge_Date
		,all_age.Phys_Name
		,all_age.Phys_Dept
		,all_age.Phys_Div
		,goals.GOAL
		,goals_overall.GOAL AS GOAL_OVERALL
		,all_age.UNIT
		,all_age.VALUE
		,all_age.VALUE_Rptg
		,all_age.custom_question
		,all_age.TOP_BOX
		,all_age.VAL_COUNT
		,all_age.AGE_STATUS
		,all_age.quarter_name
		,all_age.month_num
		,all_age.month_short_name
		,all_age.year_num
		,all_age.Survey_Unit
		,all_age.Survey_Service_Line
		,all_age.service_line_id
		,all_age.SERVICE_LINE
		,all_age.Survey_Department_Id
		,all_age.Survey_Department_Name
		,all_age.epic_department_id
		,all_age.epic_department_name
	FROM
	(
		SELECT
			'Emergency Department' AS Event_Type
			,SURVEY_ID
			,sk_Fact_Pt_Acct
			,rec.day_date AS Event_Date
			,dis.day_date AS Event_Date_Disch
	        ,rec.Fyear_num AS Event_FY
			,sk_Dim_PG_Question
			,VARNAME
			,QUESTION_TEXT_ALIAS
			,#surveys_er.Domain
			,Domain_Goals
			,RECDATE AS Recvd_Date
			,DISDATE AS Discharge_Date
			,REC_FY
			,Phys_Name
			,Phys_Dept
			,Phys_Div
			,#surveys_er.UNIT
			,VALUE
			,VALUE_Rptg
			,custom_question
			,TOP_BOX
			,VAL_COUNT
			,CASE WHEN SURVEY_ID IS NULL THEN NULL ELSE 'All' END AS AGE_STATUS
			,rec.quarter_name
			,rec.month_num
			,rec.month_short_name
			,rec.year_num
			,Survey_Unit
			,Survey_Service_Line
			,service_line_id
			,#surveys_er.SERVICE_LINE
			,Survey_Department_Id
			,Survey_Department_Name
			,#surveys_er.epic_department_id
			,#surveys_er.epic_department_name
		FROM (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @locstartdate AND day_date <= @locenddate) rec
		LEFT OUTER JOIN #surveys_er
		ON rec.day_date = #surveys_er.RECDATE
		FULL OUTER JOIN (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @locstartdate AND day_date <= @locenddate) dis -- Need to report by both the discharge date on the survey as well as the received date of the survey
		ON dis.day_date = #surveys_er.DISDATE
		LEFT OUTER JOIN DS_HSDW_App.Rptg.ED_Goals goals
		ON #surveys_er.REC_FY = goals.GOAL_FISCAL_YR AND #surveys_er.AGE_STATUS = goals.AGE_STATUS AND #surveys_er.Domain_Goals = goals.DOMAIN
	) all_age
	LEFT OUTER JOIN DS_HSDW_App.Rptg.ED_Goals goals
	ON all_age.REC_FY = goals.GOAL_FISCAL_YR AND all_age.AGE_STATUS = goals.AGE_STATUS AND all_age.Domain_Goals = goals.DOMAIN
	LEFT OUTER JOIN
	DS_HSDW_App.Rptg.ED_Goals goals_overall
	ON goals_overall.GOAL_FISCAL_YR = all_age.REC_FY AND goals_overall.AGE_STATUS = all_age.AGE_STATUS AND goals_overall.DOMAIN = 'Overall Mean' AND goals_overall.AGE_STATUS = 'All'
)

-------------------------------------------------------------------------------------------------------------------------------------
-- RESULTS

 SELECT
    [Event_Type]
   ,[SURVEY_ID]
   ,[sk_Fact_Pt_Acct]
   ,[Event_Date]
   ,[Event_Date_Disch]
   ,Event_FY
   ,[sk_Dim_PG_Question]
   ,[VARNAME]
   ,[QUESTION_TEXT_ALIAS]
   ,[DOMAIN]
   ,[Domain_Goals]
   ,[Recvd_Date]
   ,[Discharge_Date]
   ,[Phys_Name]
   ,[Phys_Dept]
   ,[Phys_Div]
   ,[GOAL]
   ,[GOAL_OVERALL]
   ,[UNIT]
   ,[VALUE]
   ,[VALUE_Rptg]
   ,[custom_question]
   ,TOP_BOX
   ,[VAL_COUNT]
   ,AGE_STATUS
   ,quarter_name
   ,month_num
   ,month_short_name
   ,year_num
   ,Survey_Unit
   ,Survey_Service_Line
   ,service_line_id
   ,SERVICE_LINE
   ,Survey_Department_Id
   ,Survey_Department_Name
   ,epic_department_id
   ,epic_department_name
  INTO #ED
  FROM [#surveys_er3]

------------------------------------------------------------------------------------------
--- GENERATE SUMMARY FOR TESTING

SELECT resp.Event_Type,
       resp.Event_FY,
	   resp.year_num,
       resp.month_num,
       resp.month_short_name,
       resp.UNIT,
       resp.SERVICE_LINE,
	   resp.AGE_STATUS,
       resp.Domain_Goals,
	   resp.QUESTION_TEXT_ALIAS,
       resp.EPIC_DEPARTMENT_ID,
       resp.epic_department_name,
	   resp.GOAL,
       SUM(resp.TOP_BOX) AS TOP_BOX,
       SUM(resp.VAL_COUNT) AS VAL_COUNT,
	   --CAST(CAST(SUM(resp.TOP_BOX) AS NUMERIC(6,3)) / CAST(SUM(resp.VAL_COUNT) AS NUMERIC(6,3)) AS NUMERIC(4,3)) AS SCORE,
	   --COUNT(*) AS N
	   COUNT(DISTINCT resp.SURVEY_ID) AS SURVEY_ID_COUNT
INTO #surveys_er_sum
FROM
(
SELECT
	Event_Type,
	Event_FY,
	year_num,
	month_num,
	month_short_name,
    UNIT,
    SERVICE_LINE,
    EPIC_DEPARTMENT_ID,
    epic_department_name,
	AGE_STATUS,
	VALUE,
	TOP_BOX,
    VAL_COUNT,
	DOMAIN,
    Domain_Goals,
	QUESTION_TEXT_ALIAS,
	SURVEY_ID,
	GOAL
--INTO #surveys_op_sum
--FROM #surveys_er
FROM #ED
--WHERE REC_FY = 2020
--WHERE Event_FY IN (2019,2020)
WHERE Event_FY >= 2019
--AND sk_Dim_PG_Question = 17 -- Rate Hospital 0-10
AND Domain_Goals IS NOT NULL
--AND (Domain_Goals IS NOT NULL
--AND Domain_Goals NOT IN
--(
--'Access to Specialists'
--,'Additional Questions About Your Care'
--,'Between Visit Communication'
--,'Health Promotion and Education'
--,'Education About Medication'
--,'Shared Decision Making'
--,'Stewardship of Patient Resources'
--))
) resp
GROUP BY 
	resp.Event_Type,
	resp.Event_FY,
	resp.year_num,
	month_num,
	month_short_name,
    UNIT,
    SERVICE_LINE,
	AGE_STATUS,
	Domain_Goals,
	QUESTION_TEXT_ALIAS,
    EPIC_DEPARTMENT_ID,
    epic_department_name,
	GOAL

SELECT Event_Type,
       Event_FY,
	   year_num AS Event_CY,
       month_num AS [Month],
       month_short_name AS Month_Name,
       Service_Line,
       epic_department_id AS DEPARTMENT_ID,
       epic_department_name AS DEPARTMENT_NAME,
       UNIT,
	   AGE_STATUS,
       Domain_Goals,
       QUESTION_TEXT_ALIAS,
       TOP_BOX,
       VAL_COUNT,
       SURVEY_ID_COUNT AS N,
       GOAL
FROM #surveys_er_sum
ORDER BY Event_Type
       , Event_FY
	   , year_num
       , month_num
	   , month_short_name
	   , Service_Line
	   , epic_department_id
	   , epic_department_name
	   , UNIT
	   , AGE_STATUS
	   , Domain_Goals
	   , QUESTION_TEXT_ALIAS

GO


