-- POS error daily snapshot (aggregated). Placeholders {{START_DATE}} and {{END_DATE}} are 'YYYY-MM-DD'.
-- Grain: snapshot_date x pos_partner x integration_type x system x merchant x result x status_code.
-- order_count = number of orders in that group. FAILED rows carry status_code + a sample_message; SUCCESS collapses to status_code=NULL.
WITH detail AS (
select * from
(SELECT a.id, a.order_id, a.Result, a.pos_partner, DATE(a.created_date) as created_date,
a.integration_type,
a.middleware_integrated, a.status_code, a.message, a.status,
a. merchant_name,
merchant_key,m.Chain_Name_in_system as brand_name, m.Account_Name,
a.Product_Name, a.Country,
case when currency_symbol = 'MYR' then round(order_amount*0.33, 2)
when currency_symbol = 'RM' then round(order_amount*0.33, 2)
when currency_symbol ='IDR' then round(order_amount*0.000092, 2)
when currency_symbol ='Rp' then round(order_amount*0.000092, 2)
when currency_symbol = 'AUD' then round(order_amount*1, 2)
when currency_symbol = 'BND' then round(order_amount*1, 2)
when currency_symbol = 'GBP' then round(order_amount*1.86985, 2)
when currency_symbol = 'NZD' then round(order_amount*0.92, 2)
when currency_symbol = 'PHP' then round(order_amount*0.028, 2)
when currency_symbol = 'HKD' then round(order_amount*0.17, 2)
when currency_symbol = 'EUR' then round(order_amount*1.61, 2)
when currency_symbol = 'THB' then round(order_amount*0.041, 2)
when currency_symbol = 'USD' then round(order_amount*1.34386, 2)
when currency_symbol = 'TWD' then round(order_amount*0.047, 2)
when currency_symbol = 'AED' then round(order_amount*0.37, 2)
when a.Country like '%French Guiana%' then round(order_amount*0.00016, 2)
when a.Country like '%United Kingdom%' then round(order_amount*1.68, 2)
else round(order_amount, 2) end as total_amount, a.system, a.created_date as createddate,
local_time,
a.updated_date as updateddate,
a.second_diff,
CASE WHEN a.second_diff <0  THEN '< 0'
WHEN a.second_diff >= 0 and a.second_diff <= 10 THEN '0-10'
WHEN a.second_diff > 10 and a.second_diff <= 20 THEN '11-20'
WHEN a.second_diff > 20 and a.second_diff <= 30 THEN '21-30'
WHEN a.second_diff > 30 and a.second_diff <= 40 THEN '31-40'
WHEN a.second_diff > 40 and a.second_diff <= 50 THEN '41-50'
WHEN a.second_diff > 50 and a.second_diff <= 60 THEN '51-60'
WHEN a.second_diff >60 THEN '>60'
END as sec_diff
FROM
(select ops.id, ops.order_id,
CASE WHEN ops.result = 0 THEN 'FAILED'
WHEN ops.result = 1 THEN 'SUCCESS'
ELSE 'UNKNOWN' END as Result,
ops.pos_partner_id,
CASE WHEN ops.pos_partner_id = '1' THEN 'RAPTOR'
WHEN ops.pos_partner_id = '2' THEN 'AGILYSYS'
WHEN ops.pos_partner_id = '3' THEN 'ALOHA'
WHEN ops.pos_partner_id = '2606' THEN 'ALOHA'
WHEN ops.pos_partner_id = '4' THEN 'EPOINT'
WHEN ops.pos_partner_id = '50' THEN 'EPOINT'
WHEN ops.pos_partner_id = '5' THEN 'STANDARD_ALONE'
WHEN ops.pos_partner_id = '6' THEN 'KONVERGE'
WHEN ops.pos_partner_id = '7' THEN 'MEGA'
WHEN ops.pos_partner_id = '8' THEN 'FOODZAPS'
WHEN ops.pos_partner_id = '9' THEN 'SUNTOYO'
WHEN ops.pos_partner_id = '10' THEN 'AU'
WHEN ops.pos_partner_id = '11' THEN 'EASI'
WHEN ops.pos_partner_id = '12' THEN 'BEZ'
WHEN ops.pos_partner_id = '13' THEN 'CATERLORD'
WHEN ops.pos_partner_id = '14' THEN 'MICROS'
WHEN ops.pos_partner_id = '16' THEN 'PROMISE'
WHEN ops.pos_partner_id = '17' THEN 'VIRTUAL'
WHEN ops.pos_partner_id = '18' THEN 'EDGEWORKS'
WHEN ops.pos_partner_id = '19' THEN 'PAPARICH'
WHEN ops.pos_partner_id = '20' THEN 'SABRE'
WHEN ops.pos_partner_id = '21' THEN 'SIMPHONY_V2'
WHEN ops.pos_partner_id = '22' THEN 'GPOS'
WHEN ops.pos_partner_id = '23' THEN 'SIMPHONY_V1'
WHEN ops.pos_partner_id = '24' THEN 'SIMPHONY_SWS'
WHEN ops.pos_partner_id = '25' THEN 'DOSHII'
WHEN ops.pos_partner_id = '26' THEN 'KOUNTA'
WHEN ops.pos_partner_id = '27' THEN 'POINTSOFT'
WHEN ops.pos_partner_id = '28' THEN 'REVEL'
WHEN ops.pos_partner_id = '29' THEN 'SHIJI'
WHEN ops.pos_partner_id = '30' THEN 'SWIFT'
WHEN ops.pos_partner_id = '31' THEN 'SHIFT8'
WHEN ops.pos_partner_id = '32' THEN 'CMG'
WHEN ops.pos_partner_id = '33' THEN 'XILNEX'
WHEN ops.pos_partner_id = '34' THEN 'ZEONIQ'
WHEN ops.pos_partner_id = '35' THEN 'ITNT'
WHEN ops.pos_partner_id = '36' THEN 'REDCAT'
WHEN ops.pos_partner_id = '37' THEN 'IDEAL'
WHEN ops.pos_partner_id = '38' THEN 'POINTSOFT'
WHEN ops.pos_partner_id = '39' THEN 'KONVERGE_V2'
WHEN ops.pos_partner_id = '40' THEN 'SIMPHONY_CLOUD'
WHEN ops.pos_partner_id = '41' THEN 'KOUNTA'
WHEN ops.pos_partner_id = '42' THEN 'AGILYSYS_V2'
WHEN ops.pos_partner_id = '43' THEN 'REVEL_V2'
WHEN ops.pos_partner_id = '44' THEN 'MINOR'
WHEN ops.pos_partner_id = '45' THEN 'OPEN_API'
WHEN ops.pos_partner_id = '47' THEN 'OPEN_API_V2'
WHEN ops.pos_partner_id = '48' THEN 'TYRO'
WHEN ops.pos_partner_id = '49' THEN 'KONVERGE_V3'
WHEN ops.pos_partner_id Between '1000' and '1009' THEN 'RAPTOR'
WHEN ops.pos_partner_id BETWEEN '1010' and '1019' then 'DELIVERECT'
WHEN ops.pos_partner_id between '1020' and '1029' then 'NOVITEE'
WHEN ops.pos_partner_id between '1030' and '1039' then 'CATERLORD'
WHEN ops.pos_partner_id between '1040' and '1049' then 'DHGODROID'
WHEN ops.pos_partner_id between '1050' and '1059' then 'CUSCAPI'
WHEN ops.pos_partner_id between '1060' and '1069' then 'KOUNTA'
WHEN ops.pos_partner_id between '1070' and '1079' then 'ALOHA_CONNECT'
WHEN ops.pos_partner_id between '1080' and '1089' then 'ALOHA_BSL'
WHEN ops.pos_partner_id between '1090' and '1099' then 'TYRO'
WHEN ops.pos_partner_id between '1100' and '1109' then 'OPEN_API_NEW'
WHEN ops.pos_partner_id between '1110' and '1119' then 'KFC'
WHEN ops.pos_partner_id between '1120' and '1129' then 'POINTSOFT'
WHEN ops.pos_partner_id between '1130' and '1139' then 'SHIFT8'
WHEN ops.pos_partner_id between '1140' and '1149' then 'CMG'
WHEN ops.pos_partner_id between '1150' and '1159' then 'REDCAT'
WHEN ops.pos_partner_id between '1160' and '1169' then 'EPOINT'
WHEN ops.pos_partner_id between '1170' and '1179' then 'ZEONIQ'
WHEN ops.pos_partner_id between '1180' and '1189' then 'SIMPHONY'
WHEN ops.pos_partner_id between '1190' and '1199' then 'AGLISYS'
WHEN ops.pos_partner_id between '1200' and '1209' then 'GPOS'
WHEN ops.pos_partner_id between '1210' and '1219' then 'ALOHA_ATO'
WHEN ops.pos_partner_id between '1220' and '1229' then 'WEIBY'
WHEN ops.pos_partner_id between '1230' and '1239' then 'OMEGA'
WHEN ops.pos_partner_id between '1240' and '1249' then 'ZINGPOS'
WHEN ops.pos_partner_id between '1250' and '1259' then 'XILNEX'
ELSE 'UNKNOWN' END as pos_partner, ops.status_code, ops.message, o.status,
ops.ecms_order, ops.created_date, ops.updated_date, ops.integration_type, ops.restaurant_id, ops.middleware_integrated,
DATETIME(ops.created_date,ifnull(tz.timezone, "Asia/Singapore")) as local_time,
ml.RestaurantName as merchant_name,
ml.merchant_id as merchant_key,
org.name as ecms_merchant,
org.merchant_key as ecms_merchant_id,
 apt.name as Product_Name,
o.currency_symbol, o.order_amount,
ml.country as Country,
case when org.name is null THEN 'CMS' ELSE 'ECMS' end as system,
DATETIME_DIFF(ops.updated_date, ops.created_date, second) as second_diff
from `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_order_pos_status_view_prod` ops
left join `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_orders_view_prod` o on o.id = ops.order_id
left join `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_organization_view_prod` org ON o.restaurant_id = org.id
left join `tabsquare-data-sciences.tabsquare_dw_lookups.master_merchant_list` as ml on ml.Merchant_id = org.merchant_key
left join `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_app_type_view_prod` as apt on apt.id = o.app_type
LEFT JOIN `tabsquare-data-sciences.tabsquare_dw_lookups.all_merchants_timezone_lookups` as tz
ON ops.restaurant_id=tz.restaurant_id
where date(ops.created_date) >= DATE("{{START_DATE}}") and date(ops.created_date)<=DATE("{{END_DATE}}")
and date(o.changed_date) >= DATE("{{START_DATE}}") and date(o.changed_date) <= DATE("{{END_DATE}}")
and COALESCE(is_test_account,0)!=1
) as a
left join `tabsquare-data-sciences.tabsquare_dw_lookups.master_merchant_list` as m on m.Merchant_id = a.merchant_key
) as b
where NOT(LOWER(merchant_name) LIKE ("%test%")
    OR LOWER(merchant_name) LIKE ("%demo%")
    OR LOWER(merchant_name) LIKE ("%ts cafe%")
    OR LOWER(merchant_name) LIKE ("%latest%"))
)
SELECT
  created_date AS snapshot_date,
  pos_partner, integration_type, system,
  merchant_key, merchant_name, brand_name, Account_Name AS account_name, Country AS country,
  Result AS result,
  IF(Result='FAILED', CAST(status_code AS STRING), NULL) AS status_code,
  IF(Result='FAILED', ANY_VALUE(SUBSTR(message,1,200)), NULL) AS sample_message,
  COUNT(*) AS order_count
FROM detail
GROUP BY snapshot_date, pos_partner, integration_type, system, merchant_key, merchant_name, brand_name, account_name, country, result,
  IF(Result='FAILED', CAST(status_code AS STRING), NULL)
ORDER BY snapshot_date, pos_partner, merchant_name, status_code
