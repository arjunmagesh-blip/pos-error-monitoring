-- POS error ACTIVE MONITOR query (rolling window, aggregated per merchant).
-- Placeholder {{WINDOW_HOURS}} = how many hours back from now to scan (on created_date, UTC).
-- One row per (pos_partner, merchant_key) with totals/fails/timeouts over the window.
-- Timeout = status_code 504 (see POS timeout definition). Read-only.
WITH detail AS (
  SELECT
    CASE
      WHEN ops.pos_partner_id = '1' THEN 'RAPTOR'
      WHEN ops.pos_partner_id = '2' THEN 'AGILYSYS'
      WHEN ops.pos_partner_id IN ('3','2606') THEN 'ALOHA'
      WHEN ops.pos_partner_id IN ('4','50') THEN 'EPOINT'
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
      WHEN ops.pos_partner_id BETWEEN '1000' AND '1009' THEN 'RAPTOR'
      WHEN ops.pos_partner_id BETWEEN '1010' AND '1019' THEN 'DELIVERECT'
      WHEN ops.pos_partner_id BETWEEN '1020' AND '1029' THEN 'NOVITEE'
      WHEN ops.pos_partner_id BETWEEN '1030' AND '1039' THEN 'CATERLORD'
      WHEN ops.pos_partner_id BETWEEN '1040' AND '1049' THEN 'DHGODROID'
      WHEN ops.pos_partner_id BETWEEN '1050' AND '1059' THEN 'CUSCAPI'
      WHEN ops.pos_partner_id BETWEEN '1060' AND '1069' THEN 'KOUNTA'
      WHEN ops.pos_partner_id BETWEEN '1070' AND '1079' THEN 'ALOHA_CONNECT'
      WHEN ops.pos_partner_id BETWEEN '1080' AND '1089' THEN 'ALOHA_BSL'
      WHEN ops.pos_partner_id BETWEEN '1090' AND '1099' THEN 'TYRO'
      WHEN ops.pos_partner_id BETWEEN '1100' AND '1109' THEN 'OPEN_API_NEW'
      WHEN ops.pos_partner_id BETWEEN '1110' AND '1119' THEN 'KFC'
      WHEN ops.pos_partner_id BETWEEN '1120' AND '1129' THEN 'POINTSOFT'
      WHEN ops.pos_partner_id BETWEEN '1130' AND '1139' THEN 'SHIFT8'
      WHEN ops.pos_partner_id BETWEEN '1140' AND '1149' THEN 'CMG'
      WHEN ops.pos_partner_id BETWEEN '1150' AND '1159' THEN 'REDCAT'
      WHEN ops.pos_partner_id BETWEEN '1160' AND '1169' THEN 'EPOINT'
      WHEN ops.pos_partner_id BETWEEN '1170' AND '1179' THEN 'ZEONIQ'
      WHEN ops.pos_partner_id BETWEEN '1180' AND '1189' THEN 'SIMPHONY'
      WHEN ops.pos_partner_id BETWEEN '1190' AND '1199' THEN 'AGLISYS'
      WHEN ops.pos_partner_id BETWEEN '1200' AND '1209' THEN 'GPOS'
      WHEN ops.pos_partner_id BETWEEN '1210' AND '1219' THEN 'ALOHA_ATO'
      WHEN ops.pos_partner_id BETWEEN '1220' AND '1229' THEN 'WEIBY'
      WHEN ops.pos_partner_id BETWEEN '1230' AND '1239' THEN 'OMEGA'
      WHEN ops.pos_partner_id BETWEEN '1240' AND '1249' THEN 'ZINGPOS'
      WHEN ops.pos_partner_id BETWEEN '1250' AND '1259' THEN 'XILNEX'
      ELSE 'UNKNOWN' END AS pos_partner,
    ops.result AS result_raw,
    ops.status_code,
    ops.message,
    org.merchant_key AS merchant_key,
    ml.RestaurantName AS merchant_name,
    ml.country AS country
  FROM `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_order_pos_status_view_prod` ops
  LEFT JOIN `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_orders_view_prod` o ON o.id = ops.order_id
  LEFT JOIN `tabsquare-data-sciences.all_skipque_cdc_data_prod.all_organization_view_prod` org ON o.restaurant_id = org.id
  LEFT JOIN `tabsquare-data-sciences.tabsquare_dw_lookups.master_merchant_list` ml ON ml.Merchant_id = org.merchant_key
  WHERE ops.created_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {{WINDOW_HOURS}} HOUR)
    AND DATE(o.changed_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND COALESCE(org.is_test_account, 0) != 1
    AND NOT (
      LOWER(ml.RestaurantName) LIKE '%test%'
      OR LOWER(ml.RestaurantName) LIKE '%demo%'
      OR LOWER(ml.RestaurantName) LIKE '%ts cafe%'
      OR LOWER(ml.RestaurantName) LIKE '%latest%'
    )
)
SELECT
  pos_partner,
  merchant_key,
  ANY_VALUE(merchant_name) AS merchant_name,
  ANY_VALUE(country) AS country,
  COUNT(*) AS total,
  COUNTIF(result_raw = 0) AS fails,
  COUNTIF(result_raw = 0 AND CAST(status_code AS STRING) = '504') AS timeouts,
  ANY_VALUE(IF(result_raw = 0, SUBSTR(message, 1, 200), NULL)) AS sample_message
FROM detail
GROUP BY pos_partner, merchant_key
HAVING total > 0
