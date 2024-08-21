-- Create #temp_table rfm_basic (Calculate Recency, Frequency, Monetary)
    drop table if exists rfm_basic;
    create temporary table rfm_basic
    (select CustomerID,
           datediff('2022-09-01', Max(Purchase_Date)) as Recency,
           round(1.00 * count(distinct Purchase_Date) / timestampdiff(year, created_date, '2022-09-01'), 2) as Frequency,
           round(sum(GMV) / timestampdiff(year, created_date, '2022-09-01')) as Monetary
    from customer_transaction_2 T
    join customer_registered_2 R
    on T.CustomerID = R.ID
    group by CustomerID);

select rfm_basic.Recency, count(*) from rfm_basic group by rfm_basic.Recency order by Recency;

-- step 1: Create table rfm_calculation and calculate quartiles of R,F,M
    -- Create rfm_calculation table
drop table if exists rfm_calculation;
create table rfm_calculation as
(select CustomerID, Recency, Frequency, Monetary,
       row_number() over (order by Recency) as rn_recency,
       row_number() over (order by Frequency) as rn_frequency,
       row_number() over (order by Monetary) as rn_monetary
from rfm_basic);

    -- Calculate rfm_quartiles
with r_quartile as
(select 'Q1' as Quartile, Recency
from rfm_calculation
where rn_recency = (select ceiling(count(*)*0.25) from rfm_calculation)
Union
select 'Q2' as Quartile, Recency
from rfm_calculation
where rn_recency = (select ceiling(count(*)*0.5) from rfm_calculation)
Union
select 'Q3' as Quartile, Recency
from rfm_calculation
where rn_recency = (select ceiling(count(*)*0.75) from rfm_calculation)),
    --
f_quartile as
(select 'Q1' as Quartile, Frequency
from rfm_calculation
where rn_frequency = (select ceiling(count(*)*0.25) from rfm_calculation)
Union
select 'Q2' as Quartile, Frequency
from rfm_calculation
where rn_frequency = (select ceiling(count(*)*0.5) from rfm_calculation)
Union
select 'Q3' as Quartile, Frequency
from rfm_calculation
where rn_frequency = (select ceiling(count(*)*0.75) from rfm_calculation)),
    --
m_quartile as
(select 'Q1' as Quartile, Monetary
from rfm_calculation
where rn_monetary = (select ceiling(count(*)*0.25) from rfm_calculation)
Union
select 'Q2' as Quartile, Monetary
from rfm_calculation
where rn_monetary = (select ceiling(count(*)*0.5) from rfm_calculation)
Union
select 'Q3' as Quartile, Monetary
from rfm_calculation
where rn_monetary = (select ceiling(count(*)*0.75) from rfm_calculation))
select r.Quartile, Recency, Frequency, Monetary from r_quartile r
join f_quartile f on r.Quartile = f.Quartile
join m_quartile m on f.Quartile = m.Quartile;

    -- Calculate R,F,M score
drop table if exists rfm_result_temp;
create temporary table rfm_result_temp as (
select CustomerID, Recency, Frequency, Monetary,
        case
            when Recency >= (select min(Recency) from rfm_calculation) and
                Recency < (select Recency from rfm_calculation
                                           where rn_recency = (select ceiling(count(*)*0.25) from rfm_calculation)) then '4'
            when Recency >= (select Recency from rfm_calculation
                                               where rn_recency = (select ceiling(count(*)*0.25) from rfm_calculation)) and
                Recency < (select Recency from rfm_calculation
                                               where rn_recency = (select ceiling(count(*)*0.5) from rfm_calculation)) then '3'
            when Recency >= (select Recency from rfm_calculation
                                               where rn_recency = (select ceiling(count(*)*0.5) from rfm_calculation)) and
                 Recency < (select Recency from rfm_calculation
                                                where rn_recency = (select ceiling(count(*)*0.75) from rfm_calculation)) then '2'
            else '1'
         end as R,
       case
           when Frequency >= (select min(Frequency) from rfm_calculation) and
               Frequency < (select Frequency from rfm_calculation
                                              where rn_frequency = (select ceiling(count(*)*0.25) from rfm_calculation)) then '1'
           when Frequency >= (select Frequency from rfm_calculation
                                              where rn_frequency = (select ceiling(count(*)*0.25) from rfm_calculation)) and
               Frequency < (select Frequency from rfm_calculation
                                              where rn_frequency = (select ceiling(count(*)*0.5) from rfm_calculation)) then '2'
           when Frequency >= (select Frequency from rfm_calculation
                                              where rn_frequency = (select ceiling(count(*)*0.5) from rfm_calculation)) and
                Frequency < (select Frequency from rfm_calculation
                                               where rn_frequency = (select ceiling(count(*)*0.75) from rfm_calculation)) then '3'
           else '4'
        end as F,
        case
            when Monetary >= (select min(Monetary) from rfm_calculation) and
                Monetary < (select Monetary from rfm_calculation
                                               where rn_monetary = (select ceiling(count(*)*0.25) from rfm_calculation)) then '1'
            when Monetary >= (select Monetary from rfm_calculation
                                               where rn_monetary = (select ceiling(count(*)*0.25) from rfm_calculation)) and
                Monetary < (select Monetary from rfm_calculation
                                               where rn_monetary = (select ceiling(count(*)*0.5) from rfm_calculation)) then '2'
            when Monetary >= (select Monetary from rfm_calculation
                                               where rn_monetary = (select ceiling(count(*)*0.5) from rfm_calculation)) and
                 Monetary < (select Monetary from rfm_calculation
                                                where rn_monetary = (select ceiling(count(*)*0.75) from rfm_calculation)) then '3'
            else '4'
         end as M
from rfm_calculation);
    -- Concat R.F,M score
drop table if exists rfm_result;
create table rfm_result as
(select *,
       concat(R, F, M) as 'Group'
from rfm_result_temp);

select * from rfm_result;

-- Customer segmentation
with customer_segmentation as (
select *,
       case
           when `Group` in (444, 434, 344, 334) then 'Champions'
           when `Group` in (443, 433, 344, 334, 343, 333) then 'Loyalists'
           when `Group` in (424, 423, 414, 413, 324, 323, 314, 313) then 'Recent Big Spenders'
           when `Group` in (422, 421, 412, 411, 322, 321, 312, 311) then 'Recent Small Spenders'
           when `Group` in (442, 441, 432, 431, 342, 341, 332, 331) then 'Promising'
           when `Group` in (243, 233, 223, 213, 143, 133, 123, 113) then 'At Risk customers'
           when `Group` in (244, 234, 224, 214, 144, 134, 124, 114) then 'Can’t Lose Them'
           when `Group` in (111) then 'Lost'
           else 'Hibernating'
       end as Segment
from rfm_result)
select * from customer_segmentation;



