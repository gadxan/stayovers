-- Exact row count of every table that holds Stayover data, as "schema.table,count".
-- Used by the nightly backup (live database) and by restores (the copy) so the two can be compared.
select t.table_schema || '.' || t.table_name || ',' ||
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from %I.%I', t.table_schema, t.table_name), false, true, '')))[1]::text
from information_schema.tables t
where t.table_type = 'BASE TABLE'
  and (t.table_schema = 'public'
       or (t.table_schema, t.table_name) in (('auth', 'users'), ('storage', 'objects'), ('storage', 'buckets')))
order by 1;
