let s:base_column_query = 'SELECT TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS'
let s:query = s:base_column_query.' ORDER BY COLUMN_NAME ASC'
let s:schema_query = 'SELECT TABLE_SCHEMA,TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS GROUP BY TABLE_SCHEMA,TABLE_NAME'
let s:count_query = 'SELECT COUNT(*) AS total FROM INFORMATION_SCHEMA.COLUMNS'
let s:table_column_query = s:base_column_query.' WHERE TABLE_NAME={db_tbl_name}'
let s:reserved_words = vim_dadbod_completion#reserved_keywords#get_as_dict()
let s:quote_rules = {
      \ 'camelcase': {val -> val =~# '[A-Z]' && val =~# '[a-z]'},
      \ 'space': {val -> val =~# '\s'},
      \ 'reserved_word': {val -> has_key(s:reserved_words, toupper(val))}
      \ }

function! s:map_and_filter(delimiter, list) abort
  return filter(
        \ map(a:list, { _, table -> map(split(table, a:delimiter), 'trim(v:val)') }),
        \ 'len(v:val) ==? 2'
        \ )
endfunction

function! s:should_quote(rules, val) abort
  if empty(trim(a:val))
    return 0
  endif

  let do_quote = 0

  for rule in a:rules
    let do_quote = s:quote_rules[rule](a:val)
    if do_quote
      break
    endif
  endfor

  return do_quote
endfunction

function! s:count_parser(index, result) abort
  return str2nr(get(a:result, a:index, 0))
endfunction

let s:postgres = {
      \ 'args': ['-A', '-c'],
      \ 'column_query': s:query,
      \ 'count_column_query': s:count_query,
      \ 'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \ 'functions_query': "SELECT routine_name FROM information_schema.routines WHERE routine_type='FUNCTION'",
      \ 'functions_parser': {list->list[1:-4]},
      \ 'schemas_query': s:schema_query,
      \ 'schemas_parser': function('s:map_and_filter', ['|']),
      \ 'quote': ['"', '"'],
      \ 'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
      \ 'column_parser': function('s:map_and_filter', ['|']),
      \ 'count_parser': function('s:count_parser', [1])
      \ }

let s:oracle_args = "echo \"SET linesize 4000;\nSET pagesize 4000;\n%s\" | "
let s:oracle_base_column_query = printf(s:oracle_args, "COLUMN column_name FORMAT a50;\nCOLUMN table_name FORMAT a50;\nSELECT C.table_name, C.column_name FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO' %s;")
let s:oracle = {
\   'column_parser': function('s:map_and_filter', ['\s\s\+']),
\   'column_query': printf(s:oracle_base_column_query, 'ORDER BY C.column_name ASC'),
\   'count_column_query': printf(s:oracle_args, "COLUMN total FORMAT 9999999;\nSELECT COUNT(*) AS total FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO';"),
\   'count_parser': function('s:count_parser', [1]),
\   'quote': ['"', '"'],
\   'requires_stdin': v:true,
\   'schemas_query': printf(s:oracle_args, "COLUMN owner FORMAT a20;\nCOLUMN table_name FORMAT a25;\nSELECT T.owner, T.table_name FROM all_tables T JOIN all_users U ON T.owner = U.username WHERE U.common = 'NO' ORDER BY T.table_name;"),
\   'schemas_parser': function('s:map_and_filter', ['\s\s\+']),
\   'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
\   'table_column_query': {table -> printf(s:oracle_base_column_query, "AND C.table_name='".table."'")},
\ }

if !exists('g:db_adapter_bigquery_region')
  let g:db_adapter_bigquery_region = 'region-us'
endif

let s:bigquery_schemas_query = "SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA" 

let s:bigquery_column_query = printf("
      \ SELECT table_name, column_name
      \ FROM `%s`.INFORMATION_SCHEMA.COLUMNS
      \ ", g:db_adapter_bigquery_region)

let s:bigquery_count_column_query = printf("
      \ SELECT count(*) as total
      \ FROM `%s`.INFORMATION_SCHEMA.COLUMNS
      \ ", g:db_adapter_bigquery_region)

let s:bigquery_schema_tables_query = printf("
      \ SELECT table_schema, table_name
      \ FROM `%s`.INFORMATION_SCHEMA.TABLES
      \ ", g:db_adapter_bigquery_region)

let s:bigquery_table_column_query = printf("
      \ SELECT table_schema, table_name
      \ FROM `%s`.INFORMATION_SCHEMA.TABLES
      \ WHERE TABLE_NAME={db_tbl_name}
      \ ", g:db_adapter_bigquery_region)

let s:bigquery = {
      \ 'callable': 'filter',
      \ 'args': ['--format=csv'],
      \ 'schemes_query': s:bigquery_schemas_query,
      \ 'schemes_tables_query': s:bigquery_schema_tables_query,
      \ 'table_column_query': {table -> substitute(s:bigquery_table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \ 'column_query': s:bigquery_column_query,
      \ 'count_column_query': s:bigquery_count_column_query,
      \ 'requires_stdin': v:true,
      \ 'column_parser': function('s:map_and_filter', [',']),
      \ }

let s:count_query = 'SELECT COUNT(*) AS total FROM INFORMATION_SCHEMA.COLUMNS'

let s:schemas = {
      \ 'bigquery': s:bigquery,
      \ 'postgres': s:postgres,
      \ 'postgresql': s:postgres,
      \ 'mysql': {
      \   'column_query': s:query,
      \   'count_column_query': s:count_query,
      \   'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \   'schemas_query': s:schema_query,
      \   'schemas_parser': function('s:map_and_filter', ['\t']),
      \   'requires_stdin': v:true,
      \   'quote': ['`', '`'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['\t']),
      \   'count_parser': function('s:count_parser', [1])
      \ },
      \ 'oracle': s:oracle,
      \ 'sqlite': {
      \   'args': ['-list'],
      \   'column_query': "SELECT m.name AS table_name, ii.name AS column_name FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table' ORDER BY column_name ASC;",
      \   'count_column_query': "SELECT count(*) AS total FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table';",
      \   'table_column_query': {table -> substitute("SELECT m.name AS table_name, ii.name AS column_name FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table' AND table_name={db_tbl_name};", '{db_tbl_name}', "'".table."'", '')},
      \   'quote': ['"', '"'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [1]),
      \ },
      \ 'sqlserver': {
      \   'args': ['-h-1', '-W', '-s', '|', '-Q'],
      \   'column_query': s:query,
      \   'count_column_query': s:count_query,
      \   'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \   'schemas_query': s:schema_query,
      \   'schemas_parser': function('s:map_and_filter', ['|']),
      \   'quote': ['[', ']'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [0])
      \ },
    \ }

function! vim_dadbod_completion#schemas#get(scheme)
  return get(s:schemas, a:scheme, {})
endfunction

function! vim_dadbod_completion#schemas#get_quotes_rgx() abort
  let open = []
  let close = []
  for db in values(s:schemas)
    if index(open, db.quote[0]) <= -1
      call add(open, db.quote[0])
    endif

    if index(close, db.quote[1]) <= -1
      call add(close, db.quote[1])
    endif
  endfor

  return {
        \ 'open': escape(join(open, '\|'), '[]'),
        \ 'close': escape(join(close, '\|'), '[]')
        \ }
endfunction

