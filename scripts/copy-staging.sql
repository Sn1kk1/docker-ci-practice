DO $copy$
DECLARE
  source_table record;
  target_table regclass;
  columns text;
  casts text;
  row_count bigint;
BEGIN
  FOR source_table IN SELECT * FROM source_counts ORDER BY table_name LOOP
    IF to_regclass(format('mattermost.%I', source_table.table_name)) IS NULL THEN
      RAISE EXCEPTION 'Missing staging table %', source_table.table_name;
    END IF;
    EXECUTE format('SELECT count(*) FROM mattermost.%I', source_table.table_name) INTO row_count;
    IF row_count <> source_table.row_count THEN
      RAISE EXCEPTION 'Incomplete pgloader transfer for % (% of % rows)',
        source_table.table_name, row_count, source_table.row_count;
    END IF;

    IF source_table.table_name IN ('db_migrations', 'db_lock', 'schema_migrations') THEN
      CONTINUE;
    END IF;

    target_table := to_regclass(format('public.%I', source_table.table_name));
    IF target_table IS NULL THEN
      IF row_count <> 0 THEN
        RAISE EXCEPTION 'No destination table for %', source_table.table_name;
      END IF;
      CONTINUE;
    END IF;

    SELECT string_agg(format('%I', target.attname), ', ' ORDER BY target.attnum),
           string_agg(format('%I::text::%s', target.attname,
                      format_type(target.atttypid, target.atttypmod)), ', ' ORDER BY target.attnum)
      INTO columns, casts
      FROM pg_attribute target
      JOIN pg_attribute staging ON staging.attname = target.attname
     WHERE target.attrelid = target_table AND target.attnum > 0 AND NOT target.attisdropped
       AND target.attgenerated = ''
       AND staging.attrelid = to_regclass(format('mattermost.%I', source_table.table_name))
       AND staging.attnum > 0 AND NOT staging.attisdropped;

    IF columns IS NULL THEN
      RAISE EXCEPTION 'No matching columns for %', source_table.table_name;
    END IF;
    EXECUTE format('DELETE FROM %s', target_table);
    EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM mattermost.%I',
                   target_table, columns, casts, source_table.table_name);
    GET DIAGNOSTICS row_count = ROW_COUNT;
    IF row_count <> source_table.row_count THEN
      RAISE EXCEPTION 'Incomplete PostgreSQL copy for %', source_table.table_name;
    END IF;
  END LOOP;
END
$copy$;
